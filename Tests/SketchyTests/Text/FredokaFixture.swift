import CoreText
import UIKit

/// Fredoka SemiBold, the wordmark face from the Good Enough sticker.
///
/// The file is the OFL build used by SlapDuck (`Fonts/Fredoka-SemiBold.ttf`).
/// `Fredoka-OFL.txt` is the license that ships with that font.
enum FredokaFixture {
    static func font(size: CGFloat) -> UIFont? {
        guard let url = Bundle.module.url(
            forResource: "Fredoka-SemiBold",
            withExtension: "ttf",
            subdirectory: "Fixtures"
        ) else { return nil }
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        return UIFont(name: "Fredoka-SemiBold", size: size)
    }
}
