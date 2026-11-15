import UIKit

/// Экспорт тир-листа картинкой для соцсетей: полная доска (1080 шириной)
/// и вертикальный формат для сторис (1080×1920) с фирменной плашкой.
/// Постеры подтягиваются с прогрессом; отрисовка — UIGraphicsImageRenderer
/// (прецедент: renderCircularAvatar в ContentView).
enum TierListImageExporter {

    static func loadPosters(for list: TierList, progress: @escaping (Double) -> Void) async -> [String: UIImage] {
        let items = list.allItems
        var result: [String: UIImage] = [:]
        let unique = Dictionary(items.compactMap { item -> (String, String)? in
            guard let original = item.posterUrl, let resolved = item.resolvedPosterURL else { return nil }
            return (original, resolved)
        }, uniquingKeysWith: { first, _ in first })
        let entries = Array(unique)
        var completed = 0
        // Bounded batches avoid hundreds of simultaneous decodes on large boards.
        for offset in stride(from: 0, to: entries.count, by: 6) {
            guard !Task.isCancelled else { break }
            let batch = Array(entries[offset..<min(offset + 6, entries.count)])
            await withTaskGroup(of: (String, UIImage?).self) { group in
                for (key, value) in batch {
                    group.addTask {
                        guard !Task.isCancelled, let raw = URL(string: value), let url = ImageCache.resolveEffectiveUrl(raw) else { return (key, nil) }
                        if let cached = ImageCache.shared.image(forKey: url.absoluteString) { return (key, cached) }
                        do {
                            let (data, response) = try await ImageCache.session.data(for: URLRequest(url: url, timeoutInterval: 15))
                            guard !Task.isCancelled, let http = response as? HTTPURLResponse, http.statusCode == 200 else { return (key, nil) }
                            return (key, UIImage(data: data))
                        } catch { return (key, nil) }
                    }
                }
                for await (key, image) in group {
                    completed += 1
                    if let image { result[key] = image }
                    progress(Double(completed) / Double(max(1, entries.count)))
                }
            }
        }
        progress(1)
        return result
    }

    // MARK: Полная доска

