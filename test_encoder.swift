import Foundation
let url = URL(string: "https://s3.collaps.io/hls/1234/master.m3u8")!
let absolutePath = url.path.isEmpty ? "/" : url.path
let query = url.query.map { "?\($0)" } ?? ""
let payload = "123456/\(absolutePath)\(query)"
print(payload)
