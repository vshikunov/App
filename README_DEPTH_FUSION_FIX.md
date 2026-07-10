# Four-Point LiDAR Depth-Fusion Fix

## Why the earlier build produced no STL

The earlier four-point build depended mainly on ARKit scene-reconstruction mesh anchors. That mesh is designed to estimate the surrounding environment and can omit or simplify a small tabletop part. When no usable triangles appeared inside the four-point footprint, the app had nothing to write to STL.

This patch keeps ARKit scene mesh support, but adds a second capture path:

1. Enables `smoothedSceneDepth` or `sceneDepth` on the AR session.
2. Copies depth and confidence pixels from repeated AR frames.
3. Unprojects those pixels into world-space 3D points.
4. Keeps only depth samples inside the four-point ground polygon and above the ground-clearance plane.
5. Connects adjacent samples into surface triangles while rejecting large depth discontinuities.
6. Accumulates and deduplicates triangles from multiple viewpoints.
7. Fuses those triangles with any ARKit scene mesh triangles.
8. Isolates the dominant non-ground surface cluster and writes it to STL.

## Visible confirmation

The corrected build shows this badge near the top of the camera view:

`4-POINT AREA • DEPTH FUSION`

If that badge is absent, the iPhone is running an older TestFlight build.

## Live diagnostics

During scanning, expand the top status chip. You will see:

- `pts`: accepted LiDAR depth samples accumulated inside the four-point area.
- `tris`: depth-derived surface triangles accumulated from those samples.
- `anchors`: ARKit scene-mesh anchors available as supplemental geometry.
- `LiDAR depth`, `ARKit mesh`, or `LiDAR depth + AR mesh`: the active source.

The Finish button is deliberately tappable even when the counters are zero. Tapping it will now display an actionable diagnostic instead of silently doing nothing.

## Recommended first test

- Use one matte, opaque object on a clear flat table.
- Make the four-point polygon 20–50 mm larger than the object on each side.
- Keep the phone approximately 25–80 cm from the object.
- Capture the four ground corners clockwise.
- After point 4, move slowly around the object and tilt the phone enough to see its top and lower edges.
- Wait until `pts` and `tris` increase, then tap **Finish & Measure**.

## If the counters do not increase

### `pts = 0`

- Keep the object inside the blue polygon.
- Move closer, but not extremely close; start around 40 cm.
- Verify **Fuse per-frame LiDAR depth** is enabled in Scan settings.
- **Include low-confidence depth** is enabled by default in this patch.
- Reduce **Ground clearance** if the part is very thin.
- Increase **Maximum object height** if the part extends above the configured search volume.
- Avoid transparent, mirror-like, or highly reflective surfaces.

### `pts > 0`, but `tris = 0`

- Set Sampling density to **High**.
- Increase **Max depth-triangle edge** to 45–55 mm.
- Move more slowly so adjacent depth samples remain coherent.

### `tris > 0`, but no teal object appears

- Increase **Surface merge distance** slightly.
- Lower **Minimum object height** for a small or flat part.
- Remove other objects, hands, or fixtures from inside the blue polygon.

## Files replaced

- `App/ScannerViewModel.swift`
- `App/ARScannerView.swift`
- `App/ContentView.swift`
- `App/ScanSettingsView.swift`

The patch does not replace signing assets, `codemagic.yaml`, the bundle identifier, certificates, provisioning profiles, or the Xcode project.

## Accuracy limitation

The output is an approximate LiDAR/depth surface and may be open or non-watertight. It is suitable for prototyping, approximate external dimensions, and workflow development. Validate tolerance decisions against calipers, gauges, or a CMM before using results for acceptance inspection.
