import AppKit
import SwiftUI

class SetupWindow: NSWindow {
    private let setupState = SetupState()

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 400, height: 280),
                   styleMask: [.titled, .closable],
                   backing: .buffered, defer: false)
        title = "Voice2Text Setup"
        isReleasedWhenClosed = false
        center()

        let view = NSHostingView(rootView: SetupView(state: setupState))
        contentView = view
    }

    var state: SetupState { setupState }
}

class SetupState: ObservableObject {
    @Published var step: SetupStep = .accessibility
    @Published var progress: String = ""
}

enum SetupStep {
    case accessibility, microphone, downloadingWhisper, downloadingLLM, warmingUp, done
}

struct SetupView: View {
    @ObservedObject var state: SetupState

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "mic.fill")
                .font(.system(size: 48))
                .foregroundColor(.blue)

            Text("Voice2Text")
                .font(.title.bold())

            VStack(spacing: 8) {
                stepRow("Accessibility Permission", done: isPast(.accessibility), active: state.step == .accessibility)
                stepRow("Microphone Permission", done: isPast(.microphone), active: state.step == .microphone)
                stepRow("Downloading Whisper model (~1.5 GB)", done: isPast(.downloadingWhisper), active: state.step == .downloadingWhisper)
                stepRow("Downloading LLM model (~1 GB)", done: isPast(.downloadingLLM), active: state.step == .downloadingLLM)
                stepRow("Warming up…", done: state.step == .done, active: state.step == .warmingUp)
            }

            if state.step != .done {
                ProgressView()
                    .scaleEffect(0.8)
                if !state.progress.isEmpty {
                    Text(state.progress)
                        .font(.caption)
                        .foregroundColor(.orange)
                        .multilineTextAlignment(.center)
                }
            } else {
                Text("Ready! Use Right ⌘ to record.")
                    .foregroundColor(.secondary)
            }
        }
        .padding(30)
        .frame(width: 400, height: 280)
    }

    private func stepRow(_ text: String, done: Bool, active: Bool = false) -> some View {
        HStack {
            if done {
                Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
            } else if active {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: "circle").foregroundColor(.secondary)
            }
            Text(text)
                .foregroundColor(active ? .primary : (done ? .secondary : .secondary))
            Spacer()
        }
    }

    private func isPast(_ step: SetupStep) -> Bool {
        let order: [SetupStep] = [.accessibility, .microphone, .downloadingWhisper, .downloadingLLM, .warmingUp, .done]
        guard let current = order.firstIndex(of: state.step),
              let target = order.firstIndex(of: step) else { return false }
        return current > target
    }
}
