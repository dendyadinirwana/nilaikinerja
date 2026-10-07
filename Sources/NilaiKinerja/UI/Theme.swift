import SwiftUI

/// Semantic design tokens for NilaiKinerja.
///
/// Centralises the dark slate surfaces and sky-blue accent colours used
/// across the notch panel, forms, cards, and Mochi stages.
enum NKTheme {
    /// Deep dark notch canvas (#16181F)
    static let canvasBackground = Color(hex: 0x16181F)
    /// Card / pill dark surface (#141518)
    static let cardBackground = Color(hex: 0x141518)
    /// Sky Blue accent (#60A5FA)
    static let accentBlue = Color(hex: 0x60A5FA)
    /// Primary action blue (#2563EB)
    static let primaryBlue = Color(hex: 0x2563EB)
    /// Border / focus blue (#3B82F6)
    static let borderBlue = Color(hex: 0x3B82F6)
    /// Deep navy chat bubble (#1E3A8A)
    static let navyBubble = Color(hex: 0x1E3A8A)
    /// Success green (#059669)
    static let successGreen = Color(hex: 0x059669)
    /// Bright success green (#34D399)
    static let successGreenBright = Color(hex: 0x34D399)
    /// Danger red (#EF4444)
    static let dangerRed = Color(hex: 0xEF4444)
    /// Soft danger red (#F87171)
    static let dangerRedSoft = Color(hex: 0xF87171)
    /// Accent purple (#8B5CF6)
    static let purple = Color(hex: 0x8B5CF6)
}
