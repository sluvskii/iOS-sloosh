import Foundation
import JavaScriptCore

/// Универсальный кроссплатформенный движок выполнения динамических скрейперов (JavaScriptCore).
/// Загружает актуальные JS-модули парсеров с бэкенда (sloosh-api), выполняет их локально на устройстве
/// с реального IP пользователя (что исключает блокировки балансеров и 410 Gone) и возвращает готовые модели потоков.
final class ScraperEngine: @unchecked Sendable {
    static let shared = ScraperEngine()

    private let lock = NSLock()
    private var inMemoryScripts: [String: String] = [:]

    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        return URLSession(configuration: config)
    }()

    private init() {
        // Загружаем закэшированные скрипты из UserDefaults при старте
        if let cached = UserDefaults.standard.string(forKey: "sloosh_scraper_collaps"), !cached.isEmpty {
            inMemoryScripts["collaps"] = cached
        } else {
            inMemoryScripts["collaps"] = Self.bundledCollapsScraper
        }
    }

    // MARK: - Lifecycle & Remote Update

    /// Фоновый прогрев и обновление скрейперов при запуске приложения
    func warmup() async {
        await refreshScraper(id: "collaps")
    }

    /// Проверяет наличие обновленного скрейпера на сервере
    func refreshScraper(id: String) async {
        do {
            let envelope = try await MoviesApi.shared.fetchScraper(id: id)
            guard let scraperDto = envelope.data, !scraperDto.code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return
            }
            lock.lock()
            inMemoryScripts[id] = scraperDto.code
            lock.unlock()

            UserDefaults.standard.set(scraperDto.code, forKey: "sloosh_scraper_\(id)")
            AppDiagnostics.shared.log("ScraperEngine: updated scraper '\(id)' to version \(scraperDto.version)")
        } catch {
            // Игнорируем сетевые ошибки, используем закэшированный или встроенный скрипт
        }
    }

    func getScript(for id: String) -> String {
        lock.lock()
        defer { lock.unlock() }
        if let script = inMemoryScripts[id], !script.isEmpty {
            return script
        }
        if id == "collaps" {
            return Self.bundledCollapsScraper
        }
        return ""
    }

    // MARK: - Collaps Resolution via Remote JS

    /// Выполняет полный цикл резолва Collaps через динамический скрейпер:
    /// 1. Получает URL для embed и заголовки из JS
    /// 2. Делает HTTP GET с IP телефона
    /// 3. Парсит HTML в JavaScriptCore
    /// 4. Возвращает готовый ParseResult
    func resolveCollaps(
        kpId: Int?,
        imdbId: String?,
        title: String?,
        isTv: Bool?
    ) async -> CollapsParser.ParseResult? {
        let script = getScript(for: "collaps")
        guard !script.isEmpty else { return nil }

        let (embedUrls, headers) = getEmbedConfig(script: script, kpId: kpId, imdbId: imdbId)
        guard !embedUrls.isEmpty else { return nil }

        let resolvedTitle = title ?? "Видео"

        for urlString in embedUrls {
            guard let url = URL(string: urlString) else { continue }
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            for (k, v) in headers {
                request.setValue(v, forHTTPHeaderField: k)
            }

            do {
                let (data, response) = try await session.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                    continue
                }
                guard let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .windowsCP1251) else {
                    continue
                }

                if let catalog = parseHtml(script: script, html: html, title: resolvedTitle, isTv: isTv) {
                    if let parsed = CollapsParser.createResult(from: catalog, defaultTitle: resolvedTitle) {
                        return parsed
                    }
                }
            } catch {
                continue
            }
        }

        return nil
    }

    // MARK: - JavaScriptCore Execution

    private func getEmbedConfig(
        script: String,
        kpId: Int?,
        imdbId: String?
    ) -> (urls: [String], headers: [String: String]) {
        guard let context = JSContext() else {
            return defaultEmbedConfig(kpId: kpId, imdbId: imdbId)
        }
        context.evaluateScript(script)

        let kpVal = kpId ?? 0
        let imdbVal = imdbId ?? ""
        let evalCode = "SlooshCollapsScraper.getEmbedUrls({ kpId: \(kpVal), imdbId: '\(imdbVal)' })"
        guard let result = context.evaluateScript(evalCode), !result.isUndefined, !result.isNull else {
            return defaultEmbedConfig(kpId: kpId, imdbId: imdbId)
        }

        var urls: [String] = []
        var headers: [String: String] = [:]

        if let urlsValue = result.forProperty("urls"), urlsValue.isArray {
            if let arr = urlsValue.toArray() as? [String] {
                urls = arr
            }
        }
        if let headersValue = result.forProperty("headers"), headersValue.isObject {
            if let dict = headersValue.toDictionary() as? [String: String] {
                headers = dict
            }
        }

        if urls.isEmpty {
            return defaultEmbedConfig(kpId: kpId, imdbId: imdbId)
        }
        return (urls, headers)
    }

    private func parseHtml(
        script: String,
        html: String,
        title: String,
        isTv: Bool?
    ) -> CollapsCatalog? {
        guard let context = JSContext() else { return nil }
        context.evaluateScript(script)

        // Передаем HTML безопасно через глобальную переменную JSContext, чтобы не сломать экранирование
        context.setObject(html, forKeyedSubscript: "__raw_html" as NSString)
        
        let isTvParam = isTv.map { $0 ? "true" : "false" } ?? "undefined"
        let sanitizedTitle = title.replacingOccurrences(of: "'", with: "\\'")
        let evalCode = "SlooshCollapsScraper.parse(__raw_html, { title: '\(sanitizedTitle)', isTv: \(isTvParam) })"

        guard let result = context.evaluateScript(evalCode), !result.isUndefined, !result.isNull else {
            return nil
        }

        guard let jsonString = result.toString(), !jsonString.isEmpty && jsonString != "null" else {
            return nil
        }

        guard let data = jsonString.data(using: .utf8) else { return nil }

        do {
            let dto = try JSONDecoder().decode(CollapsStreamResponseDto.self, from: data)
            return dto.toCatalog()
        } catch {
            AppDiagnostics.shared.log("ScraperEngine parse JSON decode error: \(error)")
            return nil
        }
    }

    private func defaultEmbedConfig(kpId: Int?, imdbId: String?) -> (urls: [String], headers: [String: String]) {
        var urls: [String] = []
        if let kp = kpId, kp > 0 {
            urls.append("https://api.luxembd.ws/embed/kp/\(kp)")
        }
        if let imdb = imdbId, !imdb.isEmpty {
            urls.append("https://api.luxembd.ws/embed/imdb/\(imdb)")
        }
        let headers: [String: String] = [
            "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64)",
            "Referer": "https://kinokrad.my/",
            "Origin": "https://kinokrad.my",
            "Accept": "text/html,application/xhtml+xml"
        ]
        return (urls, headers)
    }

    // MARK: - Bundled Fallback Scraper

    static let bundledCollapsScraper: String = """
    var SlooshCollapsScraper = (function() {
      function normalizeStreamUrl(str) {
        if (!str) return null;
        str = String(str).trim().replace(/\\\\\\//g, "/");
        if (str.startsWith("//")) str = "https:" + str;
        return str;
      }

      function extractOrderedVoices(audioObj) {
        if (!audioObj || !Array.isArray(audioObj.names)) return [];
        var result = [];
        for (var i = 0; i < audioObj.names.length; i++) {
          var name = String(audioObj.names[i] || "").trim();
          if (name.toLowerCase() === "delete") {
            name = "Перевод " + (i + 1);
          }
          name = name.replace(/\"/g, "'");
          if (name) result.push(name);
        }
        return result;
      }

      function extractSubtitles(ccArray) {
        if (!Array.isArray(ccArray)) return [];
        var result = [];
        for (var i = 0; i < ccArray.length; i++) {
          var sub = ccArray[i];
          var url = String(sub.url || sub.src || "").trim();
          if (!url) continue;
          if (url.startsWith("//")) url = "https:" + url;
          var label = String(sub.name || sub.label || "Русский").trim();
          var rawLang = String(sub.lang || sub.language || "").trim();
          var lower = label.toLowerCase();
          var language = rawLang || ((lower.includes("eng") || lower.includes("original")) ? "en" : "ru");
          result.push({ url: url, label: label, language: language });
        }
        return result;
      }

      function extractSeasonsJson(html) {
        var match = html.match(/\\bseasons\\s*:\\s*\\[/i);
        if (!match || match.index === undefined) return null;
        var startIndex = match.index + match[0].length - 1;
        var depth = 0;
        var isQuoted = false;
        var quoteChar = "";
        var isEscaped = false;
        for (var i = startIndex; i < html.length; i++) {
          var char = html[i];
          if (isEscaped) { isEscaped = false; continue; }
          if (char === "\\\\") { isEscaped = true; continue; }
          if (char === '"' || char === "'") {
            if (!isQuoted) { isQuoted = true; quoteChar = char; }
            else if (char === quoteChar) { isQuoted = false; }
            continue;
          }
          if (!isQuoted) {
            if (char === "[") depth++;
            else if (char === "]") {
              depth--;
              if (depth === 0) return html.slice(startIndex, i + 1);
            }
          }
        }
        return null;
      }

      function extractJsonObject(html, key) {
        var regex = new RegExp("\\\\b" + key + "\\\\s*:\\\\s*\\\\{", "i");
        var match = html.match(regex);
        if (!match || match.index === undefined) return null;
        var startIndex = match.index + match[0].length - 1;
        var depth = 0;
        var isQuoted = false;
        var quoteChar = "";
        var isEscaped = false;
        for (var i = startIndex; i < html.length; i++) {
          var char = html[i];
          if (isEscaped) { isEscaped = false; continue; }
          if (char === "\\\\") { isEscaped = true; continue; }
          if (char === '"' || char === "'") {
            if (!isQuoted) { isQuoted = true; quoteChar = char; }
            else if (char === quoteChar) { isQuoted = false; }
            continue;
          }
          if (!isQuoted) {
            if (char === "{") depth++;
            else if (char === "}") {
              depth--;
              if (depth === 0) {
                try {
                  return JSON.parse(html.slice(startIndex, i + 1));
                } catch (e) {
                  return null;
                }
              }
            }
          }
        }
        return null;
      }

      function extractJsonArray(html, key) {
        var regex = new RegExp("\\\\b" + key + "\\\\s*:\\\\s*\\\\[", "i");
        var match = html.match(regex);
        if (!match || match.index === undefined) return null;
        var startIndex = match.index + match[0].length - 1;
        var depth = 0;
        var isQuoted = false;
        var quoteChar = "";
        var isEscaped = false;
        for (var i = startIndex; i < html.length; i++) {
          var char = html[i];
          if (isEscaped) { isEscaped = false; continue; }
          if (char === "\\\\") { isEscaped = true; continue; }
          if (char === '"' || char === "'") {
            if (!isQuoted) { isQuoted = true; quoteChar = char; }
            else if (char === quoteChar) { isQuoted = false; }
            continue;
          }
          if (!isQuoted) {
            if (char === "[") depth++;
            else if (char === "]") {
              depth--;
              if (depth === 0) {
                try {
                  return JSON.parse(html.slice(startIndex, i + 1));
                } catch (e) {
                  return null;
                }
              }
            }
          }
        }
        return null;
      }

      function parseSeries(seasonsJson, title) {
        try {
          var rawSeasons = JSON.parse(seasonsJson);
          if (!Array.isArray(rawSeasons)) return null;
          var collapsSeasons = [];
          for (var s = 0; s < rawSeasons.length; s++) {
            var seasonObj = rawSeasons[s];
            var seasonNum = parseInt(String(seasonObj.season || ""), 10);
            if (isNaN(seasonNum) || seasonNum <= 0 || !Array.isArray(seasonObj.episodes)) continue;
            var collapsEpisodes = [];
            for (var e = 0; e < seasonObj.episodes.length; e++) {
              var epObj = seasonObj.episodes[e];
              var episodeNum = parseInt(String(epObj.episode || ""), 10);
              if (isNaN(episodeNum)) continue;
              var hls = normalizeStreamUrl(epObj.hls);
              var dash = normalizeStreamUrl(epObj.dasha || epObj.dash);
              var primaryUrl = hls || dash || "";
              if (!primaryUrl) continue;
              var voices = extractOrderedVoices(epObj.audio);
              if (voices.length === 0) voices = ["Основной"];
              var subtitles = extractSubtitles(epObj.cc);
              collapsEpisodes.push({
                season: seasonNum,
                episode: episodeNum,
                title: episodeNum + " серия",
                playlist: {
                  primaryUrl: primaryUrl,
                  hlsUrl: hls,
                  dashUrl: dash,
                  voiceovers: voices,
                  subtitles: subtitles
                }
              });
            }
            if (collapsEpisodes.length > 0) {
              collapsEpisodes.sort(function(a, b) { return a.episode - b.episode; });
              collapsSeasons.push({
                season: seasonNum,
                title: seasonNum + " сезон",
                episodes: collapsEpisodes
              });
            }
          }
          if (collapsSeasons.length === 0) return null;
          collapsSeasons.sort(function(a, b) { return a.season - b.season; });
          return {
            kind: "series",
            source: "collaps",
            title: title || "Сериал",
            headers: {
              "Referer": "https://kinokrad.my/",
              "Origin": "https://kinokrad.my",
              "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64)"
            },
            seasons: collapsSeasons
          };
        } catch(err) {
          return null;
        }
      }

      function parseMovie(html, title) {
        try {
          var hlsMatch = html.match(/"hls"\\s*:\\s*"([^"]+)"/i);
          var dashMatch = html.match(/"dash"\\s*:\\s*"([^"]+)"/i) || html.match(/"dasha"\\s*:\\s*"([^"]+)"/i);
          var hls = hlsMatch ? normalizeStreamUrl(hlsMatch[1]) : null;
          var dash = dashMatch ? normalizeStreamUrl(dashMatch[1]) : null;
          var primaryUrl = hls || dash;
          if (!primaryUrl) return null;

          var voices = [];
          var audioObj = extractJsonObject(html, "audio");
          if (audioObj) voices = extractOrderedVoices(audioObj);
          if (voices.length === 0) voices = ["Основной"];

          var subtitles = [];
          var ccArray = extractJsonArray(html, "cc");
          if (ccArray) subtitles = extractSubtitles(ccArray);

          return {
            kind: "movie",
            source: "collaps",
            title: title || "Фильм",
            headers: {
              "Referer": "https://kinokrad.my/",
              "Origin": "https://kinokrad.my",
              "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64)"
            },
            playlist: {
              primaryUrl: primaryUrl,
              hlsUrl: hls,
              dashUrl: dash,
              voiceovers: voices,
              subtitles: subtitles
            }
          };
        } catch(err) {
          return null;
        }
      }

      return {
        id: "collaps",
        version: "1.0.0",
        getEmbedUrls: function(params) {
          var urls = [];
          if (params && params.kpId && Number(params.kpId) > 0) {
            urls.push("https://api.luxembd.ws/embed/kp/" + params.kpId);
          }
          if (params && params.imdbId) {
            urls.push("https://api.luxembd.ws/embed/imdb/" + params.imdbId);
          }
          return {
            urls: urls,
            headers: {
              "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64)",
              "Referer": "https://kinokrad.my/",
              "Origin": "https://kinokrad.my",
              "Accept": "text/html,application/xhtml+xml"
            }
          };
        },
        parse: function(html, params) {
          if (!html || typeof html !== "string") return null;
          params = params || {};
          var title = params.title || "Видео";
          var isTv = params.isTv;

          if (isTv === true) {
            var seasonsJson = extractSeasonsJson(html);
            if (seasonsJson) {
              var resSeries = parseSeries(seasonsJson, title);
              if (resSeries) return JSON.stringify(resSeries);
            }
          } else if (isTv === false) {
            var resMovie = parseMovie(html, title);
            if (resMovie) return JSON.stringify(resMovie);
          } else {
            var seasonsJsonMaybe = extractSeasonsJson(html);
            if (seasonsJsonMaybe) {
              var resSeriesMaybe = parseSeries(seasonsJsonMaybe, title);
              if (resSeriesMaybe) return JSON.stringify(resSeriesMaybe);
            }
            var resMovieMaybe = parseMovie(html, title);
            if (resMovieMaybe) return JSON.stringify(resMovieMaybe);
          }
          return null;
        }
      };
    })();
    """
}
