import AppKit
import SwiftUI

extension Color {
    static let kotobaGreen = Color(red: 0.17, green: 0.32, blue: 0.26)
    static let kotobaLime = Color(red: 0.85, green: 0.93, blue: 0.68)
    static let kotobaPaper = Color(red: 0.96, green: 0.97, blue: 0.94)
}

struct CaptionRGB: Codable, Equatable {
    var red: Double
    var green: Double
    var blue: Double
    var color: Color { Color(red: red, green: green, blue: blue) }
    var isLight: Bool { red * 0.2126 + green * 0.7152 + blue * 0.0722 > 0.58 }
    static let forest = CaptionRGB(red: 0.07, green: 0.12, blue: 0.10)
    static let black = CaptionRGB(red: 0, green: 0, blue: 0)
    static let white = CaptionRGB(red: 1, green: 1, blue: 1)
    init(red: Double, green: Double, blue: Double) { self.red = red; self.green = green; self.blue = blue }
    init(_ color: Color) {
        let rgb = NSColor(color).usingColorSpace(.sRGB) ?? .black
        self.init(red: rgb.redComponent, green: rgb.greenComponent, blue: rgb.blueComponent)
    }
}

struct CaptionAppearance: Codable, Equatable {
    var width: Double = 900
    var height: Double = 220
    var automaticHeight = true
    var sourceFontSize: Double = 30
    var translationFontSize: Double = 25
    var background = CaptionRGB.forest
    var opacity: Double = 0.86
    var foreground: Color { background.isLight ? Color(white: 0.08) : .white }
    var translationForeground: Color { background.isLight ? Color(red: 0.10, green: 0.30, blue: 0.22) : .kotobaLime }
    var textShadow: Color { background.isLight ? .white.opacity(0.65) : .black.opacity(0.7) }
    static let storageKey = "captionAppearance.v2"

    func normalized() -> Self {
        func safe(_ value: Double, _ lower: Double, _ upper: Double, _ fallback: Double) -> Double {
            value.isFinite ? clamp(value, lower, upper) : fallback
        }
        var result = self
        result.width = safe(width, 320, 2000, 900)
        result.height = safe(height, 100, 900, 220)
        result.sourceFontSize = safe(sourceFontSize, 14, 90, 30)
        result.translationFontSize = safe(translationFontSize, 14, 90, 25)
        result.opacity = safe(opacity, 0, 1, 0.86)
        result.background = CaptionRGB(red: safe(background.red, 0, 1, 0.07), green: safe(background.green, 0, 1, 0.12), blue: safe(background.blue, 0, 1, 0.10))
        return result
    }
    func save(to preferences: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(normalized()) { preferences.set(data, forKey: Self.storageKey) }
    }
    static func load(from preferences: UserDefaults = .standard) -> Self {
        if let data = preferences.data(forKey: storageKey), let saved = try? JSONDecoder().decode(Self.self, from: data) { return saved.normalized() }
        var result = Self()
        if preferences.object(forKey: "fontSize") != nil {
            result.sourceFontSize = preferences.double(forKey: "fontSize")
            result.translationFontSize = (result.sourceFontSize * 0.82).rounded()
        }
        if preferences.object(forKey: "overlayWidth") != nil { result.width = preferences.double(forKey: "overlayWidth") }
        if preferences.object(forKey: "opacity") != nil { result.opacity = preferences.double(forKey: "opacity") }
        return result.normalized()
    }
}

enum CaptionTypesetting {
    static func lineHeight(_ size: Double, weight: NSFont.Weight = .regular, spacing: Double = 5) -> Double {
        let font = NSFont.systemFont(ofSize: size, weight: weight)
        return ceil(font.ascender - font.descender + font.leading) + spacing
    }
    static func lineCount(_ text: String, size: Double, width: Double, weight: NSFont.Weight = .regular, spacing: Double = 5) -> Int {
        guard !text.isEmpty else { return 0 }
        let paragraph = NSMutableParagraphStyle(); paragraph.lineSpacing = spacing
        let rect = (text as NSString).boundingRect(with: NSSize(width: max(1, width), height: 20000), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: NSFont.systemFont(ofSize: size, weight: weight), .paragraphStyle: paragraph])
        return max(1, Int(ceil((rect.height + spacing) / lineHeight(size, weight: weight, spacing: spacing))))
    }
    static func naturalHeight(caption: VisibleCaption, style: CaptionAppearance, width: Double) -> Double {
        let source = lineCount(caption.source, size: style.sourceFontSize, width: width - 52, weight: .medium)
        let target = lineCount(caption.translation, size: style.translationFontSize, width: width - 52)
        if source == 0 && target == 0 { return 62 + lineHeight(style.translationFontSize) }
        return 62 + (source > 0 && target > 0 ? 9 : 0) + Double(source) * lineHeight(style.sourceFontSize, weight: .medium) + Double(target) * lineHeight(style.translationFontSize)
    }
}
