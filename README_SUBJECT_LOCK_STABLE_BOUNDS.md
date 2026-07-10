# Tap-to-lock subject selection and stable dimensions

This patch fixes the expanding green object box seen while scanning small calibration parts.

## Why the old box expanded

The screenshot showed a four-point area of about **30.5 × 27.2 mm**, while the green X/Z box grew to about **45.9 × 43.1 mm**. The previous default edge margin was 8 mm per side, so the old measured limit was approximately:

- X: 30.5 + 8 + 8 = 46.5 mm
- Z: 27.2 + 8 + 8 = 43.2 mm

That margin was useful for retaining edge triangles, but it should never have been counted as part size.

The 136 mm height was a separate problem: sparse depth rays or coarse room-mesh fragments became connected to the cube and were treated as part of the same object.

## What this patch changes

1. **Capture margin is no longer measurement margin.** X and Z are clamped to the original four-point footprint before dimensions are calculated.
2. **Four points no longer start scanning immediately.** After point four, aim the reticle at the actual object and tap **Select Object**.
3. **The selected 3D point becomes a subject lock.** An ellipsoidal lock volume rejects remote walls, shelves, hands, and tall depth rays before component analysis.
4. **Fine LiDAR depth is preferred.** Coarse AR room mesh is disabled by default for small parts and remains an optional fallback.
5. **Component merging is conservative.** Only fragments directly adjacent to the selected subject can merge; recursive chain growth is removed.
6. **Robust dimensions are used.** X/Z percentile trimming, a grounded height-density estimator, and sparse-outlier rejection reduce false growth.
7. **The green box is stabilized too.** A rolling median is applied to local min/max bounds, not only to the number labels.
8. **Explosive one-frame growth is ignored.** Large sudden jumps do not enter the displayed measurements or green box.

## New workflow

1. Capture four ground points clockwise around one object.
2. Aim the center reticle at a visible surface on the object.
3. Tap **Select Object**.
4. Move slowly around the object while the teal surface fills in.
5. Wait for the bounds stability indicator to rise.
6. Tap **Finish & Measure**.

The camera screen displays:

```
4-POINT AREA • TAP-TO-LOCK
```

If this badge is missing, the iPhone is running an older TestFlight build.

## Suggested settings for a 1 × 1 × 1 inch calibration cube

- Footprint edge margin: **1.0–1.5 mm**
- Maximum object height: **60 mm**
- Ground clearance: **1.5–2.0 mm**
- Minimum object height: **3 mm**
- Surface merge distance: **4–6 mm**
- Object lock radius: **45–55 mm**
- Outlier trimming: **2.5–4.0%**
- Coarse AR room mesh fallback: **Off**
- Depth sampling density: **High** or **Balanced**

Place the four ground points approximately 5–10 mm outside the cube. Aim the selection reticle at the center of the front or top face, not the table.

## Important limitation

This is a 3D LiDAR subject lock inspired by tap-to-select behavior. It does not invoke the private Photos interface. Still-image subject masks are not sufficient by themselves because the camera moves during a 3D scan; this implementation locks the selected subject in world-space and follows its LiDAR-connected surface.
