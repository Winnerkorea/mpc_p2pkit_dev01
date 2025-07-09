//
//  P2PNetworking.swift
//  P2PKitExample
//
//  Created by Paige Sun on 5/2/24.
//

import MultipeerConnectivity

// MARK: - P2PSessionDelegate 프로토콜 정의
/// P2P 세션에서 발생하는 이벤트를 델리게이트 객체에게 전달하기 위한 프로토콜입니다.
/// 연결 상태 업데이트, 데이터 수신, 연결 수락 여부를 앱 외부 로직으로 위임하여 처리할 수 있도록 합니다.
protocol P2PSessionDelegate: AnyObject {
    /// 연결된 피어의 상태가 변경될 때 호출됩니다.
    /// - Parameters:
    ///   - session: 연결 세션 인스턴스
    ///   - peer: 연결 상태가 변경된 피어
    func p2pSession(_ session: P2PSession, didUpdate peer: Peer) -> Void
    /// 피어로부터 데이터를 수신했을 때 호출됩니다.
    /// - Parameters:
    ///   - session: 연결 세션 인스턴스
    ///   - data: 수신된 원본 데이터
    ///   - json: 수신된 데이터의 JSON 표현 (가능한 경우)
    ///   - peerID: 데이터를 보낸 피어의 ID
    func p2pSession(_ session: P2PSession, didReceive data: Data, dataAsJson json: [String: Any]?, from peerID: MCPeerID)
    /// 새 피어의 연결 요청을 수락할지 여부를 결정합니다.
    /// - Parameters:
    ///   - session: 연결 세션 인스턴스
    ///   - peerID: 연결을 요청한 피어의 ID
    /// - Returns: 연결을 수락할 경우 true, 거절할 경우 false
    func p2pSession(_ session: P2PSession, shouldAccept peerID: MCPeerID) -> Bool
}


class P2PSession: NSObject {
    weak var delegate: P2PSessionDelegate?
    
    let myPeer: Peer
    private let myDiscoveryInfo: DiscoveryInfo
    private let maxPeerCount: Int
    
    private let session: MCSession
    private let advertiser: MCNearbyServiceAdvertiser
    private let browser: MCNearbyServiceBrowser
    
    private var peersLock = NSLock()
    private var foundPeers = Set<MCPeerID>()  // protected with peersLock
    private var discoveryInfos = [MCPeerID: DiscoveryInfo]() // protected with peersLock
    private var sessionStates = [MCPeerID: MCSessionState]() // protected with peersLock
    private var invitesHistory = [MCPeerID: InviteHistory]() // protected with peersLock
    private var loopbackTestTimers = [MCPeerID: Timer]() // protected with peersLock
    
    
    var connectedPeers: [Peer] {
        peersLock.lock(); defer { peersLock.unlock() }
        let peerIDs = session.connectedPeers.filter {
            foundPeers.contains($0) && sessionStates[$0] == .connected
        }
        prettyPrint(level: .debug, "connectedPeers: \(peerIDs)")
        return peerIDs.compactMap { peer(for: $0) }
    }
    
    // Debug only, use connectedPeers instead.
    var allPeers: [Peer] {
        peersLock.lock(); defer { peersLock.unlock() }
        let peerIDs = session.connectedPeers.filter {
            foundPeers.contains($0)
        }
        prettyPrint(level: .debug, "all peers: \(peerIDs)")
        return peerIDs.compactMap { peer(for: $0) }
    }
    
    // Callers need to protect this with peersLock
    private func peer(for peerID: MCPeerID) -> Peer? {
        guard let discoverID = discoveryInfos[peerID]?.discoveryId else { return nil }
        return Peer(peerID, id: discoverID)
    }
    
