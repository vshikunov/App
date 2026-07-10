# Object Capture coherent-mesh replacement

## Why this patch exists

The previous scanner accumulated per-frame LiDAR depth triangles. That approach can create floating sheets, duplicated surfaces, and a bounding box that grows when camera-pose or depth noise drifts. Tight crop boxes and outlier trimming can hide some errors, but they cannot turn independently accumulated depth frames into a coherent, watertight object model.

This patch replaces the main capture workflow with Apple's native Object Capture pipeline:

1. `ObjectCaptureSession` detects the intended subject.
2. `ObjectCaptureView` presents Apple's editable 3D selection box and guided capture dial.
3. The session automatically saves useful high-resolution views and LiDAR data.
4. On-device `PhotogrammetrySession` reconstructs one USDZ model.
5. Model I/O exports that model to STL.
6. The app converts STL coordinates from meters to millimeters, moves the minimum corner to the STL origin, measures X/Y/Z bounds, and creates measurement/tolerance CSV files.

The old four-ground-point/depth-fusion UI is no longer the default screen. Its source files remain in the project only to avoid changing the Xcode project structure; `ContentView.swift` no longer instantiates that scanner.

## Visible build marker

The correct app shows:

```text
OBJECT CAPTURE • COHERENT MESH
```

If this marker is absent, TestFlight is running an older build.

## Capture workflow

1. Put one stationary object on a textured, nonreflective surface.
2. Tap **Select Object**.
3. Tighten Apple's automatic 3D box around only the object.
4. Tap **Use This Box**.
5. Move slowly around the object until the capture dial is complete.
6. For a small part, tap **More Angles** and complete another orbit from a different height.
7. Tap **Build 3D Model**.
8. Keep the app open while on-device reconstruction runs.
9. Review dimensions from the final STL and share STL, USDZ, raw-dimensions CSV, or tolerance CSV.

## One-inch calibration cube

A 1 inch cube is 25.4 x 25.4 x 25.4 mm. A plain black, glossy, or featureless cube is difficult for photogrammetry. Use bright diffuse light and add temporary removable visual texture, such as small paper dots or a washable scanning spray. Do not move the object during a scan pass.

The result page includes a button to calibrate a coherent cube result to 25.4 mm. That applies a uniform scale correction only. It does not repair missing faces or a distorted reconstruction.

## Accuracy boundary

Object Capture should produce a substantially more coherent model than raw depth-sheet accumulation. It is still not an industrial CMM, structured-light metrology scanner, or certified acceptance gauge. Validate repeatability and bias against calibrated physical standards before using tolerance results for production decisions.

## Files replaced

```text
App/ContentView.swift
```

## Files added

```text
README_OBJECT_CAPTURE_COHERENT_MESH.md
```
