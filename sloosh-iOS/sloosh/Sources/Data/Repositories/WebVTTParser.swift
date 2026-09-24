import Foundation

public struct SubtitleCue: Identifiable, Sendable, Equatable {
    public let id: Int
    public let start: TimeInterval
    public let end: TimeInterval
    public let text: String

    public init(id: Int, start: TimeInterval, end: TimeInterval, text: String) {
        self.id = id
        self.start = start
        self.end = end
        self.text = text
    }
}

public enum WebVTTParser {
    /// Парсит содержимое WebVTT или SRT в массив отсортированных реплик SubtitleCue
    public static func parse(text: String) -> [SubtitleCue] {
        var cues: [SubtitleCue] = []
        // Удаляем UTF-8 BOM если есть
        let cleanInput = text.replacingOccurrences(of: "\u{FEFF}", with: "")
        let normalized = cleanInput
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized.components(separatedBy: "\n")
        
        var currentIndex = 0
        var cueCounter = 0
        let totalLines = lines.count

        while currentIndex < totalLines {
            let line = lines[currentIndex].trimmingCharacters(in: .whitespaces)

            // Проверяем строку с таймкодами (содержит "-->")
            if line.contains("-->") {
                if let (start, end) = parseTimestampLine(line) {
                    var textLines: [String] = []
                    currentIndex += 1
                    while currentIndex < totalLines {
                        let textLine = lines[currentIndex]
                        if textLine.trimmingCharacters(in: .whitespaces).isEmpty {
                            break
                        }
                        textLines.append(textLine)
                        currentIndex += 1
                    }
                    let rawText = textLines.joined(separator: "\n")
                    let cleanText = cleanCueText(rawText)
                    if !cleanText.isEmpty {
                        cueCounter += 1
                        cues.append(SubtitleCue(id: cueCounter, start: start, end: end, text: cleanText))
                    }
                } else {
                    currentIndex += 1
                }
            } else {
                currentIndex += 1
            }
        }

        return cues.sorted { $0.start < $1.start }
    }

    private static func parseTimestampLine(_ line: String) -> (TimeInterval, TimeInterval)? {
        let parts = line.components(separatedBy: "-->")
        guard parts.count == 2 else { return nil }
        
        let startPart = parts[0].trimmingCharacters(in: .whitespaces)
        // Правая часть может содержать параметры позиционирования, например: "00:01:23.456 align:start size:50%"
        let endPartRaw = parts[1].trimmingCharacters(in: .whitespaces)
        let endPart = endPartRaw.components(separatedBy: .whitespaces).first ?? endPartRaw

        guard let startSec = parseTimecode(startPart),
              let endSec = parseTimecode(endPart) else {
            return nil
        }
        return (startSec, endSec)
    }

    public static func parseTimecode(_ timeString: String) -> TimeInterval? {
        let clean = timeString.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)
        let components = clean.components(separatedBy: ":")
        
        if components.count == 3 {
            // ЧЧ:ММ:СС.ммм
            guard let h = Double(components[0]),
                  let m = Double(components[1]),
                  let s = Double(components[2]) else { return nil }
            return h * 3600.0 + m * 60.0 + s
        } else if components.count == 2 {
            // ММ:СС.ммм
            guard let m = Double(components[0]),
                  let s = Double(components[1]) else { return nil }
            return m * 60.0 + s
        } else if components.count == 1 {
            // СС.ммм
            return Double(components[0])
        }
        return nil
    }

    public static func cleanCueText(_ text: String) -> String {
        var result = text
        // Удаляем теги форматирования VTT: <c.color>, <v Speaker>, <b>, </i>, <u> и т.д.
        let tagRegex = try? NSRegularExpression(pattern: #"<[^>]+>"#, options: [])
        let range = NSRange(result.startIndex..<result.endIndex, in: result)
        result = tagRegex?.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "") ?? result

        // Декодируем стандартные HTML-сущности
        result = result
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&nbsp;", with: " ")

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Быстрый бинарный поиск реплики для заданного времени `time` (в секундах).
    /// Поддерживает объединение реплик при одновременном звучании нескольких спикеров.
    public static func cue(at time: TimeInterval, in cues: [SubtitleCue]) -> SubtitleCue? {
        guard !cues.isEmpty else { return nil }
        
        var low = 0
        var high = cues.count - 1
        var candidateIdx = -1

        while low <= high {
            let mid = (low + high) / 2
            if cues[mid].end >= time {
                candidateIdx = mid
                high = mid - 1
            } else {
                low = mid + 1
            }
        }

        if candidateIdx >= 0 {
            var matchingTexts: [String] = []
            for i in candidateIdx..<min(cues.count, candidateIdx + 6) {
                let c = cues[i]
                if c.start <= time && time <= c.end {
                    matchingTexts.append(c.text)
                }
                if c.start > time + 5.0 {
                    break
                }
            }
            if !matchingTexts.isEmpty {
                let combinedText = matchingTexts.joined(separator: "\n")
                return SubtitleCue(id: candidateIdx, start: time, end: time, text: combinedText)
            }
        }
        return nil
    }
}
