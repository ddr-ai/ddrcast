import SwiftUI

/// Native iPhone/iPad keyboard. Roku accepts ECP `Lit_` keypresses.
/// Chromecast Default Media Receiver does not.
struct CastKeyboardView: View {
    @EnvironmentObject var cast: CastService
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var showBlocked = false
    @State private var sending = false
    @State private var sentOK = false
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                if cast.supportsRemoteKeyboard {
                    Text("Typing here sends characters to \(cast.connection.deviceName ?? "the Roku") over the local network (ECP).")
                        .font(.callout)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.cyan.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                } else {
                    Text(limitation)
                        .font(.callout)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.orange.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                TextField("Type here with the iPhone keyboard", text: $text, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .focused($focused)
                    .lineLimit(3...6)

                Button {
                    focused = false
                    Task { await send() }
                } label: {
                    if sending {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Label(
                            cast.supportsRemoteKeyboard ? "Send to Roku" : "Send to Chromecast",
                            systemImage: "paperplane"
                        )
                        .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.cyan)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || sending)

                if sentOK {
                    Text("Sent.")
                        .font(.caption)
                        .foregroundStyle(.cyan)
                }

                Spacer()
            }
            .padding()
            .navigationTitle("Remote keyboard")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .onAppear { focused = true }
            .alert("Cannot send text", isPresented: $showBlocked) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(limitation)
            }
        }
        .preferredColorScheme(.dark)
    }

    private var limitation: String {
        let name = cast.connection.deviceName ?? "this Chromecast"
        return """
        \(name) is running Google’s Default Media Receiver, which has no text field and does not accept keyboard input from a Cast sender. \
        Connect to a Roku to type with the iPhone keyboard.
        """
    }

    private func send() async {
        let payload = text
        guard !payload.isEmpty else { return }
        if !cast.supportsRemoteKeyboard {
            showBlocked = true
            return
        }
        sending = true
        let ok = await cast.sendRemoteText(payload)
        sending = false
        sentOK = ok
        if ok { text = "" }
    }
}
