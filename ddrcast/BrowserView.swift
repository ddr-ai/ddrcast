import SwiftUI

struct BrowserView: View {
    @EnvironmentObject var browser: BrowserModel
    @EnvironmentObject var cast: CastService
    @EnvironmentObject var updates: UpdateService
    @State private var showCastSheet = false
    @State private var showKeyboard = false
    @State private var showError = false
    @State private var errorText = ""

    var body: some View {
        VStack(spacing: 0) {
            BrowserToolbar(
                onCast: openCast,
                onKeyboard: { showKeyboard = true }
            )
            progressBar
            WebContainerView()
                .ignoresSafeArea(.container, edges: .bottom)
            if cast.connection.isConnected {
                NowPlayingBar(onOpenCast: openCast, onKeyboard: { showKeyboard = true })
            }
        }
        .background(Color(red: 0.043, green: 0.071, blue: 0.125).ignoresSafeArea())
        .sheet(isPresented: $showCastSheet) {
            CastSheet()
                .environmentObject(cast)
                .environmentObject(browser)
        }
        .sheet(isPresented: $showKeyboard) {
            CastKeyboardView()
                .environmentObject(cast)
        }
        .alert("Cast", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorText)
        }
        .onChange(of: cast.lastError) { _, new in
            if let new, !new.isEmpty {
                errorText = new
                showError = true
            }
        }
        .onChange(of: browser.lastLoadError) { _, new in
            if let new, !new.isEmpty {
                errorText = new
                showError = true
            }
        }
        .overlay(alignment: .top) {
            if updates.updateAvailable {
                Button {
                    updates.apply()
                } label: {
                    Text("Update available — tap to install \(updates.latest?.version ?? "")")
                        .font(.footnote.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.cyan.opacity(0.9))
                        .foregroundStyle(Color(red: 0.04, green: 0.07, blue: 0.12))
                        .clipShape(Capsule())
                }
                .padding(.top, 56)
            }
        }
    }

    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Color.clear
                if browser.isLoading {
                    Rectangle()
                        .fill(Color.cyan)
                        .frame(width: geo.size.width * max(0.02, browser.progress))
                }
            }
        }
        .frame(height: 2)
    }

    private func openCast() {
        browser.refreshVideos()
        browser.rebuildCandidates()
        cast.startDiscovery()
        showCastSheet = true
    }
}

struct BrowserToolbar: View {
    @EnvironmentObject var browser: BrowserModel
    @EnvironmentObject var cast: CastService
    var onCast: () -> Void
    var onKeyboard: () -> Void
    @FocusState private var addressFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Button(action: browser.goBack) {
                Image(systemName: "chevron.left")
            }
            .disabled(!browser.canGoBack)
            Button(action: browser.goForward) {
                Image(systemName: "chevron.right")
            }
            .disabled(!browser.canGoForward)
            Button(action: browser.loadHome) {
                Image(systemName: "house")
            }

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                TextField("Search or enter address", text: $browser.addressText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.webSearch)
                    .submitLabel(.go)
                    .focused($addressFocused)
                    .onSubmit {
                        addressFocused = false
                        browser.submitAddress()
                    }
                if addressFocused {
                    Button {
                        browser.addressText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                } else if browser.isLoading {
                    ProgressView()
                        .scaleEffect(0.7)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            Button(action: onCast) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: cast.connection.isConnected ? "tv.fill" : "tv.badge.wifi")
                        .foregroundStyle(cast.connection.isConnected ? Color.cyan : Color.primary)
                    if !browser.candidates.isEmpty {
                        Circle()
                            .fill(Color.cyan)
                            .frame(width: 8, height: 8)
                            .offset(x: 3, y: -3)
                    }
                }
            }
            .accessibilityLabel("Cast")
        }
        .font(.body.weight(.semibold))
        .foregroundStyle(Color.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color(red: 0.086, green: 0.125, blue: 0.200))
    }
}

struct NowPlayingBar: View {
    @EnvironmentObject var cast: CastService
    var onOpenCast: () -> Void
    var onKeyboard: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onOpenCast) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(cast.connection.deviceName ?? "Chromecast")
                        .font(.caption.weight(.semibold))
                    Text(cast.nowPlayingTitle ?? "Connected — tap to choose video")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .foregroundStyle(.white)
            Spacer()
            Button(action: onKeyboard) {
                Image(systemName: "keyboard")
            }
            .accessibilityLabel("Keyboard")
            Button(action: cast.togglePlayPause) {
                Image(systemName: cast.isPlaying ? "pause.fill" : "play.fill")
            }
            Button(action: cast.disconnect) {
                Image(systemName: "xmark")
            }
            .accessibilityLabel("Disconnect")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .foregroundStyle(Color.cyan)
        .background(Color(red: 0.086, green: 0.125, blue: 0.200))
    }
}
