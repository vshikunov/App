#!/usr/bin/env bash
set -euo pipefail

require_env() {
  local name="$1"
  if [[ -z "${!name:-}" ]]; then
    echo "Missing required environment variable: $name" >&2
    exit 2
  fi
}

require_env BUILD_CERTIFICATE_BASE64
require_env P12_PASSWORD
require_env PROVISION_PROFILE_BASE64
require_env KEYCHAIN_PASSWORD
require_env DEVELOPMENT_TEAM
require_env BUNDLE_ID

WORK_DIR="$PWD/build/signing"
mkdir -p "$WORK_DIR"
CERT_PATH="$WORK_DIR/signing_certificate.p12"
PROFILE_PATH="$WORK_DIR/profile.mobileprovision"
PROFILE_PLIST="$WORK_DIR/profile.plist"
KEYCHAIN_PATH="$RUNNER_TEMP/dimensional-scanner-signing.keychain-db"

printf '%s' "$BUILD_CERTIFICATE_BASE64" | base64 --decode > "$CERT_PATH"
printf '%s' "$PROVISION_PROFILE_BASE64" | base64 --decode > "$PROFILE_PATH"

security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
security set-keychain-settings -lut 21600 "$KEYCHAIN_PATH"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
security import "$CERT_PATH" -P "$P12_PASSWORD" -A -t cert -f pkcs12 -k "$KEYCHAIN_PATH"
security list-keychain -d user -s "$KEYCHAIN_PATH" $(security list-keychains -d user | sed s/\"//g)
security default-keychain -d user -s "$KEYCHAIN_PATH"
security set-key-partition-list -S apple-tool:,apple: -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"

security cms -D -i "$PROFILE_PATH" > "$PROFILE_PLIST"
PROFILE_UUID=$(/usr/libexec/PlistBuddy -c 'Print UUID' "$PROFILE_PLIST")
PROFILE_NAME=$(/usr/libexec/PlistBuddy -c 'Print Name' "$PROFILE_PLIST")
PROFILE_APP_ID=$(/usr/libexec/PlistBuddy -c 'Print Entitlements:application-identifier' "$PROFILE_PLIST" 2>/dev/null || true)

mkdir -p "$HOME/Library/MobileDevice/Provisioning Profiles"
cp "$PROFILE_PATH" "$HOME/Library/MobileDevice/Provisioning Profiles/$PROFILE_UUID.mobileprovision"

cat > "$PWD/build/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>${EXPORT_METHOD:-development}</string>
    <key>teamID</key>
    <string>$DEVELOPMENT_TEAM</string>
    <key>signingStyle</key>
    <string>manual</string>
    <key>provisioningProfiles</key>
    <dict>
        <key>$BUNDLE_ID</key>
        <string>$PROFILE_NAME</string>
    </dict>
    <key>stripSwiftSymbols</key>
    <true/>
    <key>compileBitcode</key>
    <false/>
</dict>
</plist>
PLIST

cat <<SUMMARY
Installed signing assets.
Provisioning profile UUID: $PROFILE_UUID
Provisioning profile name: $PROFILE_NAME
Provisioning profile app id: $PROFILE_APP_ID
Bundle ID requested: $BUNDLE_ID
Export method: ${EXPORT_METHOD:-development}
SUMMARY
