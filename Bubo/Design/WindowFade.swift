import AppKit

/// Bubo's windows coming and going in a fade of `Motion.windowFade`, or at once with Riduci movimento.
extension NSWindow {
    /// Orders the window in front of the others without activating Bubo, fading it in if it was not on screen.
    func orderFrontFading(reducesMotion: Bool = Motion.isReduced) {
        let wasVisible = isVisible
        WindowFade.generation[ObjectIdentifier(self), default: 0] += 1
        if !wasVisible, !reducesMotion { alphaValue = 0 }
        orderFrontRegardless()
        fade(to: 1, reducesMotion: reducesMotion || wasVisible && alphaValue == 1)
    }

    /// Makes the window key and orders it in front, fading it in if it was not on screen.
    func makeKeyAndOrderFrontFading(reducesMotion: Bool = Motion.isReduced) {
        let wasVisible = isVisible
        WindowFade.generation[ObjectIdentifier(self), default: 0] += 1
        if !wasVisible, !reducesMotion { alphaValue = 0 }
        makeKeyAndOrderFront(nil)
        fade(to: 1, reducesMotion: reducesMotion || wasVisible && alphaValue == 1)
    }

    /// Fades the window out, then orders it out and calls `completion`; a fade in started meanwhile keeps it on screen
    /// and skips `completion`.
    func orderOutFading(reducesMotion: Bool = Motion.isReduced, completion: @escaping @MainActor () -> Void = {}) {
        let id = ObjectIdentifier(self)
        WindowFade.generation[id, default: 0] += 1
        let generation = WindowFade.generation[id]
        guard isVisible, !reducesMotion else {
            orderOut(nil)
            alphaValue = 1
            completion()
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Motion.windowFade
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            animator().alphaValue = 0
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                // Shown again while fading: the newer call wins.
                guard let self, WindowFade.generation[id] == generation else { return }
                self.orderOut(nil)
                self.alphaValue = 1
                completion()
            }
        }
    }

    private func fade(to alpha: CGFloat, reducesMotion: Bool) {
        guard !reducesMotion else {
            alphaValue = alpha
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Motion.windowFade
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().alphaValue = alpha
        }
    }
}

/// The fades under way, so a fade out that ends after a newer fade in does not order the window out.
private enum WindowFade {
    // ponytail: never pruned; a handful of windows per run.
    static var generation: [ObjectIdentifier: Int] = [:]
}
