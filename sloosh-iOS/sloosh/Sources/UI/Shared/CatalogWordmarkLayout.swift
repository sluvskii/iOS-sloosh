import Foundation
import CoreText

/// Fit actual ink, not Oswald's unusually tall ascender/descender line box.
/// Uniform point-size scaling preserves letter shapes; no horizontal stretching.
struct CatalogWordmarkLayout {
    struct Line {
        let text: String
        let shaped: CTLine
        let ink: CGRect
    }
    let lines: [Line]
    let pointSize: CGFloat
    let inkSize: CGSize
    let lineGap: CGFloat
    let isTruncated: Bool

    private final class Cached {
        let layout: CatalogWordmarkLayout
        init(_ layout: CatalogWordmarkLayout) { self.layout = layout }
    }
    private static let cache: NSCache<NSString, Cached> = {
        let cache = NSCache<NSString, Cached>()
        cache.countLimit = 384
        return cache
    }()

    static func fit(title: String, in area: CGSize, scale: CGFloat = 1) -> Self {
        guard area.width > 0, area.height > 0, area.width.isFinite, area.height.isFinite,
              scale > 0, scale.isFinite else {
            return Self(lines: [], pointSize: 0, inkSize: .zero, lineGap: 0, isTruncated: false)
        }
        let text = CatalogFallbackTitleStyle.displayTitle(String(title.prefix(512)))
            .split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
            + (title.count > 512 ? "…" : "")
        guard !text.isEmpty else {
            return Self(lines: [], pointSize: 0, inkSize: .zero, lineGap: 0, isTruncated: false)
        }
        let key = "\(text)|\(area.width)|\(area.height)|\(scale)" as NSString
        if let hit = cache.object(forKey: key) { return hit.layout }

        let words = text.split(separator: " ").map(String.init)
        var arrangements = [[text]]
        // Natural word boundaries only: don't split a short title into letters.
        if words.count > 1 {
            for split in 1..<words.count {
                arrangements.append([words[..<split].joined(separator: " "), words[split...].joined(separator: " ")])
            }
        }
        let reference: CGFloat = 100
        func measure(_ texts: [String], size: CGFloat, truncate: Bool = false) -> Self {
            let font = CTFontCreateWithName(CatalogFallbackTitleStyle.postScriptName as CFString, size, nil)
            let attributes: [NSAttributedString.Key: Any] = [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTKernAttributeName as String): CatalogFallbackTitleStyle.trackingEm * size,
                NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String): true
            ]
            var shortened = false
            let lines = texts.map { text -> Line in
                var line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
                if truncate, bounds(line).width > area.width {
                    let token = CTLineCreateWithAttributedString(NSAttributedString(string: "…", attributes: attributes))
                    if let replacement = CTLineCreateTruncatedLine(line, max(1, area.width - 1), .end, token) {
                        line = replacement
                    } else {
                        line = token
                    }
                    shortened = true
                }
                return Line(text: text, shaped: line, ink: bounds(line))
            }
            let gap = texts.count > 1 ? size * CatalogFallbackTitleStyle.lineGapEm : 0
            return Self(lines: lines, pointSize: size,
                        inkSize: CGSize(width: lines.map { $0.ink.width }.max() ?? 0,
                                        height: lines.reduce(0) { $0 + $1.ink.height } + gap),
                        lineGap: gap, isTruncated: shortened)
        }
        func candidate(_ arrangement: [String]) -> Self {
            let sample = measure(arrangement, size: reference)
            let factor = min(area.width / max(sample.inkSize.width, 1), area.height / max(sample.inkSize.height, 1))
            var result = measure(arrangement, size: reference * factor)
            // Account for final-size shaping/rounding. Never clip accents/descenders.
            for _ in 0..<2 {
                let correction = min(1, area.width / max(result.inkSize.width, 1), area.height / max(result.inkSize.height, 1))
                if correction >= 1 { break }
                result = measure(arrangement, size: result.pointSize * correction)
            }
            return result
        }
        var best = candidate(arrangements[0])
        let hangingWords: Set<String> = ["И", "В", "ВО", "НА", "С", "СО", "К", "ИЗ", "О", "ОБ", "ПО", "ДЛЯ", "THE", "A", "OF", "AND", "TO"]
        func score(_ layout: Self) -> CGFloat {
            let last = layout.lines.first?.text.split(separator: " ").last.map(String.init) ?? ""
            return layout.pointSize * (layout.lines.count > 1 && hangingWords.contains(last) ? 0.94 : 1)
        }
        for arrangement in arrangements.dropFirst() {
            let plan = candidate(arrangement)
            // Prefer a single line when a split would only gain a negligible size.
            if score(plan) > score(best) * (best.lines.count == 1 ? 1.04 : 1.001) { best = plan }
        }
        let minimum = CatalogFallbackTitleStyle.minimumPointSize * scale
        if best.pointSize < minimum {
            let readable = measure(best.lines.map(\.text), size: minimum, truncate: true)
            if readable.inkSize.width <= area.width && readable.inkSize.height <= area.height {
                best = readable
            }
        }
        cache.setObject(Cached(best), forKey: key)
        return best
    }

    private static func bounds(_ line: CTLine) -> CGRect {
        let ink = CTLineGetBoundsWithOptions(line, [.useGlyphPathBounds])
        if !ink.isEmpty && !ink.isNull { return ink }
        var ascent: CGFloat = 0, descent: CGFloat = 0
        let width = CTLineGetTypographicBounds(line, &ascent, &descent, nil)
        return CGRect(x: 0, y: -descent, width: width, height: ascent + descent)
    }
}
