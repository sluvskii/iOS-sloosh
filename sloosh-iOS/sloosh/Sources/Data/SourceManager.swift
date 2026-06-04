import Foundation
import SwiftUI

enum SourceMode: String, CaseIterable, Identifiable {
    case collaps = "COLLAPS"
    case alloha = "ALLOHA"
    case cdn = "CDN"
    
    var id: String { self.rawValue }
    
    var displayName: String {
        switch self {
        case .collaps: return "Collaps"
        case .alloha: return "Alloha"
        case .cdn: return "Основной"
        }
    }
}

class SourceManager: ObservableObject {
    static let shared = SourceManager()
    
    @AppStorage("source_mode") var currentMode: SourceMode = .alloha
}
