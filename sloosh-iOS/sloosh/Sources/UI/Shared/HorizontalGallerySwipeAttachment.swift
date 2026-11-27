import SwiftUI
import UIKit

/// Snapshot of vertical scroll geometry used to align incoming horizontal gallery pages
/// without disturbing the enclosing native ScrollView and iOS 26 progressive edge effects.
struct HorizontalGalleryScrollMetrics: Equatable {
    var topOffset: CGFloat
    var width: CGFloat
    var fullHeight: CGFloat
    var topInset: CGFloat

    static func from(_ geometry: ScrollGeometry) -> HorizontalGalleryScrollMetrics {
        HorizontalGalleryScrollMetrics(
            topOffset: max(0, geometry.contentOffset.y + geometry.contentInsets.top),
            width: max(1, geometry.containerSize.width),
            fullHeight: max(200, geometry.containerSize.height + geometry.contentInsets.bottom),
            topInset: max(0, geometry.contentInsets.top)
        )
    }
}

/// Non-publishing reference box holding live scroll metrics and per-category scroll offsets
/// so vertical scrolling never invalidates the gallery swipe state tree on every frame.
final class HorizontalGalleryMetricsBox<Category: Hashable> {
    var topOffset: CGFloat = 0
    var width: CGFloat = UIScreen.main.bounds.width
    var fullHeight: CGFloat = UIScreen.main.bounds.height
    var topInset: CGFloat = 0
    var savedScrollOffsets: [Category: CGFloat] = [:]

    func apply(_ newMetrics: HorizontalGalleryScrollMetrics) {
        topOffset = newMetrics.topOffset
        width = newMetrics.width
        fullHeight = newMetrics.fullHeight
        topInset = newMetrics.topInset
    }

    /// Computes how far an incoming scrolled pane must bleed upward behind the translucent top bar
    /// so it fills from screen top down even when the outgoing page is at offset 0.
    func topBleed(isActive: Bool, savedY: CGFloat, extraTopMargin: CGFloat) -> CGFloat {
        guard !isActive, savedY > 0 else { return 0 }
        return min(savedY, topInset + extraTopMargin)
    }
}

/// Shared state machine and velocity-aware native spring driver for horizontal category paging
/// inside a single native vertical ScrollView.
@MainActor
final class HorizontalGallerySwipeController<Category: Hashable>: ObservableObject {
    @Published var dragOffset: CGFloat = 0
    @Published var slideDirection: Int = 0
    @Published var overridePreviewCategory: Category? = nil

    var isAnimatingSnap: Bool = false
    var snapGeneration: Int = 0
    weak var attachedScrollView: UIScrollView? = nil

    static var pageGap: CGFloat { 16 }

    func relativeCategory(from current: Category, in all: [Category], step: Int) -> Category? {
        guard let currentIndex = all.firstIndex(of: current) else { return nil }
        let targetIndex = currentIndex + step
        guard targetIndex >= 0 && targetIndex < all.count else { return nil }
        return all[targetIndex]
    }

    func incomingCategory(current: Category, in all: [Category]) -> Category? {
        if let override = overridePreviewCategory {
            return override
        }
        guard slideDirection != 0 else { return nil }
        return relativeCategory(from: current, in: all, step: slideDirection > 0 ? 1 : -1)
    }

    func visibleCategories(current: Category, in all: [Category]) -> [Category] {
        if let incoming = incomingCategory(current: current, in: all), incoming != current {
            return [current, incoming]
        }
        return [current]
    }

    func effectiveOffset(current: Category, in all: [Category], pageWidth: CGFloat) -> CGFloat {
        if overridePreviewCategory != nil {
            return dragOffset
        }
        guard dragOffset != 0 else { return 0 }
        let step = dragOffset < 0 ? 1 : -1
        if relativeCategory(from: current, in: all, step: step) != nil {
            return dragOffset
        }
        let sign: CGFloat = dragOffset >= 0 ? 1 : -1
        let absX = abs(dragOffset)
        let limit = max(240, pageWidth * 0.75)
        return sign * (absX * 0.25 / (1 + absX / limit))
    }

    func handlePanChanged(
        _ translationX: CGFloat,
        current: Category,
        in all: [Category],
        pageWidth: CGFloat,
        preloadIfNeeded: ((Category?) -> Void)? = nil,
        onPreviewCandidate: ((Category?, CGFloat) -> Void)? = nil
    ) {
        guard !isAnimatingSnap else { return }
        if translationX < -2 {
            slideDirection = 1
            preloadIfNeeded?(relativeCategory(from: current, in: all, step: 1))
        } else if translationX > 2 {
            slideDirection = -1
            preloadIfNeeded?(relativeCategory(from: current, in: all, step: -1))
        }
        dragOffset = translationX

        let candidate = translationX < 0
            ? relativeCategory(from: current, in: all, step: 1)
            : relativeCategory(from: current, in: all, step: -1)
        onPreviewCandidate?(candidate, translationX)
    }

