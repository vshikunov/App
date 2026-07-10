# Four-Point Ground Footprint Workflow

## Capture order

Capture four ground points clockwise around the part. Keep every point on the same flat support surface.

A good pattern is:

1. near-left corner;
2. far-left corner;
3. far-right corner;
4. near-right corner.

The points do not need to form a perfect rectangle. The app creates a convex four-sided footprint from them.

## Scanning

Scanning begins immediately after corner 4. Walk around the object slowly. Include slightly elevated views so the top is reconstructed. The live teal mesh is the isolated surface that will be exported.

## Finish

Tap **Finish & Measure** after the visible sides are covered. The result panel shows:

- W / X: STL width;
- H / Y: height above the captured ground plane;
- D / Z: STL depth;
- triangle and vertex counts;
- tolerance results.

The app also creates:

- an STL file;
- a raw dimensions CSV;
- a tolerance CSV.

## Settings

- **Maximum object height:** vertical search limit above the ground polygon. Keep it only slightly higher than the expected object.
- **Ground clearance:** removes table/floor geometry near zero height.
- **Minimum object height:** rejects small debris and low mesh fragments.
- **Surface merge distance:** joins nearby disconnected pieces of the same scanned object. Reduce it if separate objects are being joined.
- **Footprint edge margin:** retains triangles that cross the polygon edge.

## Practical setup

Use one matte, opaque object on a clear support surface. Avoid transparent parts, mirrors, highly reflective metal, and nearby objects inside the polygon. LiDAR scene reconstruction is approximate and should be validated against known standards before tolerance decisions.
