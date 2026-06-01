import Foundation
public class CollapsHTTPClient {
    private static func makeRequest(url: String, referer: String?, origin: String?) throws -> URLRequest {
        guard let requestUrl = URL(string: url) else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: requestUrl)
        request.httpMethod = "GET"
        if let referer {
            request.setValue(referer, forHTTPHeaderField: "Referer")
        }
        if let origin {
            request.setValue(origin, forHTTPHeaderField: "Origin")
        }
        request.setValue("Mozilla/5.0 (Windows NT 10.0; Win64; x64)", forHTTPHeaderField: "User-Agent")
        return request
    }

    public static func fetch(
        url: String,
        referer: String? = nil,
        origin: String? = nil
    ) async throws -> String {
        let request = try makeRequest(url: url, referer: referer, origin: origin)
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
        guard let text = String(data: data, encoding: .utf8) else {
            throw URLError(.cannotDecodeContentData)
        }
        return text
    }
}
