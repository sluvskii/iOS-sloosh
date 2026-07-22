import SwiftUI
import TipKit

struct DoubleTapTip: Tip {
    var title: Text {
        Text("Перемотка")
    }
    
    var message: Text? {
        Text("Дважды коснитесь краев экрана, чтобы перемотать видео на 10 секунд.")
    }
    
    var image: Image? {
        Image(systemName: "goforward.10")
    }
    
    var options: [TipOption] {
        [Tip.MaxDisplayCount(1)]
    }
}
