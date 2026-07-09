# Build and launch on iPhone

## Requirements

- Mac with Xcode installed.
- iPhone 16 Pro Max or another LiDAR-capable iPhone/iPad.
- Apple ID signed into Xcode.
- Developer Mode enabled on the iPhone.

## Steps

1. Open `DimensionalScanner.xcodeproj`.
2. Click the project in the left navigator.
3. Select the `DimensionalScanner` target.
4. Go to **Signing & Capabilities**.
5. Choose your team.
6. Change `com.example.DimensionalScanner` to a unique bundle identifier.
7. Connect the iPhone.
8. Select the iPhone in the Xcode run destination menu.
9. Press **Product > Run**.
10. Approve the developer prompt on the iPhone if iOS asks.
11. Allow camera access when the app launches.

## If Xcode refuses to install

- Make sure Developer Mode is enabled on the phone.
- Trust the Mac on the phone.
- Make the bundle identifier unique.
- Confirm the selected destination is the physical iPhone, not a simulator.
- Scene reconstruction requires LiDAR; the app will not scan properly in Simulator.
