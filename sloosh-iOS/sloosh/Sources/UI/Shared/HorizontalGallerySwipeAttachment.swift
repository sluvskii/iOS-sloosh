import SwiftUI
import UIKit
import QuartzCore

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
    /// so it fills from screen top down even when the outgoing page is at scroll offset 0.
    func topBleed(isActive: Bool, savedY: CGFloat, extraTopMargin: CGFloat) -> CGFloat {
        guard !isActive, savedY > 0 else { return 0 }
        return min(savedY, topInset + extraTopMargin)
    }
}

private final class DisplayLinkProxy: NSObject {
    private weak var owner: AnyObject?
    private let callback: (AnyObject, CADisplayLink) -> Void

    init<T: AnyObject>(owner: T, callback: @escaping (T, CADisplayLink) -> Void) {
        self.owner = owner
        self.callback = { obj, link in
            if let typed = obj as? T {
                callback(typed, link)
            }
        }
        super.init()
    }

    @objc func tick(_ link: CADisplayLink) {
        guard let owner else {
            link.invalidate()
            return
        }
        callback(owner, link)
    }
}

/// Shared 120Hz CADisplayLink spring driver and unblockable swipe state machine for horizontal
/// category paging inside a single native vertical ScrollView.
@MainActor
final class HorizontalGallerySwipeController<Category: Hashable>: ObservableObject {
    @Published var dragOffset: CGFloat = 0
    @Published var slideDirection: Int = 0
    @Published var overridePreviewCategory: Category? = nil

    weak var attachedScrollView: UIScrollView? = nil

    static var pageGap: CGFloat { 16 }

    nonisolated(unsafe) private var displayLink: CADisplayLink?
    private var displayLinkProxy: DisplayLinkProxy?
    private var springTargetOffset: CGFloat = 0
    private var springVelocity: CGFloat = 0
    private var springStartTime: CFTimeInterval = 0
    private var springCompletion: (() -> Void)?
    private var springGeneration: Int = 0
    private var dragBaseOffset: CGFloat = 0

    deinit {
        displayLink?.invalidate()
    }

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

    func handlePanBegan(
        _ translationX: CGFloat,
        current: Category,
        in all: [Category],
        pageWidth: CGFloat,
        preloadIfNeeded: ((Category?) -> Void)? = nil,
        onPreviewCandidate: ((Category?, CGFloat) -> Void)? = nil
    ) {
        if let completion = springCompletion,
           springTargetOffset != 0,
           abs(dragOffset - springTargetOffset) < 2 {
            stopSpringOnly()
            completion()
        } else {
            stopSpringOnly()
        }
        dragBaseOffset = dragOffset
        updateDrag(
            totalX: dragBaseOffset + translationX,
            current: current,
            in: all,
            pageWidth: pageWidth,
            preloadIfNeeded: preloadIfNeeded,
            onPreviewCandidate: onPreviewCandidate
        )
    }

    func handlePanChanged(
        _ translationX: CGFloat,
        current: Category,
        in all: [Category],
        pageWidth: CGFloat,
        preloadIfNeeded: ((Category?) -> Void)? = nil,
        onPreviewCandidate: ((Category?, CGFloat) -> Void)? = nil
    ) {
        updateDrag(
            totalX: dragBaseOffset + translationX,
            current: current,
            in: all,
            pageWidth: pageWidth,
            preloadIfNeeded: preloadIfNeeded,
            onPreviewCandidate: onPreviewCandidate
        )
    }

