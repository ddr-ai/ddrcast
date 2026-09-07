import GoogleCast
import SwiftUI

struct CastSheet: View {
    @EnvironmentObject var cast: CastService
    @EnvironmentObject var browser: BrowserModel
    @Environment(\.dismiss) private var dismiss
    @State private var showKeyboard = false

    var body: some View {
        NavigationStack {
            List {
                connectionSection
                devicesSection
                mediaSection
                if cast.connection.isConnected {
                    keyboardSection
                    disconnectSection
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color(red: 0.043, green: 0.071, blue: 0.125))
            .navigationTitle("Cast")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showKeyboard) {
                CastKeyboardView()
                    .environmentObject(cast)
            }
            .onAppear { cast.startDiscovery() }
        }
        .preferredColorScheme(.dark)
    }

    private var connectionSection: some View {
        Section("Status") {
            HStack {
                statusDot
                VStack(alignment: .leading, spacing: 4) {
                    Text(cast.statusText)
                    if cast.isDiscovering {
                        Text("Scanning the local network for Chromecast devices.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var statusDot: some View {
        Circle()
            .fill(color(for: cast.connection))
            .frame(width: 10, height: 10)
    }

    private func color(for state: CastConnectionState) -> Color {
        switch state {
        case .connected: return .green
        case .connecting: return .yellow
        case .failed: return .red
        case .disconnecting: return .orange
        case .idle: return .gray
        }
    }

    private var devicesSection: some View {
        Section("Chromecast devices") {
            if cast.devices.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("No devices found yet.")
                    Text("Keep this iPhone or iPad on the same Wi-Fi as the Chromecast, then allow Local Network access when iOS asks.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Scan again") { cast.startDiscovery() }
                }
            } else {
                ForEach(cast.devices, id: \.uniqueID) { device in
                    Button {
                        cast.connect(to: device)
                    } label: {
                        HStack {
                            Image(systemName: "tv")
                            VStack(alignment: .leading) {
                                Text(device.friendlyName)
                                    .foregroundStyle(.primary)
                                Text(device.modelName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if cast.connection.deviceName == device.friendlyName, cast.connection.isConnected {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Color.cyan)
                            }
                        }
                    }
                }
            }
        }
    }

    private var mediaSection: some View {
        Section("Cast this page") {
            if let recommended = browser.recommended {
                Button {
                    cast.cast(recommended)
                } label: {
                    candidateRow(recommended)
                }
            }
            ForEach(browser.candidates.filter { !$0.recommended }) { item in
                Button {
                    cast.cast(item)
                } label: {
                    candidateRow(item)
                }
            }
            if browser.candidates.isEmpty {
                Text(browser.pageBlockReason ?? "No castable video on this page.")
                    .font(.callout)
                    .foregroundStyle(.primary)
            }
            if !browser.videos.isEmpty && browser.candidates.isEmpty {
                Text("Detected \(browser.videos.count) video element(s), none with a direct media URL.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func candidateRow(_ item: CastCandidate) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(item.title)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Spacer()
                if item.recommended {
                    Text("Recommended")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.cyan.opacity(0.2))
                        .foregroundStyle(Color.cyan)
                        .clipShape(Capsule())
                }
            }
            Text(item.sourceLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(item.url.absoluteString)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }

    private var keyboardSection: some View {
        Section("Keyboard") {
            Button {
                showKeyboard = true
            } label: {
                Label("Type with iPhone keyboard", systemImage: "keyboard")
            }
            Text("The Default Media Receiver cannot accept remote text. Opening the keyboard will explain this instead of faking TV key events.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var disconnectSection: some View {
        Section {
            Button(role: .destructive) {
                cast.disconnect()
                dismiss()
            } label: {
                Label("Disconnect and return to browsing", systemImage: "tv.slash")
            }
        }
    }
}
