import Foundation
import SwiftUI

enum SourceMode: String, CaseIterable, Identifiable {
    case collaps = "COLLAPS"
    case alloha = "ALLOHA"
    
    var id: String { self.rawValue }
    
    var displayName: String {
        switch self {
        case .collaps: return "Collaps (Online)"
        case .alloha: return "Alloha (Online)"
        }
    }
}

class SourceManager: ObservableObject {
    static let shared = SourceManager()
    
    @AppStorage("source_mode") var currentMode: SourceMode = .alloha
}
