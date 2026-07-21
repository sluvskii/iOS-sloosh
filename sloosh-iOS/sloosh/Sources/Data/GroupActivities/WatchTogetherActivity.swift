import Foundation
import GroupActivities
import CoreTransferable

public struct WatchTogetherActivity: GroupActivity, Transferable {
    public let mediaId: String
    public let title: String
    
    public init(mediaId: String, title: String) {
        self.mediaId = mediaId
        self.title = title
    }
    
    public static let activityIdentifier = "ru.sloosh.WatchTogether"
    
    public var metadata: GroupActivityMetadata {
        var meta = GroupActivityMetadata()
        meta.title = title
        meta.type = .watchTogether
        return meta
    }
}
