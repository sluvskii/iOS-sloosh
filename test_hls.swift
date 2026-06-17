import Foundation

let base = "https://api.bhcesh.me"
let kpId = 326

let sema = DispatchSemaphore(value: 0)

Task {
    do {
        let url = URL(string: "\(base)/embed/kp/\(kpId)")!
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        request.setValue("https://kinokrad.my", forHTTPHeaderField: "Origin")
        request.setValue("https://kinokrad.my/", forHTTPHeaderField: "Referer")
        
        let (data, _) = try await URLSession.shared.data(for: request)
        let html = String(data: data, encoding: .utf8) ?? ""
        
        let pattern = "hls:\\s+['"](https?:\\/\\/[^\\"']+\\.m3u[^\\"']*)['"]"
        let regex = try NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        if let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
           let range = Range(match.range(at: 1), in: html) {
            let hlsUrlStr = String(html[range]).replacingOccurrences(of: "\\/", with: "/")
            print("Found HLS URL: \(hlsUrlStr)")
            
            if let hlsUrl = URL(string: hlsUrlStr) {
                var hlsReq = URLRequest(url: hlsUrl)
                hlsReq.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
                hlsReq.setValue("https://kinokrad.my", forHTTPHeaderField: "Origin")
                hlsReq.setValue("https://kinokrad.my/", forHTTPHeaderField: "Referer")
                
                let (hlsData, _) = try await URLSession.shared.data(for: hlsReq)
                if let m3u8 = String(data: hlsData, encoding: .utf8) {
                    print("--- HLS MANIFEST ---")
                    let lines = m3u8.components(separatedBy: .newlines)
                    for line in lines where line.hasPrefix("#EXT-X-MEDIA:TYPE=AUDIO") {
                        print(line)
                    }
                }
            }
        }
    } catch {
        print(error)
    }
    sema.signal()
}

sema.wait()
