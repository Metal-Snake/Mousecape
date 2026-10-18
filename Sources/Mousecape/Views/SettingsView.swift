import SwiftUI

struct SettingsView: View {
    @Bindable var model: AppModel

    @State private var scale = EnginePreferences.cursorScale ?? Engine.scale
    @State private var leftHanded = EnginePreferences.leftHanded

    var body: some View {
        Form {
            Section {
                Toggle("Apply cape at login", isOn: agentBinding)
                if model.loginAgent.needsApproval {
                    HStack {
                        Text("Allow Mousecape in Login Items to finish turning this on.")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Open Settings") { model.loginAgent.openLoginItemsSettings() }
                    }
                }
                if let error = model.loginAgent.lastError {
                    Text(error)
                        .foregroundStyle(.red)
                }
            } footer: {
                Text("macOS forgets custom cursors when you log out. A small background agent applies your cape again at login and when displays change.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Section {
                LabeledContent("Cursor size") {
                    HStack {
                        Slider(value: $scale, in: 1...4, step: 0.25)
                        Text(scale, format: .number.precision(.fractionLength(2)))
                            .monospacedDigit()
                            .frame(width: 40, alignment: .trailing)
                    }
                }
                Toggle("Left-handed (mirror pointers)", isOn: $leftHanded)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
        .onChange(of: scale) { _, newValue in
            Engine.scale = newValue
            EnginePreferences.cursorScale = newValue
        }
        .onChange(of: leftHanded) { _, newValue in
            EnginePreferences.leftHanded = newValue
            model.library.reapply()
        }
        .onAppear { model.loginAgent.refresh() }
    }

    private var agentBinding: Binding<Bool> {
        Binding(get: { model.loginAgent.isEnabled || model.loginAgent.needsApproval },
                set: { model.loginAgent.setEnabled($0) })
    }
}
