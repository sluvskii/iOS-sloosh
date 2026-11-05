import Foundation
import SwiftUI
import CoreText

@main
struct AuthPresentationTests {
    @MainActor
    static func main() {
        var count = 0
        func check(_ condition: Bool, _ message: String) {
            precondition(condition, message)
            count += 1
        }
        guard let assetsPath = ProcessInfo.processInfo.environment["SLOOSH_AUTH_TEST_ASSETS"],
              let brandBundle = Bundle(path: assetsPath),
              brandBundle.url(forResource: "Assets", withExtension: "car") != nil else {
            fatalError("Compile the actual LogoText asset bundle before running auth presentation tests")
        }
        func authPhrase(phrase: String, elapsed: Double, accent: Color, scale: CGFloat = 1) -> AuthAnimatedPhrase {
            AuthAnimatedPhrase(phrase: phrase, elapsed: elapsed, accent: accent, scale: scale, logoBundle: brandBundle)
        }
        let svg = try! String(contentsOfFile: "sloosh/Resources/Assets.xcassets/LogoText.imageset/sloosh.svg", encoding: .utf8)
        check(svg.contains("viewBox=\"0 0 625 173\""), "Inline logo ratio must match the canonical SVG")
        check(AuthInlineBrand.suffix(of: "SLOOSH-АЙ") == "-АЙ" && AuthInlineBrand.suffix(of: "SLOOSH") == "", "Logo replaces only the brand; suffix remains text")
        check(AuthInlineBrand.suffix(of: "SLOOSHING") == nil, "Do not replace unrelated words")
        let fontURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("sloosh/Resources/Fonts/\(CatalogFallbackTitleStyle.fontFileName)")
        var fontError: Unmanaged<CFError>?
        check(CTFontManagerRegisterFontsForURL(fontURL as CFURL, .process, &fontError), "Bundled catalog font registers for auth phrases")
        let font = CTFontCreateWithName(CatalogFallbackTitleStyle.postScriptName as CFString, AuthPhraseTypography.baseSize, nil)
        check(CTFontCopyPostScriptName(font) as String == CatalogFallbackTitleStyle.postScriptName, "Auth font must not silently fall back to SF")
        let letters = Array("АаБбВвДдЕеЁёЖжЙйЦцЩщЯяsloosh-ай".utf16)
        var glyphs = [CGGlyph](repeating: 0, count: letters.count)
        check(CTFontGetGlyphsForCharacters(font, letters, &glyphs, letters.count) && !glyphs.contains(0), "Mixed-case Cyrillic and the brand are covered")
        check(AuthBackgroundSmoothing.noiseBytes.count == 64 * 64, "Tiny cached grain texture")
        let meanNoise = AuthBackgroundSmoothing.noiseBytes.reduce(0.0) { $0 + Double($1) } / Double(AuthBackgroundSmoothing.noiseBytes.count)
        check(abs(meanNoise - 127.5) < 4, "Noise remains neutral instead of tinting or lifting the background")
        check(AuthBackgroundSmoothing.ditherOpacity <= 0.06, "Dither is restrained, not a visible grain effect")
        let glow = AuthBackgroundSmoothing.glowStops.map(\.opacity)
        check(glow.first == 1 && glow.last == 0, "Glow starts at the same intensity and feathers to zero")
        check(zip(glow, glow.dropFirst()).allSatisfy { $0 >= $1 }, "Glow has no abrupt brightness reversals")
        let beam = AuthBackgroundSmoothing.beamStops.map(\.opacity)
        check(beam.first == 0 && (beam.last ?? 1) < 0.0001 && beam[16] == 1, "Beam edges are feathered, preserving peak intensity")
        let phrase = "  Один клик —\nи ты уже в кино  "
        let plan = AuthWordRevealPlan(phrase)
        check(plan.parts.map(\.text).joined() == phrase, "Preserve spaces, punctuation and manual line breaks")
        check(plan.wordCount == 7, "Standalone dash shares the preceding beat")
        check(plan.parts.first(where: { $0.text == "—" })?.wordIndex == 1, "Punctuation belongs with preceding word")
        check(AuthWordRevealPlan("").duration == 0, "Empty phrase is safe")
        check(AuthWordRevealPlan(" \n ").wordCount == 0, "Whitespace is not animated as a word")
        check(AuthWordRevealPlan("sloosh-ай сердцем").wordCount == 2, "Hyphenated brand is one word")
        for i in 0..<plan.wordCount {
            let start = Double(i) * AuthWordRevealPlan.stagger
            check(AuthWordRevealPlan.visibility(of: i, at: start) == 0, "Each word starts on its own beat")
            check(AuthWordRevealPlan.visibility(of: i, at: start + AuthWordRevealPlan.wordDuration + 0.001) == 1, "Every word reaches full focus")
            check(AuthWordRevealPlan.visibility(of: i, at: plan.duration + 0.001) == 1, "Hold begins only after last word is readable")
            let samples = (0...100).map { AuthWordRevealPlan.visibility(of: i, at: Double($0) * plan.duration / 100) }
            check(zip(samples, samples.dropFirst()).allSatisfy { $0 <= $1 }, "No flashing backwards during reveal")
        }
        check(AuthWordRevealPlan.visibility(of: 1, at: 0.17) == 0, "Second word stays hidden while first word appears")
        check(AuthWordRevealPlan.visibility(of: 0, at: 0.17) > 0, "First word is already appearing")

        let fitted = AuthPhraseLayout.fit("Твой личный кинозал\nВ кармане", in: CGSize(width: 340, height: 190))
        check(fitted.lines.count == 2, "Keep authored two-line layout when it fits")
        check(fitted.lines.last!.pointSize > fitted.lines.first!.pointSize * 1.5,
              "Short row gets a larger font, not simply the same point size")
        check(fitted.lines.last!.text == "В КАРМАНЕ", "Visual text is uppercase Cyrillic")
        check(fitted.lines.map(\.pointSize).min()! > 28, "Hero lettering grows beyond the old fixed font")
        check(fitted.lineGap < 6, "Compact gap measured between real glyph outlines")
        check(AuthPhraseLayout.fit(" \n ", in: CGSize(width: 300, height: 180)).lines.isEmpty, "Blank phrase is safe")
        check(AuthPhraseLayout.fit("Текст", in: .zero).lines.isEmpty, "Initial zero geometry is safe")
        check(AuthPhraseLayout.heroHeight(availableHeight: 600, scale: 1) > 110, "Responsive hero reserves more space than old fixed minimum")
        for width in [CGFloat(208), 280, 340] {
            for height in [CGFloat(140), 190] {
                for scale in [CGFloat(1), 1.6] {
                    for text in ["Не только смотри,\nно и sloosh-ай", "Залипнуть на все выходные?\nЛегко", "Ёлки и Йода\nДЦЩ", "Один клик —\nи ты уже в кино"] {
                        let layout = AuthPhraseLayout.fit(text, in: CGSize(width: width, height: height), scale: scale)
                        check(!layout.lines.isEmpty && layout.inkSize.height <= height - 28 + 0.05, "Accent/descender ink stays inside the available height")
                        let widths = layout.lines.map(\.ink.width)
                        check((widths.max()! - widths.min()!) < 0.1, "Every row has the same actual ink width")
                        check(widths.max()! <= width - 28 + 0.05, "Equal row widths do not overflow the screen")
                        check(layout.lines.map(\.text).joined(separator: " ") == CatalogFallbackTitleStyle.displayTitle(text).split(whereSeparator: { $0.isWhitespace }).joined(separator: " "),
                              "Wrapping preserves every word and punctuation")
                        var indices = Set<Int>()
                        for line in layout.lines {
                            for run in CTLineGetGlyphRuns(line.shaped) as! [CTRun] {
                                let attributes = CTRunGetAttributes(run) as NSDictionary
                                if let index = attributes[AuthPhraseLayout.wordIndexKey.rawValue] as? Int { indices.insert(index) }
                            }
                        }
                        check(indices == Set(0..<AuthWordRevealPlan(text).wordCount), "Word reveal sequence stays global across resized/wrapped rows")
                    }
                }
            }
        }

        for text in ["Не только смотри,\nно и sloosh-ай", "Смотри глазами.\nsloosh-ай сердцем", "SLOOSH"] {
            let layout = AuthPhraseLayout.fit(text, in: CGSize(width: 340, height: 190))
            var logos = 0
            for line in layout.lines {
                for run in CTLineGetGlyphRuns(line.shaped) as! [CTRun] {
                    if let rect = AuthInlineBrand.logoRect(in: run) {
                        logos += 1
                        check(abs(rect.width / rect.height - AuthInlineBrand.aspectRatio) < 0.0001, "Logo preserves canonical proportions")
                        check(rect.minX >= line.ink.minX - 0.01 && rect.maxX <= line.ink.maxX + 0.01 && rect.maxY <= line.ink.maxY + 0.01,
                              "Logo participates in actual ink bounds, not a floating overlay")
                    }
                }
            }
            check(logos == 1, "Replace exactly one SLOOSH token with an inline logo attachment")
            if layout.lines.count > 1 {
                let widths = layout.lines.map(\.ink.width)
                check(widths.max()! - widths.min()! < 0.1, "Rows remain equal width with the real logo")
            }
        }

        func pixels<V: View>(_ view: V, width: CGFloat, height: CGFloat) -> [UInt8] {
            let renderer = ImageRenderer(content: view.frame(width: width, height: height).background(.black))
            renderer.scale = 1
            guard let image = renderer.cgImage else { fatalError("Auth view must render") }
            var data = [UInt8](repeating: 0, count: image.width * image.height * 4)
            data.withUnsafeMutableBytes { bytes in
                let cg = CGContext(data: bytes.baseAddress, width: image.width, height: image.height,
                                   bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                   space: CGColorSpaceCreateDeviceRGB(),
                                   bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue)!
                cg.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            }
            return data
        }
        func litCount(_ pixels: [UInt8]) -> Int {
            stride(from: 0, to: pixels.count, by: 4).filter { pixels[$0] > 30 || pixels[$0 + 1] > 30 || pixels[$0 + 2] > 30 }.count
        }
        let title = "Кино дома"
        func renderedTitle(_ elapsed: Double, width: CGFloat = 320) -> [UInt8] {
            pixels(authPhrase(phrase: title, elapsed: elapsed, accent: .green), width: width, height: 150)
        }
        let hidden = renderedTitle(0)
        let partial = renderedTitle(0.3)
        let full = renderedTitle(10)
        check(litCount(hidden) == 0, "Actual ink renderer must hide all words initially")
        check(litCount(partial) > 0, "Actual intermediate frame contains visible lettering")
        check(litCount(full) > litCount(partial), "Actual reveal must be word-staggered, not instantly complete")
        check(litCount(renderedTitle(10, width: 160)) > 50, "Fitted text remains visible on narrow layouts")
        for text in ["Не только смотри,\nно и sloosh-ай", "Залипнуть на все выходные?\nЛегко"] {
            let complete = AuthWordRevealPlan(text).duration
            for width in [CGFloat(208), 320] {
                let image = pixels(authPhrase(phrase: text, elapsed: complete, accent: .green, scale: 1.4), width: width, height: 200)
                check(litCount(image) > 100, "Cyrillic/newlines/brand render with larger text and wrapping")
            }
        }
        // Compare actual pixels too, not only CTLine's measured widths. These
        // words have no detached accents, so two ink bands correspond to two rows.
        let equalRows = pixels(authPhrase(phrase: "Медиум дома\nКино дома", elapsed: 10, accent: .green), width: 340, height: 190)
        var rowBands: [[Int]] = []
        for y in 0..<190 {
            let xs = (0..<340).filter { x in
                let offset = (y * 340 + x) * 4
                return max(equalRows[offset], equalRows[offset + 1], equalRows[offset + 2]) > 30
            }
            if !xs.isEmpty {
                if rowBands.last?.last == y - 1 { rowBands[rowBands.count - 1].append(y) }
                else { rowBands.append([y]) }
            }
        }
        check(rowBands.count == 2, "Actual drawing produces exactly two separate compact ink rows")
        let renderedWidths = rowBands.map { ys -> Int in
            let xs = ys.flatMap { y in (0..<340).filter { x in
                let offset = (y * 340 + x) * 4
                return max(equalRows[offset], equalRows[offset + 1], equalRows[offset + 2]) > 30
            } }
            return xs.max()! - xs.min()! + 1
        }
        check(abs(renderedWidths[0] - renderedWidths[1]) <= 3, "Actual rows, not just layout boxes, have equal width")
        check(renderedWidths.min()! > 300, "Text grows to the available width")
        check(rowBands[1].first! - rowBands[0].last! <= 8, "Actual interline ink gap is tight")

        // Neutral text still uses plusLighter over the real backdrop. Brand-only
        // content must keep normal blending and the exact theme accent instead.
        let blendSurface = Color(red: 0.12, green: 0.18, blue: 0.27)
        let brandAccent = Color(red: 0.70, green: 1, blue: 0)
        let blendPhrase = authPhrase(phrase: "Кино\nдома", elapsed: 10, accent: brandAccent)
        let neutralReference = AuthPhraseInkCanvas(phrase: "Кино\nдома", elapsed: 10, accent: brandAccent,
                                                   scale: 1, role: .neutral, logoBundle: brandBundle)
        let normalInk = pixels(ZStack { blendSurface; neutralReference }, width: 320, height: 180)
        let additiveInk = pixels(ZStack { blendSurface; neutralReference.blendMode(.plusLighter) }, width: 320, height: 180)
        let productionInk = pixels(ZStack { blendSurface; blendPhrase }, width: 320, height: 180)
        check(productionInk == additiveInk, "Only neutral hero ink keeps the existing plusLighter treatment")
        check(productionInk != normalInk, "Neutral blending must affect foreground pixels")
        check(Array(productionInk.prefix(4)) == Array(normalInk.prefix(4)), "Background outside ink is unchanged")
        let brandOnly = authPhrase(phrase: "sloosh-ай", elapsed: 10, accent: brandAccent)
        let brandPixels = pixels(ZStack { blendSurface; brandOnly }, width: 320, height: 180)
        let brandReference = AuthPhraseInkCanvas(phrase: "sloosh-ай", elapsed: 10, accent: brandAccent,
                                                 scale: 1, role: .brand, logoBundle: brandBundle)
        check(brandPixels == pixels(ZStack { blendSurface; brandReference }, width: 320, height: 180),
              "Logo and suffix use normal blending, never additive tint")
        check(brandPixels != pixels(ZStack { blendSurface; brandReference.blendMode(.plusLighter) }, width: 320, height: 180),
              "Regression guard against turning green branding yellow over the backdrop")
        let swatch = pixels(brandAccent, width: 1, height: 1)
        func matchesSwatch(_ offset: Int) -> Bool {
            (0..<3).allSatisfy { abs(Int(brandPixels[offset + $0]) - Int(swatch[$0])) <= 2 }
        }
        let leftMatches = stride(from: 0, to: brandPixels.count, by: 4).filter { ($0 / 4) % 320 < 106 && matchesSwatch($0) }.count
        let rightMatches = stride(from: 0, to: brandPixels.count, by: 4).filter { ($0 / 4) % 320 > 214 && matchesSwatch($0) }.count
        func inkHistogram(in range: Range<Int>) -> String {
            var values: [String: Int] = [:]
            for offset in stride(from: 0, to: brandPixels.count, by: 4) where range.contains((offset / 4) % 320) {
                let key = "\(brandPixels[offset]),\(brandPixels[offset + 1]),\(brandPixels[offset + 2]),\(brandPixels[offset + 3])"
                values[key, default: 0] += 1
            }
            return values.sorted { $0.value > $1.value }.prefix(8).map { "\($0.key):\($0.value)" }.joined(separator: " ")
        }
        FileHandle.standardError.write(Data("::error::Brand pixel diagnostic: swatch=\(swatch), left=\(leftMatches), right=\(rightMatches), leftHistogram=\(inkHistogram(in: 0..<106)), rightHistogram=\(inkHistogram(in: 215..<320))\n".utf8))
        check(leftMatches > 50, "Actual logo pixels match a native SwiftUI accent swatch")
        check(rightMatches > 20, "CoreText suffix matches the same swatch; no sRGB/linear double encoding")
        check(litCount(pixels(authPhrase(phrase: "SLOOSH", elapsed: 10, accent: brandAccent), width: 320, height: 150)) > 100,
              "The real logo asset draws even when there are no text glyphs")
        check(litCount(pixels(authPhrase(phrase: "SLOOSH-АЙ", elapsed: 0, accent: brandAccent), width: 320, height: 150)) == 0,
              "Logo and suffix stay hidden together before their word beat")

        // Accessibility environment values are read-only system traits. Test
        // the shared fallback policy directly instead of mutating OS settings.
        for contrast in [false, true] {
            for reduceTransparency in [false, true] {
                let appearance = BackdropForegroundAppearance(isDark: true, increasedContrast: contrast,
                                                             reduceTransparency: reduceTransparency, opacity: 1)
                check(appearance.blendMode == (contrast || reduceTransparency ? .normal : .plusLighter),
                      "Shared policy preserves the normal-blend accessibility fallback")
            }
        }
        let background0 = pixels(AuthCinematicBackdrop(time: 0, accent: .green), width: 200, height: 400)
        let background8 = pixels(AuthCinematicBackdrop(time: 8, accent: .green), width: 200, height: 400)
        check(litCount(background0) > 500, "Background has actual light/depth rather than solid black")
        check(background0 != background8, "Background light changes over time")
        let withoutDither = pixels(AuthCinematicBackdrop(time: 0, accent: .green, includesDither: false), width: 200, height: 400)
        let differences = zip(background0, withoutDither).map { abs(Int($0) - Int($1)) }
        check(differences.filter { $0 > 0 }.count > 100, "Dither must actually affect rendered gradient pixels")
        check((differences.max() ?? 255) <= 8, "Dither stays a few code values, never a visible wash")
        check(background0 == pixels(AuthCinematicBackdrop(time: 0, accent: .green), width: 200, height: 400),
              "Dither is stable at the same phase, not random flicker")
        let maxChannel = stride(from: 0, to: background0.count, by: 4).map { max(background0[$0], background0[$0 + 1], background0[$0 + 2]) }.max() ?? 255
        check(maxChannel < 150, "Background remains restrained enough for white hero text")
        print("✓ Auth presentation: \(count) checks passed")
    }
}
