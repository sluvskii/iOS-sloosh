import SwiftUI

struct LiquidSliderView: View {
    @Binding var value: Double // 0...1
    @Binding var isDragging: Bool
    
    var activeThickness: CGFloat = 12
    var inactiveThickness: CGFloat = 6
    var outsideThickness: CGFloat = 4
    
    var onSeek: ((Double) -> Void)?
    var onDragEnded: (() -> Void)?
    
    @State private var dragProgress: Double?
    @State private var dragLocationY: CGFloat = 0
    
    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let currentVal = dragProgress ?? value
            
            // Расстояние по вертикали от центра слайдера
            let distanceY = abs(dragLocationY - geo.size.height / 2)
            let isOutside = isDragging && distanceY > 40
            
            let currentThickness: CGFloat = isDragging
                ? (isOutside ? outsideThickness : activeThickness)
                : inactiveThickness
                
            ZStack(alignment: .leading) {
                // Фоновая полоска
                Capsule()
                    .fill(.white.opacity(0.25))
                    .frame(width: width, height: currentThickness)
                
                // Заполненная полоска
                Capsule()
                    .fill(.white)
                    .frame(width: max(currentThickness, width * CGFloat(currentVal)), height: currentThickness)
            }
            .position(x: width / 2, y: geo.size.height / 2)
            .contentShape(Rectangle()) // Увеличиваем хитбокс до размеров всего контейнера
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { val in
                        if !isDragging {
                            isDragging = true
                        }
                        dragLocationY = val.location.y
                        let percent = max(0, min(1, val.location.x / width))
                        dragProgress = percent
                        onSeek?(percent)
                    }
                    .onEnded { val in
                        isDragging = false
                        let percent = max(0, min(1, val.location.x / width))
                        value = percent
                        dragProgress = nil
                        onSeek?(percent)
                        onDragEnded?()
                    }
            )
        }
    }
}
