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

    final class HookView: NSView, NSWindowDelegate {
        let minSize: CGSize
        let defaultsKey: String

        init(minSize: CGSize, sizeKey: String) {
            self.minSize = minSize
            self.defaultsKey = "sheetSize." + sizeKey
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { nil }

        /// Observations are selector-based, so they end by themselves when this view goes away.
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            makeResizable()
            // SwiftUI sizes the window to the content (twice) before the sheet is shown,
            // the width always to the minimum. Setting the saved size after each of these,
            // while the window is still hidden, opens the sheet at that size right away.
            NotificationCenter.default.addObserver(self, selector: #selector(didResize(_:)),
                                                   name: NSWindow.didResizeNotification, object: window)
            NotificationCenter.default.addObserver(self, selector: #selector(didEndResize(_:)),
                                                   name: NSWindow.didEndLiveResizeNotification, object: window)
            // SwiftUI configures the sheet window while presenting it, after this view
            // joined it; set things again once that is done.
            DispatchQueue.main.async { [weak self] in self?.makeResizable() }
        }

        private func makeResizable() {
            guard let window else { return }
            window.styleMask.insert(.resizable)
            window.contentMinSize = minSize
            window.contentMaxSize = CGSize(width: 10_000, height: 10_000)
            // SwiftUI sets the sheet window's minimum back to zero as the content lays
            // out, so the sheet could be dragged down to nothing. It gives the window no
            // delegate; this view becomes it and keeps the minimum itself.
            if window.delegate == nil { window.delegate = self }
        }

        func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
            let smallest = sender.frameRect(forContentRect: CGRect(origin: .zero, size: minSize)).size
            return NSSize(width: max(frameSize.width, smallest.width),
                          height: max(frameSize.height, smallest.height))
        }

        /// The size last used, if it is at least the minimum; never larger than the screen.
        private var savedSize: CGSize? {
            guard let saved = UserDefaults.standard.string(forKey: defaultsKey) else { return nil }
            let size = NSSizeFromString(saved)
            guard size.width >= minSize.width, size.height >= minSize.height else { return nil }
            let visible = (window?.screen ?? NSScreen.main)?.visibleFrame.size ?? size
            return CGSize(width: min(size.width, visible.width), height: min(size.height, visible.height))
        }

        @objc private func didResize(_ notification: Notification) {
            guard let window, !window.isVisible, let size = savedSize,
                  window.contentRect(forFrameRect: window.frame).size != size
            else { return }
            window.setContentSize(size)
        }

        @objc private func didEndResize(_ notification: Notification) {
            guard let window = notification.object as? NSWindow else { return }
            let size = window.contentRect(forFrameRect: window.frame).size
            UserDefaults.standard.set(NSStringFromSize(size), forKey: defaultsKey)
        }
    }
}