    /// P2PSession의 초기화 함수입니다.
    /// - Parameters:
    ///   - myPeer: 자신을 나타내는 Peer 객체
    ///   - maxPeerCount: 연결 가능한 최대 피어 수 (기본값은 4명)
    init(myPeer: Peer, maxPeerCount: Int = 4) {
        self.myPeer = myPeer  // 자신의 피어 정보를 저장
        self.myDiscoveryInfo = DiscoveryInfo(discoveryId: myPeer.id)  // 자신의 discovery ID 설정
        self.maxPeerCount = maxPeerCount  // 최대 연결 가능한 피어 수 저장
        discoveryInfos[myPeer.peerID] = self.myDiscoveryInfo  // 자신의 discovery 정보 등록
        
        let myPeerID = myPeer.peerID  // MultipeerConnectivity에서 사용할 PeerID 생성
        
        // 보안을 적용한 MCSession 인스턴스 생성
        session = MCSession(peer: myPeerID, securityIdentity: nil, encryptionPreference: .required)
        
        // 주변 피어에게 광고를 시작할 Advertiser 생성 (discovery 정보 포함)
        advertiser = MCNearbyServiceAdvertiser(peer: myPeerID,
                                               discoveryInfo: ["discoveryId": "\(myDiscoveryInfo.discoveryId)"],
                                               serviceType: P2PConstants.networkChannelName)
        
        // 주변 피어를 검색할 Browser 생성
        browser = MCNearbyServiceBrowser(peer: myPeerID, serviceType: P2PConstants.networkChannelName)
        
        super.init()  // NSObject 초기화
        
        // 세션, 광고자, 브라우저에 대한 델리게이트 설정
        session.delegate = self
        advertiser.delegate = self
        browser.delegate = self
    }
    
    func start() {
        advertiser.startAdvertisingPeer()
        browser.startBrowsingForPeers()
        delegate?.p2pSession(self, didUpdate: myPeer)
    }
    
    deinit {
        disconnect()
    }
    
    func disconnect() {
        prettyPrint("disconnect")
        
        session.disconnect()
        session.delegate = nil
        
        advertiser.stopAdvertisingPeer()
        advertiser.delegate = nil
        
        browser.stopBrowsingForPeers()
        browser.delegate = nil
    }
    
    func connectionState(for peer: MCPeerID) -> MCSessionState? {
        peersLock.lock(); defer { peersLock.unlock() }
        return sessionStates[peer]
    }
    
    func makeBrowserViewController() -> MCBrowserViewController {
        return MCBrowserViewController(browser: browser, session: session)
    }
    
    // MARK: - Sending
    
    func send(_ encodable: Encodable, to peers: [MCPeerID] = [], reliable: Bool) {
        
        do {
            let data = try JSONEncoder().encode(encodable)
            send(data: data, to: peers, reliable: reliable)
        } catch {
            prettyPrint(level: .error, "Could not encode: \(error.localizedDescription)")
        }
    }
    
