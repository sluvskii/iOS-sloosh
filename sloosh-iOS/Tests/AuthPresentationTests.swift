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
        for reduceMotion in [false, true] {
            for active in [false, true] {
                for lowPower in [false, true] {
                    check(AuthBackgroundMotion.isPaused(reduceMotion: reduceMotion, isActive: active, lowPower: lowPower)
                          == (reduceMotion || !active || lowPower), "Background honors every pause condition")
                }
            }
        }
        let epoch = Date(timeIntervalSince1970: 1_000)
        var clock = AuthBackgroundClock()
        check(clock.time(at: epoch) == 0, "Paused clock starts with the static design")
        clock.setRunning(true, at: epoch)
        clock.setRunning(true, at: epoch.addingTimeInterval(2))
        check(clock.time(at: epoch.addingTimeInterval(5)) == 5, "Repeated appearance must not restart live time")
        clock.setRunning(false, at: epoch.addingTimeInterval(5))
        clock.setRunning(false, at: epoch.addingTimeInterval(70))
        check(clock.time(at: epoch.addingTimeInterval(100)) == 5, "Pause freezes the current phase, not phase zero")
        clock.setRunning(true, at: epoch.addingTimeInterval(100))
        check(clock.time(at: epoch.addingTimeInterval(102)) == 7, "Resume cannot catch up background time")
        check(clock.time(at: epoch.addingTimeInterval(99)) == 5, "Stale timeline dates never move below the frozen phase")
        for stage in AuthEntranceStage.allCases {
            check(stage.opacity(appeared: true, reducedEffects: false) == 1 && stage.offset(appeared: true, reducedEffects: false) == 0,
                  "Entrance settles without changing layout or final colors")
            check(stage.opacity(appeared: false, reducedEffects: true) == 1 && stage.offset(appeared: false, reducedEffects: true) == 0,
                  "VoiceOver / Reduce Motion expose controls immediately without entrance movement")
        }
        check(AuthEntranceStage.action.initialOpacity >= 0.7, "Primary action is visible from its first frame")
        check(AuthEntranceStage.caption.delay < 0.25, "No slow splash sequence before login")
        for pressed in [false, true] {
            for reduceMotion in [false, true] {
                let appearance = AuthPressAppearance(isPressed: pressed, reduceMotion: reduceMotion)
                check(appearance.scale >= 0.98 && appearance.opacity >= 0.95, "Press feedback is subtle, not a large bounce")
                if reduceMotion || !pressed {
                    check(appearance.scale == 1 && appearance.offset == 0, "No press displacement with Reduce Motion or when released")
                }
            }
        }
        for time in stride(from: 0.0, through: 180, by: 0.5) {
            let lights = AuthBackgroundMotion.lights(at: time)
            check(lights.count == 5 && lights.filter(\.isRibbon).count == 2, "Fixed-cost native light field, no accumulating particles")
            check(lights.allSatisfy { $0.opacity > 0 && $0.opacity < 0.3 && $0.radiusX > 0 && $0.radiusY > 0 },
                  "Breathing keeps positive, restrained light intensity and radii")
            let next = AuthBackgroundMotion.lights(at: time + 1.0 / 24)
            for (light, following) in zip(lights, next) {
                check(abs(light.x - following.x) < 0.005 && abs(light.y - following.y) < 0.005
                      && abs(light.opacity - following.opacity) < 0.001 && abs(light.angle - following.angle) < 0.2,
                      "Every light path is continuous, with no wraps or flashes")
            }
        }
        check(abs(AuthBackgroundMotion.lights(at: 2)[3].x - AuthBackgroundMotion.lights(at: 0)[3].x) > 0.1,
              "Narrow light wash visibly drifts within two seconds, not only over a long cycle")
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

        let copy = AuthPhraseCopy.phrases
        check(copy.count == 12 && Set(copy).count == copy.count, "Keep a small edited bank of 12 distinct entries, not filler")
        check(copy.contains("Осталось десять минут.\nНичего не ясно"), "Preserve the explicitly liked phrase")
        for rejected in ["Когда второй сезон?\nПервый ещё идёт", "Комедия на вечер.\nЖизнь не предлагать"] {
            check(!copy.contains(rejected), "Never restore the explicitly rejected copy")
        }
        check(copy.filter { $0.contains("sloosh-ай") }.count == 2, "Keep both approved inline-wordmark phrases")
        let copyCharacters = Array(copy.joined().uppercased().utf16).filter { $0 != 10 }
        var copyGlyphs = [CGGlyph](repeating: 0, count: copyCharacters.count)
        check(CTFontGetGlyphsForCharacters(font, copyCharacters, &copyGlyphs, copyCharacters.count) && !copyGlyphs.contains(0),
              "Every new phrase is covered by the actual hero font, without emoji/fallback glyphs")
        for text in copy {
            let rows = text.components(separatedBy: "\n")
            check(rows.count == 2 && rows.allSatisfy { !$0.isEmpty && $0 == $0.trimmingCharacters(in: .whitespaces) },
                  "Each joke has two clean authored rows: setup then reaction")
            let reveal = AuthWordRevealPlan(text)
            check(reveal.duration <= 2.5 && reveal.wordCount > 0, "Copy stays short enough for the existing reveal/hold rhythm")
            for width in [CGFloat(208), 340] {
                for scale in [CGFloat(1), 1.6] {
                    let layout = AuthPhraseLayout.fit(text, in: CGSize(width: width, height: 160), scale: scale)
                    check(!layout.lines.isEmpty && layout.inkSize.width <= width - 28 + 0.05 && layout.inkSize.height <= 132.05,
                          "All production phrases fit narrow phones and larger text without clipping")
                    let indices = Set(layout.lines.flatMap { line in
                        (CTLineGetGlyphRuns(line.shaped) as! [CTRun]).compactMap { run in
                            (CTRunGetAttributes(run) as NSDictionary)[AuthPhraseLayout.wordIndexKey.rawValue] as? Int
                        }
                    })
                    check(indices == Set(0..<reveal.wordCount), "Reflow preserves every new phrase's original word beats")
                    let widths = layout.lines.map(\.ink.width)
                    check(widths.max()! - widths.min()! < 0.1, "Every production phrase retains equal visible row widths")
                }
            }
        }

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
        for text in copy {
            let image = pixels(authPhrase(phrase: text, elapsed: AuthWordRevealPlan(text).duration, accent: .green), width: 208, height: 200)
            check(litCount(image) > 50, "Every production phrase renders visible ink on a narrow screen")
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
        if leftMatches <= 50 || rightMatches <= 20 {
            FileHandle.standardError.write(Data("::error::Brand pixel diagnostic: swatch=\(swatch), left=\(leftMatches), right=\(rightMatches), leftHistogram=\(inkHistogram(in: 0..<106)), rightHistogram=\(inkHistogram(in: 215..<320))\n".utf8))
        }
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
        for time in [0.0, 2, 5, 9, 15, 24, 45] {
            let frame = pixels(AuthCinematicBackdrop(time: time, accent: .green), width: 200, height: 400)
            let maxChannel = stride(from: 0, to: frame.count, by: 4).map { max(frame[$0], frame[$0 + 1], frame[$0 + 2]) }.max() ?? 255
            check(maxChannel < 150, "Background remains restrained for white hero text at multiple phases")
            let next = pixels(AuthCinematicBackdrop(time: time + 1.0 / 24, accent: .green), width: 200, height: 400)
            check(zip(frame, next).map { abs(Int($0) - Int($1)) }.max()! <= 4,
                  "Actual consecutive frames have no bright jumps or hard moving edges")
        }
        let background2 = pixels(AuthCinematicBackdrop(time: 2, accent: .green), width: 200, height: 400)
        let rgbOffsets = (0..<(200 * 400 * 4)).filter { $0 % 4 != 3 }
        let movement = rgbOffsets.reduce(0.0) { $0 + Double(abs(Int(background0[$1]) - Int(background2[$1]))) } / Double(rgbOffsets.count)
        check(movement > 0.5, "Real rendered light movement is perceptible within two seconds")
        let wideBackground = pixels(AuthCinematicBackdrop(time: 5, accent: .green), width: 600, height: 320)
        check(litCount(wideBackground) > 500, "Light washes adapt to wide layouts too")
        let styledButton = pixels(Button("Продолжить через Google") {}.foregroundStyle(.white).buttonStyle(AuthPressButtonStyle()), width: 320, height: 52)
        check(litCount(styledButton) > 50, "Production button style renders its label")
        print("✓ Auth presentation: \(count) checks passed")
    }
}
