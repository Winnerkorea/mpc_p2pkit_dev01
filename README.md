# 📡 P2PSession.swift 설명서

이 문서는 `P2PSession.swift` 파일의 구조와 기능에 대한 설명을 담고 있습니다. 본 파일은 **MultipeerConnectivity 프레임워크**를 사용하여, **iOS 장치 간 P2P(Peer-to-Peer) 통신**을 가능하게 하는 핵심 클래스입니다.

---

## 🧩 주요 구성요소

### 🔶 `P2PSessionDelegate` 프로토콜

P2P 세션에서 발생하는 이벤트들을 앱 외부에서 처리할 수 있도록 정의한 델리게이트 프로토콜입니다.

- `didUpdate`: 피어 상태 변경 시 호출
- `didReceive`: 데이터 수신 시 호출
- `shouldAccept`: 연결 요청 수락 여부 결정

---

### 🔷 `P2PSession` 클래스

MultipeerConnectivity를 사용한 P2P 통신을 관리하는 메인 클래스입니다. 연결 관리, 피어 검색, 데이터 송수신 등을 담당합니다.

#### 📌 주요 프로퍼티

- `myPeer`: 현재 장치를 나타내는 Peer 객체
- `maxPeerCount`: 최대 연결 가능한 피어 수
- `session`: 실제 데이터 송수신을 처리하는 MCSession
- `advertiser`: 피어에게 자신을 광고
- `browser`: 주변 피어 검색
- `foundPeers`, `discoveryInfos`, `sessionStates`: 연결 상태 관리용 캐시

---

## ⚙️ 주요 기능

### 🔸 초기화 및 시작

```swift
init(myPeer: Peer, maxPeerCount: Int = 4)
func start()
```

- 세션/브라우저/광고자 초기화 및 델리게이트 설정
- `start()` 함수로 광고 및 브라우징 시작

---

### 🔸 연결 관리

```swift
func disconnect()
func connectionState(for peer: MCPeerID) -> MCSessionState?
```

- 연결 해제 및 세션 종료
- 피어의 연결 상태 조회

---

### 🔸 데이터 전송

```swift
func send(_ encodable: Encodable, to peers: [MCPeerID], reliable: Bool)
func send(data: Data, to peers: [MCPeerID], reliable: Bool)
```

- Codable 데이터를 JSON으로 인코딩하여 전송 가능
- `reliable: Bool` 옵션으로 신뢰성 설정 (순서 보장 여부)

---

### 🔸 연결 상태 유지 테스트 (Loopback Test)

```swift
startLoopbackTest(_ peerID: MCPeerID)
receiveLoopbackTest(_ session: MCSession, didReceive json: [String: Any], fromPeer peerID: MCPeerID)
```

- `ping` → `pong` 응답을 통해 연결 상태 확인
- 일정 시간 응답이 없으면 상대에게 `pongNotReceived` 메시지로 재연결 요청

---

## 🌐 델리게이트 구현

### `MCSessionDelegate`

- 연결 상태 변경 감지
- 데이터 수신 처리
- 스트림/리소스 송수신은 명시적으로 비활성화 (fatalError)

### `MCNearbyServiceBrowserDelegate`

- 피어를 발견하고 연결 초대 시도
- 피어 유실 감지 및 상태 초기화

### `MCNearbyServiceAdvertiserDelegate`

- 피어로부터의 연결 요청 수락 여부 판단
- 광고 시작 실패 시 로그 출력

---

## 🔁 피어 초대 로직

```swift
private func invitePeerIfNeeded(_ peerID: MCPeerID)
```

- 피어 ID를 비교하여 한 쪽만 초대
- 재시도 타이머와 횟수를 기반으로 초대 로직 제어 (`InviteHistory` 사용)
- 최대 재시도 횟수를 초과하면 세션 재설정 요청

---

## 🧠 내부 구조체

### `InviteHistory`

- 초대 시도 횟수
- 다음 초대 가능 시간
- 초대 예약 여부

### `DiscoveryInfo`

- 각 피어의 고유 discoveryId 저장

---

## 🧪 디버그용 함수

- `prettyPrint(...)`: 디버깅 메시지 출력
- `connectedPeers`, `allPeers`: 현재 연결된 피어 목록 확인

---

## ✅ 기본 구현된 델리게이트 (기본 수락)

```swift
extension P2PSessionDelegate {
    func p2pSession(_ session: P2PSession, shouldAccept peerID: MCPeerID) -> Bool {
        return true
    }
}
```

- 기본적으로 **모든 연결 요청을 수락**하도록 구현되어 있음.

---

## 📎 관련 기술

- **MultipeerConnectivity**
- **MCSession / MCNearbyServiceAdvertiser / MCNearbyServiceBrowser**
- **Codable, JSONEncoder/Decoder**
- **Thread-Safety (NSLock 사용)**

---

## 👩‍💻 예시 사용 흐름

```swift
let myPeer = Peer(...) // 고유 ID 생성
let session = P2PSession(myPeer: myPeer)
session.delegate = self
session.start()
```

---