    func handlePanEnded(
        _ translationX: CGFloat,
        velocityX: CGFloat,
        didFinish: Bool,
        metrics: HorizontalGalleryMetricsBox<Category>,
        current: Category,
        in all: [Category],
        pageWidth: CGFloat,
        preloadIfNeeded: ((Category?) -> Void)? = nil,
        onPrepareCommitHeader: ((Category) -> Void)? = nil,
        onPrepareCancelHeader: (() -> Void)? = nil,
        isStillCurrent: @escaping (Category) -> Bool,
        onCommitState: @escaping (Category) -> Void
    ) {
        guard !isAnimatingSnap else { return }
        guard didFinish else {
            cancelSwipe(velocityX: 0, onPrepareHeader: onPrepareCancelHeader)
            return
        }
        let stepStride = pageWidth + Self.pageGap
        let threshold = pageWidth * 0.25
        let projectedX = translationX + velocityX * 0.14

        if let next = relativeCategory(from: current, in: all, step: 1),
           ((projectedX < -threshold && velocityX <= 120) || velocityX < -320) {
            slideDirection = 1
            preloadIfNeeded?(next)
            commitSwitch(
                metrics: metrics,
                outgoingCategory: current,
                targetCategory: next,
                finalOffset: -stepStride,
                velocityX: velocityX,
                onPrepareHeader: { onPrepareCommitHeader?(next) },
                isStillCurrent: isStillCurrent,
                onCommitState: { onCommitState(next) }
            )
        } else if let prev = relativeCategory(from: current, in: all, step: -1),
                  ((projectedX > threshold && velocityX >= -120) || velocityX > 320) {
            slideDirection = -1
            preloadIfNeeded?(prev)
            commitSwitch(
                metrics: metrics,
                outgoingCategory: current,
                targetCategory: prev,
                finalOffset: stepStride,
                velocityX: velocityX,
                onPrepareHeader: { onPrepareCommitHeader?(prev) },
                isStillCurrent: isStillCurrent,
                onCommitState: { onCommitState(prev) }
            )
        } else {
            cancelSwipe(velocityX: velocityX, onPrepareHeader: onPrepareCancelHeader)
        }
    }

    func handleRequestedCategoryChange(
        to target: Category,
        metrics: HorizontalGalleryMetricsBox<Category>,
        current: Category,
        in all: [Category],
        scrollToTop: () -> Void,
        preloadIfNeeded: ((Category?) -> Void)? = nil,
        onPrepareCommitHeader: ((Category) -> Void)? = nil,
        isStillCurrent: @escaping (Category) -> Bool,
        onCommitState: @escaping (Category) -> Void
    ) {
        guard !isAnimatingSnap else { return }
        if target == current {
            metrics.savedScrollOffsets[target] = 0
            scrollToTop()
            return
        }
        guard let currentIndex = all.firstIndex(of: current),
              let targetIndex = all.firstIndex(of: target) else {
            onCommitState(target)
            return
        }
        let isForward = targetIndex > currentIndex
        overridePreviewCategory = target
        slideDirection = isForward ? 1 : -1
        preloadIfNeeded?(target)
        let stride = max(1, metrics.width) + Self.pageGap
        commitSwitch(
            metrics: metrics,
            outgoingCategory: current,
            targetCategory: target,
            finalOffset: isForward ? -stride : stride,
            velocityX: 0,
            onPrepareHeader: { onPrepareCommitHeader?(target) },
            isStillCurrent: isStillCurrent,
            onCommitState: { onCommitState(target) }
        )
    }