    // Reliable maintains order and doesn't drop data but is slower.
    func send(data: Data, to peers: [MCPeerID] = [], reliable: Bool) {
        let sendToPeers = peers.isEmpty ? session.connectedPeers : peers
        guard !sendToPeers.isEmpty else {
            return
        }
        
        do {
            try session.send(data, toPeers: sendToPeers, with: reliable ? .reliable : .unreliable)
        } catch {
            prettyPrint(level: .error, "error sending data to peers: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Loopback Test
    // Test whether a connection is still alive.
    
    // Call with within a peersLock.
    private func startLoopbackTest(_ peerID: MCPeerID) {
        prettyPrint("Sending Ping to \(peerID.displayName)")
        send(["ping": ""], to: [peerID], reliable: true)
        
        // If A pings B but B doesn't pong back, B disconnected or unable to respond. In that case A tells B to reset.
        loopbackTestTimers[peerID] = Timer.scheduledTimer(withTimeInterval: 2, repeats: false, block: { [weak self] timer in
            prettyPrint("Did not receive pong from \(peerID.displayName). Asking it to reset.")
            self?.send(["pongNotReceived": ""], to: [peerID], reliable: true)
        })
    }
    
    private func receiveLoopbackTest(_ session: MCSession, didReceive json: [String: Any], fromPeer peerID: MCPeerID) -> Bool {
        if json["ping"] as? String == "" {
            prettyPrint("Received ping from \(peerID.displayName). Sending Pong.")
            send(["pong": ""], to: [peerID], reliable: true)
            return true
        } else if json["pong"] as? String == "" {
            prettyPrint("Received Pong from \(peerID.displayName)")
            peersLock.lock()
            if sessionStates[peerID] == nil {
                sessionStates[peerID] = .connected
            }
            loopbackTestTimers[peerID]?.invalidate()
            loopbackTestTimers[peerID] = nil
            let peer = peer(for: peerID)
            peersLock.unlock()
            
            if let peer = peer {
                delegate?.p2pSession(self, didUpdate: peer)
            }
            return true
        } else if json["pongNotReceived"] as? String == "" {
            prettyPrint("Resetting because [\(peerID.displayName)] sent ping to me but didn't receive a pong back.")
            P2PNetwork.resetSession()
        }
        return false
    }
}

// MARK: - MCSessionDelegate

extension P2PSession: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        prettyPrint("Session state of [\(peerID.displayName)] changed to [\(state)]")
        
        peersLock.lock()
        sessionStates[peerID] = state
        
        switch state {
        case .connected:
            foundPeers.insert(peerID)
        case .connecting:
            break
        case .notConnected:
            invitePeerIfNeeded(peerID)
        default:
            fatalError(#function + " - Unexpected multipeer connectivity state.")
        }
        let peer = peer(for: peerID)
        peersLock.unlock()
        
        if let peer = peer {
            delegate?.p2pSession(self, didUpdate: peer)
        }
    }
    
    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        if let json = json, receiveLoopbackTest(session, didReceive: json, fromPeer: peerID) {
            return
        }
        
        // Recieving data is from different threads, so don't get Peer.Identifier here.
        delegate?.p2pSession(self, didReceive: data, dataAsJson: json, from: peerID)
    }
    
    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {
        fatalError("This service does not send/receive streams.")
    }
    
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {
        fatalError("This service does not send/receive resources.")
    }
    
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {
        fatalError("This service does not send/receive resources.")
    }
    
    func session(_ session: MCSession, didReceiveCertificate certificate: [Any]?, fromPeer peerID: MCPeerID, certificateHandler: @escaping (Bool) -> Void) {
        certificateHandler(true)
    }
}

// MARK: - Browser Delegate

extension P2PSession: MCNearbyServiceBrowserDelegate {
    public func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        if let discoveryId = info?["discoveryId"], discoveryId != myDiscoveryInfo.discoveryId {
            prettyPrint("Found Peer: [\(peerID)], with id: [\(discoveryId)]")
            
            peersLock.lock()
            foundPeers.insert(peerID)
            
            // Each device has one DiscoveryId. When a new MCPeerID is found, cleanly remove older MCPeerIDs from the same device.
            for (otherPeerId, otherDiscoveryInfo) in discoveryInfos {
                if otherDiscoveryInfo.discoveryId == discoveryId && otherPeerId != peerID {
                    foundPeers.remove(otherPeerId)
                    discoveryInfos[otherPeerId] = nil
                    sessionStates[otherPeerId] = nil
                    invitesHistory[otherPeerId] = nil
                }
            }
            discoveryInfos[peerID] = DiscoveryInfo(discoveryId: discoveryId)

            if sessionStates[peerID] == nil, session.connectedPeers.contains(peerID) {
                startLoopbackTest(peerID)
            }
            
            invitePeerIfNeeded(peerID)
            let peer = peer(for: peerID)
            peersLock.unlock()
            
            if let peer = peer {
                delegate?.p2pSession(self, didUpdate: peer)
            }
        }
    }
    
    public func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        prettyPrint("Lost peer: [\(peerID.displayName)]")
        
        peersLock.lock()
        foundPeers.remove(peerID)
        
        // When a peer enters background, session.connectedPeers still contains that peer.
        // Setting this to nil ensures we make a loopback test to test the connection.
        sessionStates[peerID] = nil
        let peer = peer(for: peerID)
        peersLock.unlock()
        
        if let peer = peer {
            delegate?.p2pSession(self, didUpdate: peer)
        }
    }
}

// MARK: - MCNearbyServiceAdvertiserDelegate

extension P2PSession: MCNearbyServiceAdvertiserDelegate {
    
    /// 연결 요청을 받았을 때 호출됨. 현재 연결된 피어 수가 최대 허용 수를 초과하지 않고,
    /// delegate가 수락을 허용하는 경우에만 초대 수락.
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser,
                    didReceiveInvitationFromPeer peerID: MCPeerID,
                    withContext context: Data?,
                    invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        let currentConnectedCount = session.connectedPeers.count
        if isNotConnected(peerID),
           currentConnectedCount < maxPeerCount,
           delegate?.p2pSession(self, shouldAccept: peerID) == true {
            prettyPrint("Accepting Peer invite from [\(peerID.displayName)]")
            invitationHandler(true, self.session)
        } else {
            prettyPrint("Rejecting Peer invite from [\(peerID.displayName)] due to capacity limit.")
            invitationHandler(false, nil)
        }
    }
    
    /// advertising 시작 실패 시 호출됨. 네트워크 오류 등의 정보를 출력함.
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser,
                    didNotStartAdvertisingPeer error: Error) {
        prettyPrint(level: .error, "Error: \(error.localizedDescription)")
    }
}

