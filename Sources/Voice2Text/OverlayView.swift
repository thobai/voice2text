import SwiftUI

enum AppState: Equatable {
    case idle, downloading, recording, transcribing, processing, done
    case error(String)
}

class OverlayState: ObservableObject {
    @Published var appState: AppState = .idle
}

struct OverlayView: View {
    @ObservedObject var state: OverlayState

    var body: some View {
        ZStack {
            if state.appState != .idle {
                RoundedRectangle(cornerRadius: 14)
                    .fill(.ultraThinMaterial)

                HStack(spacing: 10) {
                    switch state.appState {
                    case .idle:
                        EmptyView()
                    case .downloading:
                        ProgressView().controlSize(.small)
                        Text("Downloading…")
                    case .recording:
                        Circle().fill(.red).frame(width: 10, height: 10)
                        Text("Recording…")
                    case .transcribing:
                        ProgressView().controlSize(.small)
                        Text("Transcribing…")
                    case .processing:
                        ProgressView().controlSize(.small)
                        Text("Processing…")
                    case .done:
                        Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                        Text("Copied!")
                    case .error(let msg):
                        Image(systemName: "xmark.circle.fill").foregroundColor(.red)
                        Text(msg).lineLimit(1)
                    }
                }
                .font(.system(size: 14, weight: .medium))
            }
        }
    }
}
