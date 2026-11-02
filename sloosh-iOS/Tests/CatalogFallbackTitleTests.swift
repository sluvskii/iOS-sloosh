import Foundation
import SwiftUI
import CoreText

struct CatalogFallbackTitleTests {
    @MainActor
    static func run() -> Int {
        var count = 0
        func check(_ condition: Bool, _ message: String) {
            precondition(condition, message)
            count += 1
        }
        for logos in [false, true] {
            for metadata in [false, true] {
                check(CatalogFallbackTitleStyle.isEnabled(useLogos: logos, showsMetadata: metadata) == (logos && !metadata),
                      "Keep the typography experiment out of ordinary card modes")
            }
        }
        check(CatalogFallbackTitleStyle.displayTitle("Одни из нас: Ёж и Йода") == "ОДНИ ИЗ НАС: ЁЖ И ЙОДА", "Cyrillic uppercase including Ё/Й")
        check(CatalogFallbackTitleStyle.displayTitle("Spider-Man: No Way Home") == "SPIDER-MAN: NO WAY HOME", "Latin uppercase/punctuation")
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let file = root.appendingPathComponent("sloosh/Resources/Fonts/\(CatalogFallbackTitleStyle.fontFileName)")
        var error: Unmanaged<CFError>?
        check(CTFontManagerRegisterFontsForURL(file as CFURL, .process, &error), "Bundled font must register, not silently fall back to SF")
        let font = CTFontCreateWithName(CatalogFallbackTitleStyle.postScriptName as CFString, 20, nil)
        check(CTFontCopyPostScriptName(font) as String == CatalogFallbackTitleStyle.postScriptName, "Exact static font name is available")
        let alphabet = Array("АБВГДЕЁЖЗИЙКЛМНОПРСТУФХЦЧШЩЪЫЬЭЮЯABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789".utf16)
        var glyphs = [CGGlyph](repeating: 0, count: alphabet.count)
        check(CTFontGetGlyphsForCharacters(font, alphabet, &glyphs, alphabet.count), "Font must cover Cyrillic, Latin and digits")
        check(!glyphs.contains(0), "No missing-letter tofu glyphs")
        check(CatalogFallbackTitleStyle.trackingEm < 0, "Tracking should be slightly tightened")
        let short = CatalogWordmarkLayout.fit(title: "Дюна", in: CGSize(width: 110, height: 36))
        check(short.pointSize > 20, "Short titles must grow beyond the old fixed 20pt ceiling")
        check(short.lines.count == 1, "Do not break a single word into letters")
        let medium = CatalogWordmarkLayout.fit(title: "Медиум", in: CGSize(width: 110, height: 36))
        let narrow = CatalogWordmarkLayout.fit(title: "Медиум", in: CGSize(width: 69, height: 36))
        check(medium.pointSize > narrow.pointSize, "Point size must use available width")
        let doubled = CatalogWordmarkLayout.fit(title: "Медиум", in: CGSize(width: 220, height: 72), scale: 2)
        check(abs(doubled.pointSize / medium.pointSize - 2) < 0.05, "Proportions scale uniformly, without stretching glyphs")
        let two = CatalogWordmarkLayout.fit(title: "Магическая битва: Казнь", in: CGSize(width: 110, height: 36))
        check(two.lines.count == 2, "Long multiword titles should use a natural two-line layout")
        check(two.lineGap > 0 && two.lineGap < two.pointSize * 0.1, "Use a compact real-ink gap instead of font leading")
        check(two.lines.map(\.text).joined(separator: " ") == "МАГИЧЕСКАЯ БИТВА: КАЗНЬ", "Keep all words and punctuation")
        let huge = CatalogWordmarkLayout.fit(title: String(repeating: "СВЕРХДЛИННОЕ", count: 12), in: CGSize(width: 69, height: 36))
        check(huge.isTruncated && huge.pointSize >= 10, "Pathological names need readable ellipsis, not tiny lettering")
        check(CatalogWordmarkLayout.fit(title: "  \n ", in: CGSize(width: 100, height: 36)).lines.isEmpty, "Empty titles are safe")
        check(CatalogWordmarkLayout.fit(title: "Дюна", in: .zero).lines.isEmpty, "Zero initial geometry is safe")
        let attrs: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTKernAttributeName as String): 0.1
        ]
        let original = CTLineCreateWithAttributedString(NSAttributedString(string: "БИБЛИОТЕКАРИ", attributes: attrs))
        let originalWidth = CTLineGetBoundsWithOptions(original, [.useGlyphPathBounds]).width
        let tighter = CatalogWordmarkLayout.fit(title: "БИБЛИОТЕКАРИ", in: CGSize(width: originalWidth, height: 100))
        check(tighter.pointSize > 20, "Reduced tracking actually fits larger lettering in the same width")

        let plist = try! PropertyListSerialization.propertyList(from: Data(contentsOf: root.appendingPathComponent("sloosh/Info.plist")), format: nil) as! [String: Any]
        check((plist["UIAppFonts"] as? [String])?.contains(CatalogFallbackTitleStyle.fontFileName) == true, "App declares the font")
        let project = try! String(contentsOf: root.appendingPathComponent("project.yml"), encoding: .utf8)
        check(project.contains("- \(CatalogFallbackTitleStyle.fontFileName)"), "XcodeGen must preserve the UIAppFonts declaration")

        // Render the actual SwiftUI title, not a copied layout algorithm. Wide,
        // narrow, mixed-language and long titles must be visible in the caption.
        for width in [CGFloat(69), 95, 160] {
            for scale in [CGFloat(1), 1.4, 2] {
                for title in ["Дюна", "Одни из нас", "Ёлки: Новогодняя история", "Человек-паук: Нет пути домой", "Spider-Man: No Way Home"] {
                    let area = CGSize(width: width, height: CatalogCaptionLayout(isOverlay: false, showsMetadata: false, scale: scale).totalHeight)
                    let plan = CatalogWordmarkLayout.fit(title: title, in: area, scale: scale)
                    check(plan.lines.count <= 2, "No third line")
                    check(plan.inkSize.width <= area.width + 0.01 && plan.inkSize.height <= area.height + 0.01,
                          "Real ink, including Cyrillic accents/descenders, fits the reserved caption")
                    if !plan.isTruncated {
                        check(max(plan.inkSize.width / area.width, plan.inkSize.height / area.height) > 0.98,
                              "Use all available width or height instead of a fixed small font")
                    }
                    let height = CatalogCaptionLayout(isOverlay: false, showsMetadata: false, scale: scale).totalHeight
                    let view = CatalogFallbackLogoTitle(title: title, isOverlay: false, scale: scale)
                        .frame(width: width, height: height)
                        .padding(8)
                        .background(Color.black)
                        .environment(\.colorScheme, .dark)
                    let renderer = ImageRenderer(content: view)
                    renderer.scale = 1
                    guard let image = renderer.cgImage else { fatalError("Title render failed") }
                    var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
                    pixels.withUnsafeMutableBytes { bytes in
                        let context = CGContext(data: bytes.baseAddress, width: image.width, height: image.height,
                                                bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                                space: CGColorSpaceCreateDeviceRGB(),
                                                bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue)!
                        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
                    }
                    let lit = stride(from: 0, to: pixels.count, by: 4).filter { pixels[$0] > 30 || pixels[$0+1] > 30 || pixels[$0+2] > 30 }
                    check(lit.count > 15, "Title must render actual visible letters")
                    let xs = lit.map { ($0 / 4) % image.width }, ys = lit.map { ($0 / 4) / image.width }
                    if !plan.isTruncated, let x0 = xs.min(), let x1 = xs.max(), let y0 = ys.min(), let y1 = ys.max() {
                        check(max(CGFloat(x1 - x0 + 1) / width, CGFloat(y1 - y0 + 1) / height) > 0.9,
                              "Rendered lettering, not only the measured line box, should fill an available axis")
                    }
                    check(lit.allSatisfy { index in
                        let x = (index / 4) % image.width, y = (index / 4) / image.width
                        return x >= 6 && x < image.width - 6 && y >= 6 && y < image.height - 6
                    }, "Condensed title must stay within its reserved caption, including long Cyrillic")
                }
            }
        }
        return count
    }
}
