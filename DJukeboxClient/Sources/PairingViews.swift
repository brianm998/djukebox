import SwiftUI
import DJukeboxCommon

// Number pad on iOS; no-op on macOS (which has no software keyboard).
private extension View {
    @ViewBuilder func numericKeyboard() -> some View {
#if os(iOS)
        self.keyboardType(.numberPad)
#else
        self
#endif
    }
}

// Group six digits as "NNN NNN" for display.
func groupedPairingCode(_ digits: String) -> String {
    let only = String(digits.filter(\.isNumber).prefix(6))
    if only.count > 3 {
        let i = only.index(only.startIndex, offsetBy: 3)
        return only[..<i] + " " + only[i...]
    }
    return only
}

// MARK: - new-device entry screen

/*
 Shown on the unpaired device. It announces the pairing request automatically
 (PairingClient.start() was called by the ServerBrowser), waits for someone to
 approve, then collects the 6-digit code the user reads off the trusted device.
 */
public struct PairingEntryView: View {
    @ObservedObject private var pairing: PairingClient
    @State private var code: String = ""

    public init(_ pairing: PairingClient) { self.pairing = pairing }

    public var body: some View {
        VStack {
            Spacer()

            VStack(spacing: 16) {
                Text("🔗").font(.system(size: 52))

                Text("Pair this device")
                    .font(.title).bold()
                    .foregroundStyle(DJTheme.textPrimary)

                Text(statusMessage)
                    .font(.body)
                    .foregroundStyle(DJTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 420)

                switch pairing.phase {
                case .requesting, .waiting, .submitting:
                    ProgressView().padding(.top, 4)

                case .readyForCode:
                    codeEntry

                case .denied:
                    Button("Try Again") { restart() }
                        .buttonStyle(.borderedProminent).tint(DJTheme.neonViolet)

                case .paired:
                    Text("✅").font(.system(size: 40))

                case .failed:
                    Button("Try Again") { restart() }
                        .buttonStyle(.borderedProminent).tint(DJTheme.neonViolet)
                }

                if let note = pairing.note {
                    Text(note)
                        .font(.footnote)
                        .foregroundStyle(DJTheme.neonMagenta)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 420)
                }
            }
            .padding(28)
            .frame(maxWidth: 460)
            .djCard(padding: 4)

            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var codeEntry: some View {
        VStack(spacing: 12) {
            TextField("000 000", text: $code)
                .numericKeyboard()
                .multilineTextAlignment(.center)
                .font(.system(size: 32, weight: .semibold, design: .monospaced))
                .foregroundStyle(DJTheme.neonCyan)
                .frame(maxWidth: 220)
                .textFieldStyle(.plain)
                .djField()
                .onChange(of: code) { newValue in
                    code = groupedPairingCode(newValue)
                }

            Button("Pair") { pairing.submit(code: code) }
                .buttonStyle(.borderedProminent).tint(DJTheme.neonViolet)
                .disabled(code.filter(\.isNumber).count != 6)
        }
    }

    private func restart() {
        code = ""
        pairing.retry()
    }

    private var statusMessage: String {
        switch pairing.phase {
        case .requesting:   return "Contacting the DJukebox server…"
        case .waiting:      return "Waiting for someone to allow this device on another, already-paired DJukebox client."
        case .readyForCode: return "Enter the 6-digit code shown on your other device."
        case .submitting:   return "Pairing…"
        case .denied:       return "The pairing request was declined."
        case .paired:       return "Paired!"
        case .failed(let message): return message
        }
    }
}

// MARK: - approver side

/*
 Wraps the connected UI on an already-trusted client. Owns a PairingMonitor that
 polls for incoming pair requests and presents an approval sheet when one arrives.
 Drop it around the real content on each client.
 */
public struct PairingApprovalHost<Content: View>: View {
    @StateObject private var monitor: PairingMonitor
    private let content: Content

    public init(server: ServerType, @ViewBuilder content: () -> Content) {
        _monitor = StateObject(wrappedValue: PairingMonitor(server: server))
        self.content = content()
    }

    public var body: some View {
        content
          .sheet(isPresented: shouldPresent) {
              PairingApprovalView(monitor: monitor)
          }
          .onAppear { monitor.start() }
          .onDisappear { monitor.stop() }
    }

    private var shouldPresent: Binding<Bool> {
        Binding(
          get: { monitor.activeCode != nil || !monitor.pending.isEmpty },
          set: { presented in if !presented { monitor.clearCode() } }
        )
    }
}

/*
 The approval sheet. Either asks the user to allow/deny an incoming request, or —
 once allowed — shows the 6-digit code to read out to the new device.
 */
public struct PairingApprovalView: View {
    @ObservedObject var monitor: PairingMonitor

    public init(monitor: PairingMonitor) { self.monitor = monitor }

    public var body: some View {
        VStack(spacing: 20) {
            if let active = monitor.activeCode {
                Text("🔗").font(.system(size: 48))
                Text("Pairing “\(active.name)”")
                    .font(.title2).bold()
                    .foregroundStyle(DJTheme.textPrimary)
                    .multilineTextAlignment(.center)
                Text("Enter this code on the new device:")
                    .foregroundStyle(DJTheme.textSecondary)
                Text(groupedPairingCode(active.code))
                    .font(.system(size: 44, weight: .bold, design: .monospaced))
                    .foregroundStyle(DJTheme.neonCyan)
                    .padding(.vertical, 8)
                Button("Done") { monitor.clearCode() }
                    .buttonStyle(.borderedProminent).tint(DJTheme.neonViolet)
            } else if let request = monitor.pending.first {
                Text("🔗").font(.system(size: 48))
                Text("“\(request.name)” wants to pair")
                    .font(.title2).bold()
                    .foregroundStyle(DJTheme.textPrimary)
                    .multilineTextAlignment(.center)
                Text("Allow this device to control your DJukebox?")
                    .foregroundStyle(DJTheme.textSecondary)
                    .multilineTextAlignment(.center)
                HStack(spacing: 16) {
                    Button("Deny") { monitor.deny(request) }
                        .buttonStyle(.bordered).tint(DJTheme.neonMagenta)
                    Button("Allow") { monitor.approve(request) }
                        .buttonStyle(.borderedProminent).tint(DJTheme.neonViolet)
                        .keyboardShortcut(.defaultAction)
                }
                Button("Not now") { monitor.ignore(request) }
                    .font(.footnote)
            } else {
                // nothing pending (the sheet is dismissing)
                EmptyView()
            }
        }
        .padding(28)
        .frame(minWidth: 320)
        .background(DJTheme.screenGradient)
        .preferredColorScheme(.dark)
    }
}
