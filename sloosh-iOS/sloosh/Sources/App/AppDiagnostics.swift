import Foundation
import SwiftUI

/// Глобальная система скрытого логирования и отлова крашей.
class AppDiagnostics: ObservableObject {
    static let shared = AppDiagnostics()
    
    @Published var hasCrashLog = false
    
    private let logsFileURL: URL
    private let crashFileURL: URL
    private let ioQueue = DispatchQueue(label: "ru.sloosh.appdiagnostics.io", qos: .utility)
    
    private init() {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        let docDir = paths[0]
        
        logsFileURL = docDir.appendingPathComponent("sloosh_logs.txt")
        crashFileURL = docDir.appendingPathComponent("sloosh_crash.txt")
        
        // Очищаем старые обычные логи при каждом перезапуске приложения,
        // чтобы логи всегда были свежими и не разрастались до десятков мегабайт.
        try? FileManager.default.removeItem(at: logsFileURL)
        
        // Записываем заголовок новой сессии
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let header = "=== Sloosh Session Started: [\(timestamp)] (iOS \(UIDevice.current.systemVersion)) ===\n"
        try? header.data(using: .utf8)?.write(to: logsFileURL, options: .atomic)
        
        checkPreviousCrash()
    }
    
    /// Записывает сообщение в файл логов с защитой от переполнения (макс. 2 МБ).
    func log(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        let fileName = (file as NSString).lastPathComponent
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let logMessage = "[\(timestamp)] [\(fileName):\(line)] \(function) -> \(message)\n"
        
        #if DEBUG
        print(logMessage, terminator: "")
        #endif
        
        ioQueue.async { [weak self] in
            guard let self = self else { return }
            guard let data = logMessage.data(using: .utf8) else { return }
            
            if FileManager.default.fileExists(atPath: self.logsFileURL.path) {
                // Если файл логов превысил 2 МБ за одну сессию, обрезаем старую половину
                if let attrs = try? FileManager.default.attributesOfItem(atPath: self.logsFileURL.path),
                   let size = attrs[.size] as? UInt64, size > 2 * 1024 * 1024 {
                    if let content = try? String(contentsOf: self.logsFileURL, encoding: .utf8) {
                        let lines = content.components(separatedBy: .newlines)
                        let trimmed = lines.suffix(lines.count / 2).joined(separator: "\n")
                        try? trimmed.write(to: self.logsFileURL, atomically: true, encoding: .utf8)
                    }
                }
                
                if let fileHandle = try? FileHandle(forWritingTo: self.logsFileURL) {
                    fileHandle.seekToEndOfFile()
                    try? fileHandle.write(contentsOf: data)
                    try? fileHandle.close()
                }
            } else {
                try? data.write(to: self.logsFileURL, options: .atomic)
            }
        }
    }
    
    /// Запускает отлов критических ошибок (крашей).
    func startCrashMonitoring() {
        NSSetUncaughtExceptionHandler { exception in
            let stack = exception.callStackSymbols.joined(separator: "\n")
            let timestamp = ISO8601DateFormatter().string(from: Date())
            let crashMessage = """
            --- CRASH REPORT ---
            Time: \(timestamp)
            Name: \(exception.name.rawValue)
            Reason: \(exception.reason ?? "Unknown")
            
            Stack Trace:
            \(stack)
            --------------------
            """
            
            let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
            let crashURL = paths[0].appendingPathComponent("sloosh_crash.txt")
            try? crashMessage.write(to: crashURL, atomically: true, encoding: .utf8)
        }
    }
    
    private func checkPreviousCrash() {
        if FileManager.default.fileExists(atPath: crashFileURL.path) {
            // Caught by NSSetUncaughtExceptionHandler or signal handler
            hasCrashLog = true
        }
    }
    
    func markRunning() {
        UserDefaults.standard.set(true, forKey: "sloosh_is_running")
    }
    
    func markGracefulExit() {
        UserDefaults.standard.set(false, forKey: "sloosh_is_running")
    }
    
    /// Получить URL файла с логами для отправки
    func getLogsURL() -> URL {
        return logsFileURL
    }
    
    /// Получить URL файла краша для отправки
    func getCrashURL() -> URL {
        return crashFileURL
    }
    
    /// Очистить файл краша после отправки или отмены
    func clearCrashLog() {
        ioQueue.async { [weak self] in
            guard let self = self else { return }
            try? FileManager.default.removeItem(at: self.crashFileURL)
            DispatchQueue.main.async {
                self.hasCrashLog = false
            }
        }
    }
    
    /// Получить последние строки логов для админ-панели
    public var recentLogs: [String] {
        var result: [String] = []

        if FileManager.default.fileExists(atPath: crashFileURL.path),
           let crashContent = try? String(contentsOf: crashFileURL, encoding: .utf8) {
            let lines = crashContent.components(separatedBy: .newlines).filter { !$0.isEmpty }
            result.append(contentsOf: lines.prefix(15))
        }

        if FileManager.default.fileExists(atPath: logsFileURL.path),
           let logsContent = try? String(contentsOf: logsFileURL, encoding: .utf8) {
            let lines = logsContent.components(separatedBy: .newlines).filter { !$0.isEmpty }
            result.append(contentsOf: lines.suffix(30).reversed())
        }

        return result
    }

    /// Очистить обычные логи (если разрослись)
    func clearNormalLogs() {
        ioQueue.async { [weak self] in
            guard let self = self else { return }
            try? FileManager.default.removeItem(at: self.logsFileURL)
        }
    }

    /// Очистить все логи (краши и диагностику)
    public func clearLogs() {
        clearCrashLog()
        clearNormalLogs()
    }
}
