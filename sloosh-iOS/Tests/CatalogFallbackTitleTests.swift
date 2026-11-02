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
        let plist = try! PropertyListSerialization.propertyList(from: Data(contentsOf: root.appendingPathComponent("sloosh/Info.plist")), format: nil) as! [String: Any]
        check((plist["UIAppFonts"] as? [String])?.contains(CatalogFallbackTitleStyle.fontFileName) == true, "App declares the font")
        let project = try! String(contentsOf: root.appendingPathComponent("project.yml"), encoding: .utf8)
        check(project.contains("- \(CatalogFallbackTitleStyle.fontFileName)"), "XcodeGen must preserve the UIAppFonts declaration")

        // Render the actual SwiftUI title, not a copied layout algorithm. Wide,
        // narrow, mixed-language and long titles must be visible in the caption.
        for width in [CGFloat(69), 95, 160] {
            for scale in [CGFloat(1), 1.4, 2] {
                for title in ["Дюна", "Одни из нас", "Ёлки: Новогодняя история", "Человек-паук: Нет пути домой", "Spider-Man: No Way Home"] {
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