    private func updateDrag(
        totalX: CGFloat,
        current: Category,
        in all: [Category],
        pageWidth: CGFloat,
        preloadIfNeeded: ((Category?) -> Void)?,
        onPreviewCandidate: ((Category?, CGFloat) -> Void)?
    ) {
        if overridePreviewCategory == nil {
            if totalX < -2 {
                slideDirection = 1
                preloadIfNeeded?(relativeCategory(from: current, in: all, step: 1))
            } else if totalX > 2 {
                slideDirection = -1
                preloadIfNeeded?(relativeCategory(from: current, in: all, step: -1))
            }
        }
        dragOffset = totalX

        let candidate: Category?
        if let override = overridePreviewCategory {
            candidate = abs(totalX) > pageWidth * 0.42 ? override : nil
        } else {
            let rawCandidate = totalX < 0
                ? relativeCategory(from: current, in: all, step: 1)
                : relativeCategory(from: current, in: all, step: -1)
            candidate = abs(totalX) > pageWidth * 0.42 ? rawCandidate : nil
        }
        onPreviewCandidate?(candidate, totalX)
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
        let totalX = dragBaseOffset + translationX
        dragBaseOffset = 0

        guard didFinish else {
            cancelSwipe(velocityX: 0, onPrepareHeader: onPrepareCancelHeader)
            return
        }

        let stepStride = pageWidth + Self.pageGap
        let threshold = pageWidth * 0.25
        let projectedX = totalX + velocityX * 0.14

        if let override = overridePreviewCategory {
            let isForward = slideDirection > 0
            let signMatches = isForward ? (projectedX < -threshold || velocityX < -320) : (projectedX > threshold || velocityX > 320)
            if signMatches {
                commitSwitch(
                    metrics: metrics,
                    outgoingCategory: current,
                    targetCategory: override,
                    finalOffset: isForward ? -stepStride : stepStride,
                    velocityX: velocityX,
                    onPrepareHeader: { onPrepareCommitHeader?(override) },
                    isStillCurrent: isStillCurrent,
                    onCommitState: { onCommitState(override) }
                )
            } else {
                cancelSwipe(velocityX: velocityX, onPrepareHeader: onPrepareCancelHeader)
            }
            return
        }

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
        stopSpringOnly()
        dragBaseOffset = 0

        if target == current && dragOffset == 0 {
            metrics.savedScrollOffsets[target] = 0
            scrollToTop()
            return
        }
        guard target != current,
              let currentIndex = all.firstIndex(of: current),
              let targetIndex = all.firstIndex(of: target) else {
            cancelSwipe(velocityX: 0)
            return
        }
        let isForward = targetIndex > currentIndex
        let newDirection = isForward ? 1 : -1
        if slideDirection != newDirection {
            dragOffset = 0
        }
        overridePreviewCategory = target
        slideDirection = newDirection
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
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        onPrepareHeader?()

        startSpring(to: finalOffset, initialVelocity: velocityX) { [weak self] in
            guard let self else { return }
            let outgoingTop = metrics.topOffset
            metrics.savedScrollOffsets[outgoingCategory] = outgoingTop
            let targetY = metrics.savedScrollOffsets[targetCategory] ?? 0

            if abs(targetY - outgoingTop) > 0.5, let sv = self.attachedScrollView {
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

            if abs(targetY - outgoingTop) > 0.5, targetY > 0, let sv = self.attachedScrollView {
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
    }

    func cancelSwipe(velocityX: CGFloat = 0, onPrepareHeader: (() -> Void)? = nil) {
        onPrepareHeader?()
        startSpring(to: 0, initialVelocity: velocityX) { [weak self] in
            guard let self else { return }
            var tx = Transaction()
            tx.disablesAnimations = true
            withTransaction(tx) {
                self.dragOffset = 0
                self.slideDirection = 0
                self.overridePreviewCategory = nil
            }
        }
    }

    func resetImmediately(onResetHeader: (() -> Void)? = nil) {
        stopSpringOnly()
        dragBaseOffset = 0
        var tx = Transaction()
        tx.disablesAnimations = true
        withTransaction(tx) {
            dragOffset = 0
            slideDirection = 0
            overridePreviewCategory = nil
            onResetHeader?()
        }
    }

    private func stopSpringOnly() {
        springGeneration += 1
        displayLink?.invalidate()
        displayLink = nil
        displayLinkProxy = nil
        springCompletion = nil
    }

    private func startSpring(to target: CGFloat, initialVelocity: CGFloat, completion: @escaping () -> Void) {
        stopSpringOnly()

        if abs(dragOffset - target) < 0.35 && abs(initialVelocity) < 10 {
            dragOffset = target
            completion()
            return
        }

        springTargetOffset = target
        springVelocity = max(-2600, min(2600, initialVelocity))
        springStartTime = CACurrentMediaTime()
        springCompletion = completion

        let proxy = DisplayLinkProxy(owner: self) { controller, link in
            controller.stepSpring(link)
        }
        let link = CADisplayLink(target: proxy, selector: #selector(DisplayLinkProxy.tick(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 80, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        displayLinkProxy = proxy
        displayLink = link
    }

    private func stepSpring(_ link: CADisplayLink) {
        let elapsed = CACurrentMediaTime() - springStartTime
        let rawDt = link.targetTimestamp - link.timestamp
        let dt = CGFloat(min(1.0 / 30.0, max(1.0 / 240.0, rawDt > 0 ? rawDt : (1.0 / 60.0))))

        let stiffness: CGFloat = 210.0
        let damping: CGFloat = 24.5
        let subSteps = 2
        let subDt = dt / CGFloat(subSteps)

        var x = dragOffset
        var v = springVelocity
        for _ in 0..<subSteps {
            let disp = x - springTargetOffset
            let accel = -stiffness * disp - damping * v
            v += accel * subDt
            x += v * subDt
        }

        springVelocity = v

        if elapsed > 1.35 || (abs(x - springTargetOffset) < 0.35 && abs(v) < 12.0) {
            let done = springCompletion
            displayLink?.invalidate()
            displayLink = nil
            displayLinkProxy = nil
            dragOffset = springTargetOffset
            let generation = springGeneration
            DispatchQueue.main.async { [weak self] in
                guard let self, self.springGeneration == generation else { return }
                self.springCompletion = nil
                done?()
            }
        } else {
            dragOffset = x
        }
    }
}

/// Attaches a non-blocking horizontal pan gesture recognizer directly to the enclosing vertical
/// UIScrollView so horizontal swipes feel 1:1 and never deadlock vertical scrolling.
struct HorizontalGallerySwipeAttachment: UIViewRepresentable {
    let onBegan: (CGFloat) -> Void
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
        context.coordinator.onBegan = onBegan
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
            onBegan: onBegan,
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
        var onBegan: (CGFloat) -> Void
        var onChanged: (CGFloat) -> Void
        var onEnded: (CGFloat, CGFloat, Bool) -> Void
        var onScrollViewFound: (UIScrollView) -> Void
        var onWindowDismiss: () -> Void

        weak var attachedScrollView: UIScrollView?
        private var panGesture: UIPanGestureRecognizer?

        init(
            onBegan: @escaping (CGFloat) -> Void,
            onChanged: @escaping (CGFloat) -> Void,
            onEnded: @escaping (CGFloat, CGFloat, Bool) -> Void,
            onScrollViewFound: @escaping (UIScrollView) -> Void,
            onWindowDismiss: @escaping () -> Void
        ) {
            self.onBegan = onBegan
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
                    if sv.isDecelerating {
                        sv.setContentOffset(sv.contentOffset, animated: false)
                    }
                }
                onBegan(tx)
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
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer,
                  let view = pan.view,
                  view.window != nil else { return false }
            if let sv = attachedScrollView, sv.isDragging {
                let svTy = abs(sv.panGestureRecognizer.translation(in: sv).y)
                if svTy > 10 {
                    return false
                }
            }
            let velocity = pan.velocity(in: view)
            let absX = abs(velocity.x)
            let absY = abs(velocity.y)
            guard absX > 5, absX > absY * 1.1 else {
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
            guard let sv = attachedScrollView else { return false }
            return otherGestureRecognizer === sv.panGestureRecognizer
        }

        private static func findVerticalScrollView(from view: UIView) -> UIScrollView? {
            var cursor = view.superview
            while let current = cursor {
                if let sv = current as? UIScrollView,
                   !sv.alwaysBounceHorizontal,
                   (sv.bounds.width < 1 || sv.contentSize.width <= sv.bounds.width + 2) {
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
