import SwiftUI

/// Native iPhone/iPad keyboard UI for Cast remote text.
/// The Default Media Receiver has no text-input namespace, so this view
/// does not send keystrokes and does not emulate the on-TV letter picker.
struct CastKeyboardView: View {
    @EnvironmentObject var cast: CastService
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var showBlocked = false
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text(limitation)
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.orange.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                TextField("Type here with the iPhone keyboard", text: $text, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .focused($focused)
                    .lineLimit(3...6)

                Button {
                    focused = false
                    showBlocked = true
                } label: {
                    Label("Send to Chromecast", systemImage: "paperplane")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.cyan)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Text("Send is refused on purpose: this receiver cannot take the text. No workaround is implemented.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

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
        ddrcast will not fake the on-TV letter-by-letter keyboard.
        """
    }
}
