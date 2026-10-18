import AppKit
import SwiftUI

extension View {
    /// SwiftUI sheets on macOS have a fixed size. This lets the user resize the sheet's
    /// window, down to the given minimum, and reopens it at the last size used under
    /// `sizeKey`. The view's frame should allow growing (`maxWidth`/`maxHeight: .infinity`).
    func resizableSheet(minWidth: CGFloat, minHeight: CGFloat, sizeKey: String) -> some View {
        background(SheetWindowHook(minSize: CGSize(width: minWidth, height: minHeight), sizeKey: sizeKey))
    }
}

/// An invisible view that reaches the sheet's NSWindow once it is in one.
private struct SheetWindowHook: NSViewRepresentable {
    let minSize: CGSize
    let sizeKey: String

    func makeNSView(context: Context) -> HookView { HookView(minSize: minSize, sizeKey: sizeKey) }
    func updateNSView(_ view: HookView, context: Context) {}

    final class HookView: NSView {
        let minSize: CGSize
        let defaultsKey: String
        private var observing = false

        init(minSize: CGSize, sizeKey: String) {
            self.minSize = minSize
            self.defaultsKey = "sheetSize." + sizeKey
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard window != nil else { return }
            makeResizable()
            // SwiftUI configures the sheet window while presenting it, after this view
            // joined it; set things again once that is done.
            DispatchQueue.main.async { [weak self] in
                self?.makeResizable()
                self?.restoreSize()
                self?.observeResizing()
            }
        }

        private func makeResizable() {
            guard let window else { return }
            window.styleMask.insert(.resizable)
            window.contentMinSize = minSize
            window.contentMaxSize = CGSize(width: 10_000, height: 10_000)
        }

        private func restoreSize() {
            guard let window, let saved = UserDefaults.standard.string(forKey: defaultsKey) else { return }
            let size = NSSizeFromString(saved)
            guard size.width >= minSize.width, size.height >= minSize.height else { return }
            // Never larger than the screen the sheet is on.
            let visible = window.screen?.visibleFrame.size ?? size
            window.setContentSize(CGSize(width: min(size.width, visible.width),
                                         height: min(size.height, visible.height)))
        }

        /// Selector-based, so the observation ends by itself when this view goes away.
        private func observeResizing() {
            guard let window, !observing else { return }
            observing = true
            NotificationCenter.default.addObserver(self, selector: #selector(didEndResize(_:)),
                                                   name: NSWindow.didEndLiveResizeNotification, object: window)
        }

        @objc private func didEndResize(_ notification: Notification) {
            guard let window = notification.object as? NSWindow else { return }
            let size = window.contentRect(forFrameRect: window.frame).size
            UserDefaults.standard.set(NSStringFromSize(size), forKey: defaultsKey)
        }
    }
}