    func commitSwitch(
        metrics: HorizontalGalleryMetricsBox<Category>,
        outgoingCategory: Category,
        targetCategory: Category,
        finalOffset: CGFloat,
        velocityX: CGFloat = 0,
        onPrepareHeader: (() -> Void)? = nil,
        isStillCurrent: @escaping (Category) -> Bool,
        onCommitState: @escaping () -> Void
    ) {
        snapGeneration += 1
        let generation = snapGeneration
        isAnimatingSnap = true
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        onPrepareHeader?()

        let finalizeSwitch = { [weak self] in
            guard let self, self.snapGeneration == generation, self.isAnimatingSnap else { return }
            metrics.savedScrollOffsets[outgoingCategory] = metrics.topOffset
            let targetY = metrics.savedScrollOffsets[targetCategory] ?? 0

            CATransaction.begin()
            CATransaction.setDisableActions(true)
            if let sv = self.attachedScrollView {
                let topY = -sv.adjustedContentInset.top
                let desiredY = topY + targetY
                if abs(sv.contentOffset.y - desiredY) > 0.5 {
                    sv.setContentOffset(CGPoint(x: 0, y: desiredY), animated: false)
                }
            }
            var tx = Transaction()
            tx.disablesAnimations = true
            withTransaction(tx) {
                self.dragOffset = 0
                self.slideDirection = 0
                self.overridePreviewCategory = nil
                metrics.topOffset = targetY
                onCommitState()
            }
            CATransaction.commit()
            self.isAnimatingSnap = false

            if targetY > 0, let sv = self.attachedScrollView {
                DispatchQueue.main.async { [weak sv] in
                    guard let sv,
                          isStillCurrent(targetCategory),
                          !sv.isTracking,
                          !sv.isDragging,
                          !sv.isDecelerating else { return }
                    let topY = -sv.adjustedContentInset.top
                    let maxY = max(topY, sv.contentSize.height - sv.bounds.height + sv.adjustedContentInset.bottom)
                    let clampedY = min(topY + targetY, maxY)
                    if abs(sv.contentOffset.y - clampedY) > 1 {
                        sv.setContentOffset(CGPoint(x: 0, y: clampedY), animated: false)
                    }
                }
            }
        }

        let speed = abs(velocityX)
        let clampedRatio = min(1.0, max(0.0, speed / 1200.0))
        let response = max(0.32, 0.44 - Double(clampedRatio) * 0.12)
        let pageWidth = max(1, metrics.width)
        let remaining = abs(finalOffset - dragOffset)
        let damping: Double = remaining < pageWidth * 0.35 ? 0.90 : 0.86

        withAnimation(.spring(response: response, dampingFraction: damping)) {
            dragOffset = finalOffset
        } completion: {
            finalizeSwitch()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + response + 0.45) {
            finalizeSwitch()
        }
    }

    func cancelSwipe(velocityX: CGFloat = 0, onPrepareHeader: (() -> Void)? = nil) {
        snapGeneration += 1
        let generation = snapGeneration
        isAnimatingSnap = true
        onPrepareHeader?()

        let finalizeCancel = { [weak self] in
            guard let self, self.snapGeneration == generation, self.isAnimatingSnap else { return }
            var tx = Transaction()
            tx.disablesAnimations = true
            withTransaction(tx) {
                self.dragOffset = 0
                self.slideDirection = 0
                self.overridePreviewCategory = nil
            }
            self.isAnimatingSnap = false
        }

        let speed = abs(velocityX)
        let response = speed > 600 ? 0.34 : 0.40
        withAnimation(.spring(response: response, dampingFraction: 0.82)) {
            dragOffset = 0
        } completion: {
            finalizeCancel()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + response + 0.40) {
            finalizeCancel()
        }
    }

    func resetImmediately(onResetHeader: (() -> Void)? = nil) {
        snapGeneration += 1
        var tx = Transaction()
        tx.disablesAnimations = true
        withTransaction(tx) {
            dragOffset = 0
            slideDirection = 0
            overridePreviewCategory = nil
            onResetHeader?()
        }
        isAnimatingSnap = false
    }
}

