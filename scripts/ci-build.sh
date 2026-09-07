#!/usr/bin/env bash
# Build ddrcast on GitHub Actions.
# Signs when BUILD_CERTIFICATE_BASE64 + BUILD_PROVISION_PROFILE_BASE64 are set;
# otherwise packages an unsigned arm64 IPA for sideloading.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

BUILD="${BUILD:-1}"
VERSION="${VERSION:-1.0.${BUILD}}"
SIGNED=0
if [[ -n "${BUILD_CERTIFICATE_BASE64:-}" && -n "${BUILD_PROVISION_PROFILE_BASE64:-}" ]]; then
  SIGNED=1
fi

echo "ddrcast CI build VERSION=${VERSION} SIGNED=${SIGNED}"
pod --version
pod install

WORKSPACE="ddrcast.xcworkspace"
SCHEME="ddrcast"
DERIVED="${ROOT}/DerivedData"

if [[ "$SIGNED" -eq 1 ]]; then
  CERTIFICATE_PATH="${RUNNER_TEMP:-/tmp}/build_certificate.p12"
  PP_PATH="${RUNNER_TEMP:-/tmp}/build_pp.mobileprovision"
  KEYCHAIN_PATH="${RUNNER_TEMP:-/tmp}/app-signing.keychain-db"
  KEYCHAIN_PASSWORD="${KEYCHAIN_PASSWORD:-$(openssl rand -base64 24)}"

  echo "$BUILD_CERTIFICATE_BASE64" | base64 --decode > "$CERTIFICATE_PATH"
  echo "$BUILD_PROVISION_PROFILE_BASE64" | base64 --decode > "$PP_PATH"

  security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
  security set-keychain-settings -lut 21600 "$KEYCHAIN_PATH"
  security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
  security import "$CERTIFICATE_PATH" -P "${P12_PASSWORD:-}" -A -t cert -f pkcs12 -k "$KEYCHAIN_PATH"
  security set-key-partition-list -S apple-tool:,apple: -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
  security list-keychain -d user -s "$KEYCHAIN_PATH"

  mkdir -p "$HOME/Library/MobileDevice/Provisioning Profiles"
  PROFILE_UUID=$(security cms -D -i "$PP_PATH" | plutil -extract UUID raw -)
  PROFILE_NAME=$(security cms -D -i "$PP_PATH" | plutil -extract Name raw -)
  TEAM_ID="${DEVELOPMENT_TEAM:-$(security cms -D -i "$PP_PATH" | plutil -extract TeamIdentifier.0 raw -)}"
  GET_TASK_ALLOW=$(security cms -D -i "$PP_PATH" | plutil -extract Entitlements.get-task-allow raw - 2>/dev/null || true)
  cp "$PP_PATH" "$HOME/Library/MobileDevice/Provisioning Profiles/${PROFILE_UUID}.mobileprovision"

  METHOD="ad-hoc"
  if [[ "$GET_TASK_ALLOW" == "true" ]]; then
    METHOD="development"
  fi
  if security cms -D -i "$PP_PATH" | grep -q ProvisionsAllDevices; then
    METHOD="enterprise"
  fi

  cat > /tmp/ExportOptions.plist << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key>
  <string>${METHOD}</string>
  <key>signingStyle</key>
  <string>manual</string>
  <key>teamID</key>
  <string>${TEAM_ID}</string>
  <key>compileBitcode</key>
  <false/>
  <key>stripSwiftSymbols</key>
  <true/>
  <key>provisioningProfiles</key>
  <dict>
    <key>ai.ddr.ddrcast</key>
    <string>${PROFILE_NAME}</string>
  </dict>
</dict>
</plist>
EOF

  xcodebuild \
    -workspace "$WORKSPACE" \
    -scheme "$SCHEME" \
    -configuration Release \
    -sdk iphoneos \
    -destination 'generic/platform=iOS' \
    -archivePath "${ROOT}/build/ddrcast.xcarchive" \
    -derivedDataPath "$DERIVED" \
    CODE_SIGN_STYLE=Manual \
    DEVELOPMENT_TEAM="$TEAM_ID" \
    PROVISIONING_PROFILE_SPECIFIER="$PROFILE_NAME" \
    MARKETING_VERSION="$VERSION" \
    CURRENT_PROJECT_VERSION="$BUILD" \
    archive

  xcodebuild \
    -exportArchive \
    -archivePath "${ROOT}/build/ddrcast.xcarchive" \
    -exportOptionsPlist /tmp/ExportOptions.plist \
    -exportPath "${ROOT}/export"

  IPA=$(find "${ROOT}/export" -name '*.ipa' | head -n1)
  test -n "$IPA"
  cp "$IPA" "${ROOT}/ddrcast.ipa"
  echo "SIGNED=1" > "${ROOT}/build-meta.env"
  echo "Built signed IPA ($METHOD) at ddrcast.ipa"
else
  xcodebuild \
    -workspace "$WORKSPACE" \
    -scheme "$SCHEME" \
    -configuration Release \
    -sdk iphoneos \
    -destination 'generic/platform=iOS' \
    -derivedDataPath "$DERIVED" \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGN_IDENTITY="" \
    DEVELOPMENT_TEAM="" \
    MARKETING_VERSION="$VERSION" \
    CURRENT_PROJECT_VERSION="$BUILD" \
    build

  APP=$(find "$DERIVED/Build/Products" -name 'ddrcast.app' -type d | head -n1)
  test -n "$APP"
  echo "Using $APP"
  file "$APP/ddrcast"
  rm -rf Payload ddrcast.ipa
  mkdir Payload
  cp -R "$APP" Payload/
  zip -r ddrcast.ipa Payload
  echo "SIGNED=0" > "${ROOT}/build-meta.env"
  echo "Built unsigned IPA at ddrcast.ipa"
fi

ls -lh "${ROOT}/ddrcast.ipa"
