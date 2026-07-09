# Build and install from Windows only

You cannot compile and sign an iPhone ARKit app directly on Windows. The app itself runs on iPhone, but Apple's iOS build/signing toolchain must run through Xcode/macOS somewhere in the pipeline.

This project includes two Windows-friendly routes:

1. **Codemagic + TestFlight, recommended** — easiest from Windows. Codemagic builds on cloud Mac hardware and uploads the app to TestFlight.
2. **GitHub Actions signed IPA, advanced** — GitHub builds on a hosted macOS runner. You provide Apple signing files as repository secrets.

For both routes, the iPhone installs the app over the internet through TestFlight or a signed IPA workflow. You do not need to own a Mac.

---

## Recommended route: Codemagic + TestFlight

### What you need

- Windows PC
- iPhone 16 Pro Max
- GitHub, GitLab, or Bitbucket account
- Apple Developer Program membership
- App Store Connect access
- Codemagic account

### Steps

1. Unzip this project on Windows.
2. Edit `codemagic.yaml`:
   - Replace `com.yourname.DimensionalScanner` with your real bundle ID.
   - Replace `YOUR_CODEMAGIC_APP_STORE_CONNECT_INTEGRATION_NAME` with your Codemagic App Store Connect integration name.
   - Replace `APP_STORE_APPLE_ID` after you create the App Store Connect app record.
3. Create a private GitHub repo and push the project.
4. In Apple Developer / App Store Connect:
   - Create the bundle ID.
   - Create the app record.
   - Create an App Store Connect API key with App Manager access.
5. In Codemagic:
   - Add the repository.
   - Add the App Store Connect API key integration.
   - Configure iOS code signing for the same bundle ID.
   - Run the `DimensionalScanner iOS TestFlight` workflow.
6. On the iPhone:
   - Install Apple TestFlight from the App Store.
   - Accept the TestFlight invitation.
   - Install DimensionalScanner.

---

## Advanced route: GitHub Actions signed IPA

Use `.github/workflows/ios-signed-ipa.yml`.

### Required GitHub repository secrets

- `APPLE_DEVELOPMENT_TEAM_ID` — Apple team ID.
- `BUILD_CERTIFICATE_BASE64` — base64 of your `.p12` signing certificate.
- `P12_PASSWORD` — password for the `.p12`.
- `PROVISION_PROFILE_BASE64` — base64 of your `.mobileprovision` file.
- `KEYCHAIN_PASSWORD` — any strong temporary password for the CI keychain.
- Optional for TestFlight upload: `APPSTORE_API_PRIVATE_KEY` — full text of your App Store Connect `.p8` private key.

### Required GitHub repository variables

- Optional for TestFlight upload: `APPSTORE_ISSUER_ID`.
- Optional for TestFlight upload: `APPSTORE_API_KEY_ID`.

### Helper scripts included for Windows

Create a CSR and private key on Windows:

```powershell
.\ci\windows\create-ios-distribution-csr.ps1 -CommonName "DimensionalScanner Distribution" -OutDir .\ios-signing
```

Upload `ios-signing\ios_distribution.csr` to Apple Developer when creating an Apple Distribution certificate. Download the `.cer` file from Apple, then create the `.p12`:

```powershell
.\ci\windows\make-p12-from-apple-cer.ps1 `
  -CerPath .\ios-signing\distribution.cer `
  -PrivateKeyPath .\ios-signing\ios_distribution.key `
  -P12Password "choose-a-strong-password" `
  -OutPath .\ios-signing\ios_distribution.p12
```

Copy a file as base64 for GitHub secrets:

```powershell
.\ci\windows\base64-file.ps1 .\ios-signing\ios_distribution.p12
```

Repeat for the `.mobileprovision` file:

```powershell
.\ci\windows\base64-file.ps1 .\ios-signing\DimensionalScanner_AppStore.mobileprovision
```

### Run the GitHub workflow

1. Open your GitHub repo on Windows.
2. Go to **Actions**.
3. Select **Build signed iPhone IPA**.
4. Click **Run workflow**.
5. Enter your bundle ID.
6. Choose export method:
   - `development` for a development provisioning profile.
   - `ad-hoc` for an ad hoc provisioning profile.
   - `app-store-connect` for App Store/TestFlight distribution.
7. Turn on `upload_to_testflight` only after App Store Connect API variables/secrets are configured.

---

## Important notes

- A plain `.ipa` file cannot run on an iPhone unless it is signed for that device or distributed through Apple.
- A free Apple account is normally enough only when installing from Xcode to a physically connected iPhone. With Windows-only hardware, TestFlight/App Store Connect is the cleaner route.
- The iOS Simulator is not useful for this app because the scanner needs physical iPhone camera/LiDAR hardware.
- The native app keeps scanning, STL export, measurement, and CSV tolerance reporting on the iPhone after installation.
