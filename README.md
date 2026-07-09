# DimensionalScanner iOS

Native iPhone app prototype for on-device 3D object scanning, STL export, and tolerance analysis.

The app uses ARKit scene reconstruction on LiDAR-capable iPhones/iPads. It captures AR mesh anchors, crops them to a user-defined object volume, converts the cropped mesh from meters to millimeters, exports an ASCII STL file, measures the STL bounding box, and writes a CSV tolerance report.

## What is included

- `DimensionalScanner.xcodeproj` — open this in Xcode to install the phone app.
- `App/` — SwiftUI + ARKit app code.
- `Sources/DimensionalScannerCore/` — pure Swift mesh/STL/tolerance engine.
- `Tests/` — unit tests for the core engine.
- `Tools/CoreSelfTest/` — command-line self-test that exports a sample STL and CSV report.


## Windows-only note

If you only have a Windows PC, use `WINDOWS_ONLY_DEPLOYMENT.md`. The app still needs Apple iOS signing and a macOS/Xcode build environment somewhere, but the included GitHub Actions workflow lets a Windows user run that build on a hosted macOS runner and install the app through TestFlight.

## Install on iPhone

1. Open `DimensionalScanner.xcodeproj` in Xcode.
2. Select the `DimensionalScanner` target.
3. In **Signing & Capabilities**, choose your Apple Developer team.
4. Change the bundle identifier from `com.example.DimensionalScanner` to a unique value.
5. Connect your iPhone 16 Pro Max by USB or use wireless debugging.
6. Select the physical iPhone as the run destination.
7. Press **Run**.
8. On first launch, allow camera access.

## Use the app

1. Place the object on a stable surface with visible texture around it.
2. Launch the app.
3. Aim the center of the screen at the center of the object and tap **Set Center**.
4. Tap **Scan**.
5. Walk slowly around the object so ARKit sees all sides.
6. Tap **Stop**.
7. Tap **Export STL**.
8. Use **Share STL** and **Share CSV** to send the output to Files, AirDrop, Mail, or another app.

## Setup tips

- Keep the crop volume tight around the object. Anything inside that box can appear in the STL, including a table or wall.
- Use a matte object or matte spray for shiny parts.
- Scan slowly with good lighting.
- Keep the object still.
- For dimensional tolerance work, verify the system against physical gauge blocks/calipers before accepting pass/fail results.

## Local test on a Mac/Linux machine

The iOS ARKit app cannot run without Xcode and a physical LiDAR iPhone, but the mesh/STL/tolerance engine can be tested anywhere Swift runs:

```bash
swift test
swift run CoreSelfTest --out ./self_test_output
```

Expected self-test dimensions:

```text
bbox_x_mm = 70.000 PASS
bbox_y_mm = 110.000 PASS
bbox_z_mm = 50.000 PASS
```

## Limitations

This is a working prototype, not a certified metrology instrument. ARKit scene reconstruction produces an approximate mesh. It can miss small features, blind holes, threads, deep concavities, reflective surfaces, black surfaces, and hidden undersides. The current tolerance system checks cropped STL bounding dimensions: `bbox_x_mm`, `bbox_y_mm`, and `bbox_z_mm`.

## Windows-only owner note

If you do not have a Mac, use `WINDOWS_ONLY_BUILD_AND_INSTALL.md`. This package includes `codemagic.yaml` plus GitHub Actions workflows so the iOS app can be built on cloud macOS infrastructure and installed on the iPhone through TestFlight.
