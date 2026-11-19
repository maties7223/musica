import SwiftUI

enum Theme {
    static let accent = Color(red: 0.98, green: 0.24, blue: 0.42)
    static let accent2 = Color(red: 0.60, green: 0.30, blue: 0.96)

    static var gradient: LinearGradient {
        LinearGradient(colors: [accent, accent2], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}
