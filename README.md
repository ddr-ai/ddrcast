# ddrcast

Native **iPhone and iPad** web browser that casts video to **Chromecast** devices on the local Wi-Fi.

Repository: [https://github.com/ddr-ai/ddrcast](https://github.com/ddr-ai/ddrcast)

## What it does

- Full in-app browser (`WKWebView`).
- Toolbar: **Back**, **Forward**, **Home** on the left; combined **URL / search** bar in the center; **Cast** on the right.
- Cast button discovers Chromecasts on the LAN (mDNS `_googlecast._tcp`) and lists them.
- Two cast paths, in this order:
  1. **Direct video URL** — you enter or browse to an `.mp4`, `.m3u8`, `.webm`, etc.
  2. **Embedded video** — the page is scanned for `<video>` / `<source>` / `og:video`. If a real `http(s)` media URL is found, that URL is cast.
- Playback uses Google’s **Default Media Receiver** (`CC1AD845`). The Chromecast fetches the media URL itself over the network. There is no relay server in ddrcast.
- Connected state, now-playing bar, play/pause, and **Disconnect**.
- Keyboard icon while connected — see [Remote text input](#remote-text-input).

## Technology choices

| Piece | Choice | Why |
|---|---|---|
| UI | **SwiftUI**, iOS 17+, iPhone + iPad (`TARGETED_DEVICE_FAMILY = 1,2`) | Same native stack as [ddrdesk-ios](https://github.com/ddr-ai/ddrdesk-ios). |
| Browser | **WKWebView** | The system web engine: JS, cookies, media, back-forward list. |
| Cast | **Google Cast iOS Sender SDK** (`google-cast-sdk` ~> 4.8.6) via CocoaPods | Official implementation of the Cast V2 protocol (local mDNS discovery, TLS to port 8009, media namespace). |
| Receiver | **Default Media Receiver only** | No custom receiver and no registered Cast App ID. Direct media URLs are what this receiver is for. |
| Search | DuckDuckGo | URL bar accepts either a URL or a search query. |
| CI | GitHub Actions `macos-26` | Builds an `.ipa` on every push with the iOS SDK that includes `UIGlassEffect` (required by Cast SDK 4.8.6). Signs when secrets exist; otherwise unsigned for sideload. |

Using the official SDK (instead of a homegrown Cast client) is the reliable way to speak the Google Cast protocol, including session resume and media status. Discovery and media transport stay on the LAN. Guest Mode / cloud relay is not a feature of this app.

**Google Cast SDK terms:** building this project downloads Google’s Cast SDK. Use is subject to the [Google APIs Terms](https://developers.google.com/terms/) and [Cast SDK Additional Developer Terms](https://developers.google.com/cast/docs/terms/).

## Casting behavior and limits

**Preferred:** extract a direct media URL and `loadMedia` on the Default Media Receiver. That is the fastest, most reliable path.

**If extraction fails** (blob URLs, Media Source Extensions, DRM): the app **does not** load the webpage on the Chromecast and **does not** start screen mirroring. It shows a clear error.

Page-as-receiver-video is **not technically supported** on the Default Media Receiver (that receiver is a media player, not a web browser). Doing it would require a **custom Cast receiver** and a registered Application ID. Per the project spec, that is not implemented.

DRM / logged-in streamers (YouTube, Netflix, and similar) will not cast. That is a protocol/DRM limit, not a missing button.

The home page includes Google’s public Cast sample MP4s so you can verify a device without hunting for a file.

## Remote text input

While connected, the Cast UI includes a **keyboard** icon and a native `TextField`.

**The Default Media Receiver cannot accept that text.** It has no text field and no Cast text-input namespace. ddrcast does **not** fake the on-TV letter picker and does **not** implement Android TV Remote (a different protocol, Google TV devices only) or a custom receiver channel.

The keyboard screen states this limitation instead of silently dropping keystrokes. A workaround needs either:

1. A registered custom Cast receiver that implements a text-input message namespace, or
2. Android TV Remote on Chromecast-with-Google-TV / Google TV (not classic Chromecast HDMI dongles).

Neither is in this repo until you choose one.

## Setup (Mac)

Need Xcode 16+, CocoaPods, iOS 17 SDK.

```bash
git clone https://github.com/ddr-ai/ddrcast.git
cd ddrcast
pod install
open ddrcast.xcworkspace
```

Always open the **workspace**, not the `.xcodeproj`. Allow **Local Network** on first Cast scan.

Bundle ID: `ai.ddr.ddrcast`.

### Local unsigned device build

```bash
pod install
xcodebuild -workspace ddrcast.xcworkspace -scheme ddrcast -sdk iphoneos \
  -configuration Release CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build
```

## GitHub Actions IPA

Every push to `main` (and **Actions → Build IPA → Run workflow**) produces `ddrcast.ipa` as a workflow artifact and publishes it to the `unsigned-ipa` release tag.

**Download:** [ddrcast.ipa](https://github.com/ddr-ai/ddrcast/releases/download/unsigned-ipa/ddrcast.ipa)

Install page: https://ddr-ai.github.io/ddrcast/

### Optional signing secrets

If these GitHub Actions secrets are set, CI signs the IPA automatically:

| Secret | Contents |
|---|---|
| `BUILD_CERTIFICATE_BASE64` | `.p12` signing certificate, base64 |
| `P12_PASSWORD` | Password for that `.p12` |
| `BUILD_PROVISION_PROFILE_BASE64` | `.mobileprovision` for `ai.ddr.ddrcast`, base64 |
| `DEVELOPMENT_TEAM` | 10-character Apple Team ID |
| `KEYCHAIN_PASSWORD` | Optional; CI generates one if omitted |

Create the files with:

```bash
base64 -i certificate.p12 | pbcopy
base64 -i profile.mobileprovision | pbcopy
```

The profile must include App ID `ai.ddr.ddrcast`. Development profiles export as `development`; ad-hoc as `ad-hoc`.

If the secrets are **missing**, CI still succeeds: it writes an **unsigned** IPA (`CODE_SIGNING_ALLOWED=NO`) suitable for sideloading.

## Sideload an unsigned IPA

The unsigned IPA has no signature and no provisioning profile. Sign it with your Apple ID, then install:

1. **Sideloadly** (Windows/macOS): open `ddrcast.ipa`, Apple ID, install.
2. **AltStore / AltServer / SideStore**: sideload; they re-sign with your Apple ID.
3. **Feather / ESign / GBox** on the phone, using the install page above.
4. **Mac + Xcode**: set a Development Team on the `ddrcast` target, run on a device.

On first launch, allow **Local Network** (required for Chromecast mDNS).

**AltStore/SideStore source** (add once):

https://github.com/ddr-ai/ddrcast/releases/download/unsigned-ipa/altstore.json

Stock iOS cannot overwrite a sideloaded app by itself. After the first install, keep AltStore/SideStore/Feather/ESign on the phone so later Actions builds can be applied on-device.

## Use

1. Open ddrcast. Home has sample MP4s; or type a URL / search.
2. Tap the TV button. Pick a Chromecast on the same Wi-Fi.
3. If the page has a castable `<video>`, the **Recommended** row is the direct media URL (usually `video.currentSrc`).
4. If nothing is extractable, read the error — the app will not mirror the screen.
5. Disconnect from the sheet or the now-playing bar to return to normal browsing.

## Project layout

```
ddrcast/                  SwiftUI app
ddrcast.xcodeproj/        Xcode project (CocoaPods generates the workspace)
Podfile                   google-cast-sdk
.github/workflows/ipa.yml CI
scripts/ci-build.sh       Signed vs unsigned IPA packaging
web/install.html          Phone install page template
```
