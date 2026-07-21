import SwiftUI
import TipKit

struct SharePlayTip: Tip {
    var title: Text {
        Text("Смотрите вместе!")
    }
    
    var message: Text? {
        Text("Нажмите здесь, чтобы начать сессию SharePlay и смотреть этот фильм с друзьями через FaceTime.")
    }
    
    var image: Image? {
        Image(systemName: "person.2.fill")
    }
}

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
}
