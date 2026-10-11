import SwiftUI

/// Mini 3D TV Robot Head mascot rendered inside the collapsed preview capsule (State 2: Idle Hover).
struct LiveCharacterView: View {
    var state: RobotHeadState = .idle
    var pointSize: CGFloat = 22

    var body: some View {
        RobotHeadView(
            state: state,
            shape: .rectangle,
            size: pointSize,
            color: "#2563EB",
            trimColor: "#93A6C8",
            screenColor: "#E8F2FF",
            antenna: false,
            floorShadow: false
        )
        .frame(width: pointSize * 1.3, height: pointSize)
    }
}
