import Foundation
import SwiftUI

/// Глобальная система скрытого логирования и отлова крашей.
class AppDiagnostics: ObservableObject {
    static let shared = AppDiagnostics()
    
    @Published var hasCrashLog = false
    
    private let logsFileURL: URL
    private let crashFileURL: URL
    
    private init() {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        let docDir = paths[0]
        
        logsFileURL = docDir.appendingPathComponent("sloosh_logs.txt")
        crashFileURL = docDir.appendingPathComponent("sloosh_crash.txt")
        
        checkPreviousCrash()
    }
    
    /// Записывает сообщение в скрытый файл логов.
    func log(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        let fileName = (file as NSString).lastPathComponent
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let logMessage = "[\(timestamp)] [\(fileName):\(line)] \(function) -> \(message)\n"
        
        #if DEBUG
        print(logMessage, terminator: "")
        #endif
        
        if let data = logMessage.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: logsFileURL.path) {
                if let fileHandle = try? FileHandle(forWritingTo: logsFileURL) {
                    fileHandle.seekToEndOfFile()
                    fileHandle.write(data)
                    fileHandle.closeFile()
                }
            } else {
                try? data.write(to: logsFileURL, options: .atomic)
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
        let wasRunning = UserDefaults.standard.bool(forKey: "sloosh_is_running")
        if wasRunning {
            // App was killed abruptly (OOM, Hang watchdog, or hard crash)
            hasCrashLog = true
            
            // Write a synthetic crash log if it doesn't exist
            if !FileManager.default.fileExists(atPath: crashFileURL.path) {
                let timestamp = ISO8601DateFormatter().string(from: Date())
                let hangMessage = """
                --- ABNORMAL TERMINATION ---
                Time: \(timestamp)
                Reason: The app was terminated abruptly (Hang, OOM, or force-kill).
                ----------------------------
                """
                try? hangMessage.write(to: crashFileURL, atomically: true, encoding: .utf8)
            }
        } else if FileManager.default.fileExists(atPath: crashFileURL.path) {
            // Caught by NSSetUncaughtExceptionHandler
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
        try? FileManager.default.removeItem(at: crashFileURL)
        DispatchQueue.main.async {
            self.hasCrashLog = false
        }
    }
    
    /// Очистить обычные логи (если разрослись)
    func clearNormalLogs() {
        try? FileManager.default.removeItem(at: logsFileURL)
    }
}
