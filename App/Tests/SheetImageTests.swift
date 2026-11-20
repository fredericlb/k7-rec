// A sheet photo is decoded at a bounded size.
import UIKit
import XCTest
@testable import K7Rec

final class SheetImageTests: XCTestCase {
    func testALargePhotoComesBackNoLargerThanTheLimit() throws {
        let url = try tempFolder().appendingPathComponent("score.png")
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 3000, height: 2000), format: { let f = UIGraphicsImageRendererFormat(); f.scale = 1; return f }())
        try renderer.pngData { ctx in UIColor.gray.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 3000, height: 2000)) }.write(to: url)

        let image = try XCTUnwrap(SheetImage.load(url, maxPixel: 600))

        XCTAssertLessThanOrEqual(max(image.size.width, image.size.height) * image.scale, 600)
        XCTAssertGreaterThan(max(image.size.width, image.size.height) * image.scale, 500, "shrunk, not thumbnailed to nothing")
    }

    func testAFileThatIsNotAnImageIsNil() throws {
        let url = try tempFolder().appendingPathComponent("x.png")
        try Data("no".utf8).write(to: url)
        XCTAssertNil(SheetImage.load(url))
    }
}
