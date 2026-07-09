# 6-Point Reference and Object Detection Workflow

This version adds a guided 6-point reference workflow for object scanning.

## What the six points mean

1. **Ground zero / datum** — the zero-height reference on the floor/table/fixture.
2. **Highest point** — the top of the part. This defines the reference height from datum.
3. **Boundary point 1** — first footprint/boundary point around the part.
4. **Boundary point 2** — second footprint/boundary point around the part.
5. **Boundary point 3** — third footprint/boundary point around the part.
6. **Boundary point 4** — fourth footprint/boundary point around the part.

The app computes an object-local coordinate system from those points:

- STL **Y = 0** is the captured ground-zero datum.
- Local **Y** points from ground zero to the highest point.
- Local **X/Z** are computed from the four boundary points.
- Only mesh inside that 6-point volume is kept during export.
- Flat table/floor mesh immediately at the zero plane is filtered out.

## Recommended capture process

1. Put the part on a stable, matte surface.
2. Aim the reticle at the ground/datum next to or under the part and tap **Capture Point**.
3. Aim at the highest visible point of the part and tap **Capture Point**.
4. Aim at four boundary points around the part footprint and tap **Capture Point** for each one.
5. Tap **Detect + Scan**.
6. Walk slowly around the object until the mesh overlay covers the part.
7. Tap **Stop**.
8. Tap **Export STL + CSV**.
9. Share the STL and CSV from the iPhone.

## Notes

The six-point workflow does not make LiDAR metrology-grade. It improves object isolation and establishes a usable datum. Validate against calipers, gauge blocks, or a CMM before using tolerance results for acceptance decisions.
