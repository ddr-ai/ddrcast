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
        ZStack {
            VStack(spacing: 0) {
                BrowserToolbar(
                    onCast: openCast,
                    onKeyboard: { showKeyboard = true }
                )
                TabStrip()
                progressBar
                WebContainerView(webView: browser.selected.webView)
                    .ignoresSafeArea(.container, edges: .bottom)
                if cast.connection.isConnected {
                    NowPlayingBar(onOpenCast: openCast, onKeyboard: { showKeyboard = true })
                }
            }

        }
        .overlay(alignment: .trailing) {
            VideoSourceDrawer(
                onCast: castCaptured,
                onPickDevice: {
                    cast.startDiscovery()
                    showCastSheet = true
                }
            )
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
        cast.startDiscovery()
        showCastSheet = true
    }

    private func castCaptured() {
        guard let candidate = browser.selected.tappedVideo?.candidate else { return }
        let started = cast.castOrQueue(candidate)
        if !started {
            showCastSheet = true
        }
    }
}

struct TabStrip: View {
    @EnvironmentObject var browser: BrowserModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(browser.tabs) { tab in
                    tabChip(tab)
                }
                Button(action: { browser.newTab() }) {
                    Image(systemName: "plus")
                        .font(.footnote.weight(.bold))
                        .padding(8)
                        .background(Color.white.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .accessibilityLabel("New tab")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
        .background(Color(red: 0.07, green: 0.11, blue: 0.18))
    }

    private func tabChip(_ tab: BrowserTab) -> some View {
        let selected = tab.id == browser.selectedID
        return HStack(spacing: 6) {
            Button {
                browser.select(tab.id)
            } label: {
                Text(tab.tabTitle)
                    .lineLimit(1)
                    .font(.caption.weight(selected ? .semibold : .regular))
            }
            Button {
                browser.closeTab(tab.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2.weight(.bold))
            }
            .accessibilityLabel("Close tab")
        }
        .foregroundStyle(selected ? Color.cyan : Color.white.opacity(0.85))
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: 180)
        .background(selected ? Color.cyan.opacity(0.15) : Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

/// Overlay drawer. Does not resize or pause the web view.
struct VideoSourceDrawer: View {
    @EnvironmentObject var browser: BrowserModel
    @EnvironmentObject var cast: CastService
    var onCast: () -> Void
    var onPickDevice: () -> Void

    private var tab: BrowserTab { browser.selected }

    var body: some View {
        Group {
            if tab.hasCapturedSource {
                HStack(spacing: 0) {
                    toggleHandle
                    if tab.sourcePanelOpen {
                        panel
                            .frame(width: 320)
                            .transition(.move(edge: .trailing))
                    }
                }
                .frame(maxHeight: .infinity, alignment: .center)
                .padding(.vertical, 8)
            }
        }
        .animation(.easeInOut(duration: 0.28), value: tab.sourcePanelOpen)
    }

    private var toggleHandle: some View {
        Button {
            tab.toggleSourcePanel()
        } label: {
            Image(systemName: tab.sourcePanelOpen ? "chevron.right" : "chevron.left")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 56)
                .background(Color.cyan.opacity(0.95))
                .clipShape(
                    UnevenRoundedRectangle(
                        topLeadingRadius: 10,
                        bottomLeadingRadius: 10,
                        bottomTrailingRadius: 0,
                        topTrailingRadius: 0
                    )
                )
        }
        .accessibilityLabel(tab.sourcePanelOpen ? "Hide video source" : "Show video source")
        .padding(.trailing, tab.sourcePanelOpen ? 0 : 0)
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Video source")
                    .font(.headline)
                Spacer()
                Button {
                    tab.dismissCapturedVideo()
                } label: {
                    Image(systemName: "xmark")
                        .font(.footnote.weight(.bold))
                }
                .accessibilityLabel("Close source panel")
            }

            if let tapped = tab.tappedVideo {
                Text(tapped.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(3)

                if tapped.waitingForContent {
                    Label("Ad detected — waiting for the content URL…", systemImage: "hourglass")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else if tapped.hasAd, tapped.displayURL != nil {
                    Label("Ad skipped. Casting the content source.", systemImage: "checkmark.seal")
                        .font(.caption)
                        .foregroundStyle(.cyan)
                }

                if let url = tapped.displayURL {
                    Text(url.absoluteString)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                } else {
                    Text("No direct http(s) media URL on this video yet.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button(action: onCast) {
                    Label(
                        tapped.hasAd ? "Cast ad-free" : "Cast this source",
                        systemImage: "tv"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.cyan)
                .disabled(tapped.displayURL == nil)

                if !cast.connection.isConnected {
                    Button("Choose Chromecast…", action: onPickDevice)
                        .font(.caption)
                }

                Text("Hiding this panel does not change the tab or the page. Toggle it back any time.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(14)
        .foregroundStyle(.white)
        .background(Color(red: 0.09, green: 0.14, blue: 0.22).opacity(0.97))
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(width: 1)
        }
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
                TextField("Search or enter address", text: browser.addressBinding)
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
                        browser.selected.addressText = ""
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
                    if browser.selected.hasCapturedSource {
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