// MARK: - 피어 초대 관련 (Invite Peers)

extension P2PSession {
    // 이 함수는 peersLock() 내부에서 호출되어야 합니다.
    private func invitePeerIfNeeded(_ peerID: MCPeerID) {
        func invitePeer(attempt: Int) {
            prettyPrint("Inviting peer: [\(peerID.displayName)]. Attempt \(attempt)")
            browser.invitePeer(peerID, to: session, withContext: nil, timeout: inviteTimeout)
            invitesHistory[peerID] = InviteHistory(attempt: attempt, nextInviteAfter: Date().addingTimeInterval(retryWaitTime))
        }
        
        // 두 장치 간에는 한쪽만 초대를 보냅니다.
        guard let otherDiscoverID = discoveryInfos[peerID]?.discoveryId,
              myDiscoveryInfo.discoveryId < otherDiscoverID,
              isNotConnected(peerID) else {
            return
        }
        
        let retryWaitTime: TimeInterval = 3 // 초대 재시도까지 기다리는 시간
        let maxRetries = 3 // 최대 재시도 횟수
        let inviteTimeout: TimeInterval = 8 // 초대 타임아웃 시간
        
        if let prevInvite = invitesHistory[peerID] {
            if prevInvite.nextInviteAfter.timeIntervalSinceNow < -(inviteTimeout + 3) {
                // 충분히 기다렸다면 1번째 시도부터 다시 시작합니다.
                invitePeer(attempt: 1)
                
            } else if prevInvite.nextInviteAfter.timeIntervalSinceNow < 0 {
                // 충분히 기다렸으므로 다음 초대 시도를 진행합니다.
                if prevInvite.attempt < maxRetries {
                    invitePeer(attempt: prevInvite.attempt + 1)
                } else {
                    prettyPrint(level: .error, "Max \(maxRetries) invite attempts reached for [\(peerID.displayName)].")
                    P2PNetwork.resetSession()
                }
                
            } else {
                if !prevInvite.nextInviteScheduled {
                    // 다음 초대를 시도하기엔 아직 이르므로 예약합니다.
                    prettyPrint("Inviting peer later: [\(peerID.displayName)] with attempt \(prevInvite.attempt + 1)")
                    
                    DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + retryWaitTime + 0.1) { [weak self] in
                        guard let self = self else { return }
                        self.peersLock.lock()
                        self.invitesHistory[peerID]?.nextInviteScheduled = false
                        self.invitePeerIfNeeded(peerID)
                        self.peersLock.unlock()
                    }
                    invitesHistory[peerID]?.nextInviteScheduled = true
                } else {
                    // 피어 [\(peerID.displayName)]에게 초대할 필요 없음. 다음 초대는 이미 예약되어 있음.
                    prettyPrint("No need to invite peer [\(peerID.displayName)]. Next invite is already scheduled.")
                }
            }
        } else {
            invitePeer(attempt: 1)
        }
    }
    
    private func isNotConnected(_ peerID: MCPeerID) -> Bool {
        // 연결되지 않은 상태인지 확인하는 유틸리티 함수
        return !session.connectedPeers.contains(peerID)
        && sessionStates[peerID] != .connecting
        && sessionStates[peerID] != .connected
    }
}

// MARK: - P2PSessionDelegate 기본 구현
/// 피어 연결 요청을 수락할지 여부를 판단하는 기본 구현.
/// 기본값은 true이며, 모든 연결 요청을 수락합니다.
extension P2PSessionDelegate {
    func p2pSession(_ session: P2PSession, shouldAccept peerID: MCPeerID) -> Bool {
        return true
    }
}

/// 초대 재시도를 위한 상태 저장 구조체.
/// 시도 횟수, 다음 초대 시각, 예약 여부를 포함합니다.
private struct InviteHistory {
    let attempt: Int
    let nextInviteAfter: Date
    var nextInviteScheduled: Bool = false
}

// MARK: - Private

private struct DiscoveryInfo {
    let discoveryId: Peer.Identifier
}
