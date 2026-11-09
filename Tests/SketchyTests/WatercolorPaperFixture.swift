import UIKit

/// Loads `Fixtures/watercolor-paper.jpg`.
///
/// The file is a square crop of an Unsplash watercolor-paper photograph
/// (image id `1604147706283-d7119b5b822c`). It is the docs and demo example,
/// not a generated texture. See the README credits note.
enum WatercolorPaperFixture {
    static func image() -> UIImage? {
        guard let url = Bundle.module.url(
            forResource: "watercolor-paper",
            withExtension: "jpg",
            subdirectory: "Fixtures"
        ) else {
            return nil
        }
        return (try? Data(contentsOf: url)).flatMap { UIImage(data: $0) }
    }
}