    static func renderBoardImage(list: TierList, authorName: String?, posters: [String: UIImage]) -> UIImage {
        let width: CGFloat = 1080
        let margin: CGFloat = 32
        let chipWidth: CGFloat = 170
        let chipHeight: CGFloat = 110
        let posterWidth: CGFloat = 180
        let posterHeight: CGFloat = 270
        let spacing: CGFloat = 14
        let gridColumns = 4
        let gridWidth = width - margin * 2 - chipWidth - spacing

        // Предрасчёт раскладки строк (постеры в 4 колонки с переносом)
        struct Line { let y: CGFloat; let height: CGFloat }
        var rowLayouts: [(row: TierRow, y: CGFloat, height: CGFloat, gridHeight: CGFloat)] = []
        var unrankedLayout: (y: CGFloat, height: CGFloat, gridHeight: CGFloat)?
        var cursor: CGFloat = 0

        func measureGrid(items: [TierListItem]) -> (height: CGFloat, lines: [Int]) {
            let perLine = max(1, Int(gridWidth / (posterWidth + spacing)))
            var lines: [Int] = []
            var index = 0
            while index < items.count {
                let count = min(perLine, items.count - index)
                lines.append(count)
                index += count
            }
            let rowCount = max(1, lines.count)
            let height = CGFloat(rowCount) * posterHeight + CGFloat(max(0, rowCount - 1)) * spacing
            return (max(chipHeight, height) + spacing, lines)
        }

        for row in list.rows {
            let grid = measureGrid(items: row.items)
            let rowHeight = max(chipHeight + spacing, grid.height)
            rowLayouts.append((row, cursor, rowHeight, grid.height))
            cursor += rowHeight
        }
        if !list.unranked.isEmpty {
            let grid = measureGrid(items: list.unranked)
            unrankedLayout = (cursor, max(chipHeight + spacing, grid.height), grid.height)
            cursor += max(chipHeight + spacing, grid.height)
        }

        let headerHeight: CGFloat = 210
        let footerHeight: CGFloat = 120
        let contentHeight = max(400, cursor)
        let totalHeight = headerHeight + contentHeight + footerHeight

        let format = UIGraphicsImageRendererFormat()
        // Logical export dimensions are pixels, not device points (3× used
        // nine times the memory). Very long boards stay below a 24 MP budget.
        format.scale = min(1, sqrt(24_000_000 / (width * totalHeight)))
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: totalHeight), format: format)
        return renderer.image { context in
            let cg = context.cgContext
            // Фон
            drawBackground(cg: cg, width: width, height: totalHeight)

            // Шапка
            drawHeader(cg: cg, width: width, height: headerHeight, list: list, authorName: authorName)

            var y = headerHeight
            for layout in rowLayouts {
                // Чип уровня
                drawChip(
                    cg: cg,
                    rect: CGRect(x: margin, y: y, width: chipWidth, height: min(chipHeight + spacing, layout.height) - spacing),
                    label: layout.row.label,
                    colorHex: layout.row.colorHex
                )
                // Сетка постеров
                drawPosterGrid(
                    cg: cg,
                    items: layout.row.items,
                    x: margin + chipWidth + spacing,
                    y: y,
                    gridWidth: gridWidth,
                    posterWidth: posterWidth,
                    posterHeight: posterHeight,
                    spacing: spacing,
                    columns: gridColumns,
                    posters: posters
                )
                y += layout.height
            }

            if let pool = unrankedLayout {
                drawChip(
                    cg: cg,
                    rect: CGRect(x: margin, y: y, width: chipWidth, height: min(chipHeight + spacing, pool.height) - spacing),
                    label: "?",
                    colorHex: "555B57"
                )
                drawPosterGrid(
                    cg: cg,
                    items: list.unranked,
                    x: margin + chipWidth + spacing,
                    y: y,
                    gridWidth: gridWidth,
                    posterWidth: posterWidth,
                    posterHeight: posterHeight,
                    spacing: spacing,
                    columns: gridColumns,
                    posters: posters
                )
            }

            // Подвал: вотермарка + ссылка
            drawFooter(cg: cg, width: width, height: footerHeight, y: headerHeight + contentHeight, list: list)
        }
    }

    // MARK: Сторис 1080×1920

    static func renderStoriesImage(list: TierList, authorName: String?, posters: [String: UIImage]) -> UIImage {
        let boardImage = renderBoardImage(list: list, authorName: authorName, posters: posters)
        let width: CGFloat = 1080
        let height: CGFloat = 1920
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format)
        return renderer.image { context in
            let cg = context.cgContext
            let colors = [
                UIColor(red: 0.05, green: 0.06, blue: 0.08, alpha: 1).cgColor,
                UIColor(red: 0.10, green: 0.11, blue: 0.14, alpha: 1).cgColor
            ]
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: [0, 1]) {
                cg.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: height), options: [])
            }

            // Заголовок
            let titleAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 52, weight: .heavy),
                .foregroundColor: UIColor.white
            ]
            let title = (list.title as NSString).boundingRect(
                with: CGSize(width: width - 120, height: 400),
                options: [.usesLineFragmentOrigin],
                attributes: titleAttributes,
                context: nil
            )
            (list.title as NSString).draw(
                in: CGRect(x: 60, y: 110, width: width - 120, height: title.height + 8),
                withAttributes: titleAttributes
            )
            if let author = authorName {
                let authorAttributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 30, weight: .semibold),
                    .foregroundColor: UIColor.white.withAlphaComponent(0.6)
                ]
                (author as NSString).draw(at: CGPoint(x: 60, y: 130 + title.height), withAttributes: authorAttributes)
            }

            // Доска по центру, вписанная по ширине
            let boardScale = min((width - 80) / boardImage.size.width, (height - 440) / boardImage.size.height)
            let boardSize = CGSize(width: boardImage.size.width * boardScale, height: boardImage.size.height * boardScale)
            let boardY = min(max(200, (height - boardSize.height) / 2), height - boardSize.height - 140)
            boardImage.draw(in: CGRect(x: 40, y: boardY, width: boardSize.width, height: boardSize.height))

            // Плашка бренда
            let brandAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 34, weight: .heavy),
                .foregroundColor: UIColor.white
            ]
            let brand = "sloosh"
            let brandSize = (brand as NSString).size(withAttributes: brandAttributes)
            let brandRect = CGRect(x: 60, y: height - 120, width: brandSize.width + 28, height: brandSize.height + 20)
            UIColor(white: 0.18, alpha: 0.9).setFill()
            UIBezierPath(roundedRect: brandRect, cornerRadius: 14).fill()
            (brand as NSString).draw(at: CGPoint(x: brandRect.minX + 14, y: brandRect.minY + 10), withAttributes: brandAttributes)
        }
    }

    // MARK: Примитивы

    private static func drawBackground(cg: CGContext, width: CGFloat, height: CGFloat) {
        UIColor(red: 0.06, green: 0.07, blue: 0.08, alpha: 1).setFill()
        cg.fill(CGRect(x: 0, y: 0, width: width, height: height))
    }

    private static func drawHeader(cg: CGContext, width: CGFloat, height: CGFloat, list: TierList, authorName: String?) {
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 54, weight: .heavy),
            .foregroundColor: UIColor.white
        ]
        let title = (list.title as NSString).boundingRect(
            with: CGSize(width: width - 100, height: 300),
            options: [.usesLineFragmentOrigin],
            attributes: titleAttributes,
            context: nil
        )
        (list.title as NSString).draw(in: CGRect(x: 50, y: 50, width: width - 100, height: title.height + 8), withAttributes: titleAttributes)

        if let author = authorName {
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 30, weight: .semibold),
                .foregroundColor: UIColor.white.withAlphaComponent(0.55)
            ]
            (author as NSString).draw(at: CGPoint(x: 50, y: 68 + title.height), withAttributes: attributes)
        }
    }

    private static func drawChip(cg: CGContext, rect: CGRect, label: String, colorHex: String) {
        let color = UIColor(hex: colorHex) ?? .systemGray
        let path = UIBezierPath(roundedRect: rect, cornerRadius: 24)
        color.setFill()
        path.fill()
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 64, weight: .heavy),
            .foregroundColor: UIColor.white
        ]
        let text = label as NSString
        let size = text.size(withAttributes: attributes)
        text.draw(
            at: CGPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2),
            withAttributes: attributes
        )
    }

    private static func drawPosterGrid(
        cg: CGContext,
        items: [TierListItem],
        x: CGFloat,
        y: CGFloat,
        gridWidth: CGFloat,
        posterWidth: CGFloat,
        posterHeight: CGFloat,
        spacing: CGFloat,
        columns: Int,
        posters: [String: UIImage]
    ) {
        for (index, item) in items.enumerated() {
            let column = index % columns
            let line = index / columns
            let rect = CGRect(
                x: x + CGFloat(column) * (posterWidth + spacing),
                y: y + CGFloat(line) * (posterHeight + spacing),
                width: posterWidth,
                height: posterHeight
            )
            if let image = posters[item.posterUrl ?? ""] {
                let path = UIBezierPath(roundedRect: rect, cornerRadius: 18)
                cg.saveGState()
                path.addClip()
                // Cover-кроп
                let imageSize = image.size
                let scale = max(rect.width / imageSize.width, rect.height / imageSize.height)
                let drawSize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
                image.draw(
                    in: CGRect(
                        x: rect.midX - drawSize.width / 2,
                        y: rect.midY - drawSize.height / 2,
                        width: drawSize.width,
                        height: drawSize.height
                    )
                )
                cg.restoreGState()
            } else {
                UIColor.white.withAlphaComponent(0.08).setFill()
                UIBezierPath(roundedRect: rect, cornerRadius: 18).fill()
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 44, weight: .bold),
                    .foregroundColor: UIColor.white.withAlphaComponent(0.4)
                ]
                let letter = String(item.title.prefix(1)) as NSString
                let size = letter.size(withAttributes: attributes)
                letter.draw(at: CGPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2), withAttributes: attributes)
            }
        }
    }

    private static func drawFooter(cg: CGContext, width: CGFloat, height: CGFloat, y: CGFloat, list: TierList) {
        UIColor(white: 0.18, alpha: 0.9).setFill()
        let brandRect = CGRect(x: 50, y: y + height / 2 - 36, width: 220, height: 72)
        UIBezierPath(roundedRect: brandRect, cornerRadius: 18).fill()
        let brandAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 42, weight: .heavy),
            .foregroundColor: UIColor.white
        ]
        ("sloosh" as NSString).draw(at: CGPoint(x: brandRect.minX + 24, y: brandRect.minY + 12), withAttributes: brandAttributes)

        let link = "https://sluvskii.github.io/iOS-sloosh/?tier=\(list.id)"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 26, weight: .medium),
            .foregroundColor: UIColor.white.withAlphaComponent(0.45)
        ]
        (link as NSString).draw(at: CGPoint(x: brandRect.maxX + 26, y: y + height / 2 - 16), withAttributes: attributes)
    }
}
