# Accuracy and limitations

This app uses ARKit scene reconstruction. That makes it practical for quick on-device STL capture, but it is not equivalent to a calibrated structured-light scanner, laser scanner, CMM, or optical comparator.

Expected weak spots:

- Small holes and threads.
- Sharp edges.
- Deep concavities.
- Reflective, transparent, glossy, or black objects.
- Undersides hidden from the camera.
- Thin features near the LiDAR resolution limit.
- Table or wall geometry inside the crop volume.

For tolerance decisions, run a validation study with known artifacts. Measure the same parts with calipers, gauge blocks, or a CMM and compare results before using the app for pass/fail inspection.
