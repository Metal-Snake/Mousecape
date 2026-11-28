import AppKit
import SwiftUI

extension View {
    /// Closes the sheet when the user clicks the window it is attached to, as a popover
    /// would. Only use it where closing loses nothing: pass false while the sheet holds
    /// changes, and the click does nothing (macOS's beep), as it does without this.
    func dismissesOnOutsideClick(_ isEnabled: Bool = true) -> some View {
        modifier(OutsideClickDismissal(isEnabled: isEnabled))
    }
}

private struct OutsideClickDismissal: ViewModifier {
    let isEnabled: Bool
    @Environment(\.dismiss) private var dismiss

    func body(content: Content) -> some View {
        content.background(OutsideClickHook(isEnabled: isEnabled) { dismiss() })
    }
}

/// An invisible view in the sheet that watches the app's mouse clicks while it is in a
/// window. A sheet blocks clicks on its parent window; the monitor sees them first.
private struct OutsideClickHook: NSViewRepresentable {
    let isEnabled: Bool
    let onOutsideClick: () -> Void

    func makeNSView(context: Context) -> HookView { HookView() }

    func updateNSView(_ view: HookView, context: Context) {
        view.isEnabled = isEnabled
        view.onOutsideClick = onOutsideClick
    }

    final class HookView: NSView {
        var isEnabled = true
        var onOutsideClick: () -> Void = {}
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window != nil { startMonitoring() } else { stopMonitoring() }
        }

        private func startMonitoring() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
                guard let self, self.isOutsideClick(event) else { return event }
                self.onOutsideClick()
                return nil     // the parent window would only beep
            }
        }

        private func stopMonitoring() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }

        /// A click in the content of the window this sheet is attached to. Not when a
        /// dialog sits on the sheet (the click belongs to that), and not in the title bar
        /// or toolbar, where a drag moves the window with its sheet.
        private func isOutsideClick(_ event: NSEvent) -> Bool {
            guard isEnabled,
                  let sheet = window, sheet.isSheet, sheet.attachedSheet == nil,
                  let parent = sheet.sheetParent, event.window === parent,
                  parent.attachedSheet === sheet
            else { return false }
            return parent.contentLayoutRect.contains(event.locationInWindow)
        }
    }
}
