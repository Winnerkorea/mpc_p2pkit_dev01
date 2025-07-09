//
//  GameView.swift
//  P2PKitDemo
//
//  Created by 이주현 on 7/8/25.
//

import SwiftUI
import P2PKit

struct GameView: View {
    // 각 판의 상태 (좌표, 플레이어 이름) (예: moves.value["0,1"] = "🐸 Judy’s iPhone")
    @StateObject private var moves = P2PSyncedObservable(name: "TicTacToeMoves", initial: [String: String]())
    // 현재 턴인 플레이어의 이름
    // @StateObject private var currentTurn = P2PNetwork.currentTurnPlayerName

    // 모든 플레이어 배열
    private var allPlayers: [Peer] {
        [P2PNetwork.myPeer] + P2PNetwork.connectedPeers // 나 자신 + 연결된 사람
    }
    private var myDisplayName: String {
        P2PNetwork.myPeer.displayName // 나 자신 -> '나:'를 붙이기 위함
    }

    var body: some View {
        VStack {
//            VStack(alignment: .leading, spacing: 8) {
//                ForEach(allPlayers.map { $0.displayName }, id: \.self) { name in
//                    
//                    let isMe = name == myDisplayName
//                    let displayText = isMe ? "나: \(name)" : name
//
//                    Text(displayText)
//                        .padding(6)
//                        .background(currentTurn.value == name ? Color.yellow.opacity(0.3) : Color.clear)
//                        .cornerRadius(8)
//                        .overlay(
//                            RoundedRectangle(cornerRadius: 8)
//                                .stroke(currentTurn.value == name ? Color.orange : Color.clear, lineWidth: 2)
//                        )
//                }
//            }
//            .padding(.bottom)
//
//            ForEach(0..<3, id: \.self) { row in
//                HStack {
//                    ForEach(0..<3, id: \.self) { column in
//                        let key = "\(row),\(column)"
//                        Button(action: {
//                            // 1. 내 차례인지, 2. 칸이 비어있는지 확인
//                            if currentTurn.value == myDisplayName && moves.value[key] == nil {
//                                // 3. 칸에 내 이름을 기록
//                                moves.value[key] = myDisplayName
//
//                                // 4. 다음 차례 플레이어 지정, 다음 차례로 턴 넘김
//                                // 턴 순서는 플레이어 이름을 사전순으로 정렬해서 자동으로 결정
//                                let playerNames = allPlayers.map { $0.displayName }.sorted()
//                                if let currentIdx = playerNames.firstIndex(of: myDisplayName) {
//                                    let nextIdx = (currentIdx + 1) % playerNames.count
//                                    currentTurn.value = playerNames[nextIdx]
//                                }
//                            }
//                        }) {
//                            Text(symbolForPlayer(name: moves.value[key]))
//                                .frame(width: 60, height: 60)
//                                .background(Color.gray.opacity(0.2))
//                                .border(Color.black)
//                                .font(.largeTitle)
//                        }
//                        .disabled(currentTurn.value != myDisplayName || moves.value[key] != nil)
//                    }
//                }
//            }

            Text("연결된 사람 수: \(P2PNetwork.connectedPeers.count + 1)")

            // 연결된 사람 이름 표시
            VStack(alignment: .leading, spacing: 4) {
                ForEach([P2PNetwork.myPeer] + P2PNetwork.connectedPeers, id: \.id) { peer in
                    Text(peer.displayName)
                        .font(.subheadline)
                        .foregroundColor(peer.id == P2PNetwork.myPeer.id ? .blue : .primary)
                }
            }
            
        }
        .padding()
    }

    private func symbolForPlayer(name: String?) -> String {
        guard let name = name else { return "" }
        let sortedPlayers = allPlayers.map { $0.displayName }.sorted()
        if let index = sortedPlayers.firstIndex(of: name) {
            return ["X", "O", "△", "□", "☆"][index % 5] // 최대 5명 지원
        }
        return "?"
    }
}

#Preview {
    GameView()
}

