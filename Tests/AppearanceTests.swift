import AppKit

@main enum AppearanceTests {
    static func main() {
        let name = "jp.xuhan.KotobaLocal.tests." + UUID().uuidString
        let preferences = UserDefaults(suiteName: name)!
        defer { preferences.removePersistentDomain(forName: name) }
        preferences.set(40, forKey: "fontSize")
        preferences.set(0.0, forKey: "opacity")
        let migrated = CaptionAppearance.load(from: preferences)
        precondition(migrated.sourceFontSize == 40 && migrated.translationFontSize == 33)
        precondition(migrated.opacity == 0, "Transparent backgrounds must survive migration")
        var customized = CaptionAppearance()
        customized.sourceFontSize = 38; customized.translationFontSize = 24
        customized.background = CaptionRGB(red: 0.23, green: 0.36, blue: 0.68)
        customized.width = 720; customized.height = 310; customized.automaticHeight = false
        customized.opacity = 0
        customized.save(to: preferences)
        precondition(CaptionAppearance.load(from: preferences) == customized)
        let both = VisibleCaption(source: String(repeating: "授業では身近な道具を考えます。", count: 12), translation: String(repeating: "Let's explore familiar tools together. ", count: 12), translates: true, mode: .bilingual, ready: true)
        precondition(CaptionTypesetting.naturalHeight(caption: both, style: customized, width: 420) > CaptionTypesetting.naturalHeight(caption: both, style: customized, width: 1000))
        print("PASS: previous settings migration, transparent background persistence, independent font/color/size roundtrip, long bilingual wrapping")
    }
}
