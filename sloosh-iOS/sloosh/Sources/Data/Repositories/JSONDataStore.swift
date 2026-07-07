import Foundation

final class JSONDataStore<T: Codable> {
    private let fileName: String
    private let fileURL: URL
    
    private let queue: DispatchQueue
    private var cachedData: T?
    
    init(fileName: String) {
        self.fileName = fileName
        let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        self.fileURL = documentsDir.appendingPathComponent("\(fileName).json")
        self.queue = DispatchQueue(label: "ru.neomovies.jsondatastore.\(fileName)", attributes: .concurrent)
    }
    
    func load(defaultValue: T) -> T {
        return queue.sync {
            if let data = cachedData {
                return data
            }
            
            guard let rawData = try? Data(contentsOf: fileURL) else {
                cachedData = defaultValue
                return defaultValue
            }
            
            do {
                let decoded = try JSONDecoder().decode(T.self, from: rawData)
                cachedData = decoded
                return decoded
            } catch {
                print("Error decoding \(fileName): \(error)")
                cachedData = defaultValue
                return defaultValue
            }
        }
    }
    
    func save(_ data: T) {
        queue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            self.cachedData = data
            let url = self.fileURL
            
            DispatchQueue.global(qos: .utility).async {
                do {
                    let encoded = try JSONEncoder().encode(data)
                    try encoded.write(to: url, options: .atomic)
                } catch {
                    print("Error saving \(self.fileName): \(error)")
                }
            }
        }
    }
}
