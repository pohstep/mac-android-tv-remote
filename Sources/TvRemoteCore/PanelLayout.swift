import Foundation

/// Popover size. Width stays 376. Height is the measured content until that
/// would pass the visible screen; then the panel stops at the screen and scrolls.
public enum PanelLayout {
    public static let width: Double = 376
    public static let screenMargin: Double = 12
    public static let minimumHeight: Double = 200

    public static func height(content: Double, visibleScreen: Double) -> Double {
        let cap = max(minimumHeight, visibleScreen - screenMargin)
        return min(max(content, minimumHeight), cap)
    }
}
