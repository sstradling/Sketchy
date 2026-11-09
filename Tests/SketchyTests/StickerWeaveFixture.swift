import UIKit

/// Loads `Fixtures/sticker-weave.png`.
///
/// The file is a synthetic 16×16 checker drawn for Sketchy tests and the
/// docs gallery. Rose `(214, 64, 92)` and teal `(40, 120, 150)` alternate in
/// 4-pixel blocks. It is not a photograph and it is not a third-party asset.
enum StickerWeaveFixture {
    static func data() -> Data? {
        guard let url = Bundle.module.url(
            forResource: "sticker-weave",
            withExtension: "png",
            subdirectory: "Fixtures"
        ) else {
            return nil
        }
        return try? Data(contentsOf: url)
    }

    static func image() -> UIImage? {
        data().flatMap { UIImage(data: $0) }
    }
}