extension View {
    /// Gently softens the top edge of a scrolled incoming gallery preview before native
    /// vertical scroll-edge blur engages at transition completion.
    func horizontalGalleryIncomingTopFade(
        isActive: Bool,
        outgoingTopOffset: CGFloat,
        topBleed: CGFloat
    ) -> some View {
        let shouldFade = !isActive && topBleed > 0 && outgoingTopOffset < 4
        return overlay(alignment: .top) {
            LinearGradient(
                stops: [
                    .init(color: Color(uiColor: .systemBackground).opacity(0.78), location: 0),
                    .init(color: Color(uiColor: .systemBackground).opacity(0.42), location: 0.68),
                    .init(color: Color(uiColor: .systemBackground).opacity(0), location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: shouldFade ? topBleed : 0)
            .opacity(shouldFade ? 1 : 0)
            .allowsHitTesting(false)
        }
    }
}

/// Attaches a horizontal pan gesture recognizer directly to the enclosing vertical UIScrollView
/// so horizontal swipes never fight vertical scrolling or block interactive pop / edge gestures.
struct HorizontalGallerySwipeAttachment: UIViewRepresentable {
    let isLocked: Bool
    let onChanged: (CGFloat) -> Void
    let onEnded: (CGFloat, CGFloat, Bool) -> Void
    let onScrollViewFound: (UIScrollView) -> Void
    let onWindowDismiss: () -> Void

    func makeUIView(context: Context) -> AnchorView {
        let view = AnchorView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        view.onWindowChanged = { anchor, hasWindow in
            if hasWindow {
                context.coordinator.attachIfNeeded(from: anchor)
            } else {
                context.coordinator.onWindowDismiss()
            }
        }
        return view
    }

    func updateUIView(_ uiView: AnchorView, context: Context) {
        context.coordinator.isLocked = isLocked
        context.coordinator.onChanged = onChanged
        context.coordinator.onEnded = onEnded
        context.coordinator.onScrollViewFound = onScrollViewFound
        context.coordinator.onWindowDismiss = onWindowDismiss
        context.coordinator.attachIfNeeded(from: uiView)
    }

    static func dismantleUIView(_ uiView: AnchorView, coordinator: Coordinator) {
        coordinator.detach()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            isLocked: isLocked,
            onChanged: onChanged,
            onEnded: onEnded,
            onScrollViewFound: onScrollViewFound,
            onWindowDismiss: onWindowDismiss
        )
    }

    final class AnchorView: UIView {
        var onWindowChanged: ((AnchorView, Bool) -> Void)?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            onWindowChanged?(self, window != nil)
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var isLocked: Bool
        var onChanged: (CGFloat) -> Void
        var onEnded: (CGFloat, CGFloat, Bool) -> Void
        var onScrollViewFound: (UIScrollView) -> Void
        var onWindowDismiss: () -> Void

        weak var attachedScrollView: UIScrollView?
        private var panGesture: UIPanGestureRecognizer?

        init(
            isLocked: Bool,
            onChanged: @escaping (CGFloat) -> Void,
            onEnded: @escaping (CGFloat, CGFloat, Bool) -> Void,
            onScrollViewFound: @escaping (UIScrollView) -> Void,
            onWindowDismiss: @escaping () -> Void
        ) {
            self.isLocked = isLocked
            self.onChanged = onChanged
            self.onEnded = onEnded
            self.onScrollViewFound = onScrollViewFound
            self.onWindowDismiss = onWindowDismiss
        }

        func attachIfNeeded(from view: UIView) {
            guard let sv = Self.findVerticalScrollView(from: view) else { return }
            if attachedScrollView !== sv {
                detach()
                let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
                pan.maximumNumberOfTouches = 1
                pan.cancelsTouchesInView = true
                pan.delegate = self
                sv.addGestureRecognizer(pan)
                panGesture = pan
                attachedScrollView = sv
                onScrollViewFound(sv)
            }
        }

        func detach() {
            if let pan = panGesture, let owner = pan.view {
                owner.removeGestureRecognizer(pan)
            }
            panGesture = nil
            attachedScrollView = nil
        }

        @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
            guard let view = gesture.view else { return }
            let tx = gesture.translation(in: view).x
            switch gesture.state {
            case .began:
                if let sv = attachedScrollView {
                    sv.panGestureRecognizer.isEnabled = false
                    sv.panGestureRecognizer.isEnabled = true
                }
                onChanged(tx)
            case .changed:
                onChanged(tx)
            case .ended:
                onEnded(tx, gesture.velocity(in: view).x, true)
            case .cancelled, .failed:
                onEnded(tx, 0, false)
            default:
                break
            }
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard !isLocked else { return false }
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer,
                  let view = pan.view,
                  view.window != nil else { return false }
            if let sv = attachedScrollView, sv.isDragging {
                let svTy = abs(sv.panGestureRecognizer.translation(in: sv).y)
                if svTy > 8 {
                    return false
                }
            }
            let velocity = pan.velocity(in: view)
            let absX = abs(velocity.x)
            let absY = abs(velocity.y)
            guard absX > 10, absX > absY * 1.15 else {
                return false
            }
            if let hit = view.hitTest(pan.location(in: view), with: nil),
               Self.isInsideHorizontalScrollView(hit, root: view) {
                return false
            }
            return true
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            false
        }

        private static func findVerticalScrollView(from view: UIView) -> UIScrollView? {
            var cursor = view.superview
            while let current = cursor {
                if let sv = current as? UIScrollView,
                   !sv.alwaysBounceHorizontal,
                   sv.contentSize.width <= sv.bounds.width + 2 {
                    return sv
                }
                cursor = current.superview
            }
            return nil
        }

        private static func isInsideHorizontalScrollView(_ hitView: UIView, root: UIView) -> Bool {
            var cursor: UIView? = hitView
            while let current = cursor, current !== root {
                if let sv = current as? UIScrollView,
                   sv.alwaysBounceHorizontal || sv.contentSize.width > sv.bounds.width + 2 {
                    return true
                }
                cursor = current.superview
            }
            return false
        }
    }
}
