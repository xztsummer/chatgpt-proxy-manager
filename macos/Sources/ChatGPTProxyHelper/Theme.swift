import SwiftUI
import AppKit

// MARK: - 调色板（浅色 / 深色 双套，动态跟随）

enum Palette {
    /// --render-preview 离屏渲染时强制指定外观，避免依赖系统 appearance
    static var appearanceOverride: ColorScheme?

    static func color(_ light: String, _ dark: String) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark: Bool
            if let override = appearanceOverride {
                isDark = override == .dark
            } else {
                isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            }
            return NSColor(hex: isDark ? dark : light)
        })
    }

    static let window = color("#F3F4F9", "#15161B")
    static let card = color("#FFFFFF", "#22242C")
    static let subtle = color("#EEF0F6", "#1A1C22")
    static let hairline = color("#E8E9F0", "#32343E")
    static let primaryText = color("#191B22", "#EDEEF2")
    static let secondaryText = color("#6B7280", "#9CA3AF")
    static let tertiaryText = color("#9CA3AF", "#6B7280")
    static let primary = color("#5157E8", "#6E74F2")
    static let primaryDeep = color("#3F44D6", "#5A60E8")
    static let green = color("#10B981", "#34D399")
    static let red = color("#EF4444", "#F87171")
    static let amber = color("#F59E0B", "#FBBF24")
    static let blue = color("#3B82F6", "#60A5FA")
}

extension NSColor {
    convenience init(hex: String) {
        var value = hex.trimmingCharacters(in: .whitespaces)
        if value.hasPrefix("#") { value.removeFirst() }
        var hexValue: UInt64 = 0
        Scanner(string: value).scanHexInt64(&hexValue)
        self.init(srgbRed: CGFloat((hexValue >> 16) & 0xFF) / 255,
                  green: CGFloat((hexValue >> 8) & 0xFF) / 255,
                  blue: CGFloat(hexValue & 0xFF) / 255,
                  alpha: 1)
    }
}

// MARK: - 主题

enum AppTheme: String, CaseIterable, Identifiable {
    case light, dark, system

    var id: String { rawValue }
    var label: String {
        switch self {
        case .light: "浅色"
        case .dark: "深色"
        case .system: "跟随系统"
        }
    }
    var icon: String {
        switch self {
        case .light: "sun.max.fill"
        case .dark: "moon.fill"
        case .system: "display"
        }
    }
    var colorScheme: ColorScheme? {
        switch self {
        case .light: .light
        case .dark: .dark
        case .system: nil
        }
    }
}

// MARK: - 按钮样式

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .background(
                LinearGradient(colors: [Palette.primary, Palette.primaryDeep],
                               startPoint: .leading, endPoint: .trailing),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .opacity(configuration.isPressed ? 0.85 : (isEnabled ? 1 : 0.45))
    }
}

struct NeutralButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(Palette.card, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Palette.hairline))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

struct DangerButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Palette.red)
            .background(Palette.red.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .opacity(configuration.isPressed ? 0.7 : (isEnabled ? 1 : 0.45))
    }
}
