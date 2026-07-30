import Foundation
import Network
import Combine
import UIKit

@MainActor
public final class NetworkMonitor: ObservableObject {
    public static let shared = NetworkMonitor()
    
    @Published public private(set) var isConnected: Bool = true
    @Published public private(set) var isCellular: Bool = false
    
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.sloosh.networkmonitor", qos: .utility)
    private var hasReportedInitial = false
    
    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let connected = path.status == .satisfied
            let cellular = path.usesInterfaceType(.cellular)
            
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                let wasConnected = self.isConnected
                self.isConnected = connected
                self.isCellular = cellular
                
                if self.hasReportedInitial {
                    if !connected && wasConnected {
                        ToastManager.shared.show(
                            title: "Нет подключения к сети",
                            icon: "wifi.slash"
                        )
                    } else if connected && !wasConnected {
                        ToastManager.shared.show(
                            title: "Подключение восстановлено",
                            icon: "wifi"
                        )
                    }
                } else {
                    self.hasReportedInitial = true
                }
            }
        }
        monitor.start(queue: queue)
    }
}
