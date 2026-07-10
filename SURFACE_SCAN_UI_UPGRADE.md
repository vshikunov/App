# Measure-style surface scan upgrade

This patch replaces the large always-open control panel with a compact camera-first interface and changes the six reference points into a complete oriented bounding box.

## Six-face point order

Capture one point near the center of each opposite face, in this order:

1. Bottom face
2. Top face
3. Left face
4. Right face
5. Front face
6. Back face

The points are **face points, not six arbitrary corners**. The three opposite-face pairs define the box's height, width, depth, orientation, center, and lower-left-front coordinate origin.

After point 6, the app draws a blue 3D wireframe box. Only LiDAR mesh triangles inside that volume are selected for the object scan. A small configurable margin helps retain triangles along the edges.

## Camera-first controls

- Tap the compact status chip at the top to expand or collapse details.
- Tap the eye-slash button to hide all controls. Tap the eye button to restore them.
- Use the ellipsis menu for settings, tolerances, help, clearing the box, or resetting AR.
- The center reticle turns cyan when a depth/raycast surface is available and orange when no stable point is available.
- The large white Add button captures the current face point.

## Surface capture

After the blue box appears:

1. Tap **Scan Surface**.
2. Move slowly around every side of the part.
3. Watch the translucent teal mesh fill in over the real object.
4. The ring reports rough horizontal view coverage; it is guidance, not a metrology quality score.
5. Tap **Stop** to inspect the captured surface.
6. Tap **Resume** if a side or corner is missing.
7. Tap **Export STL** when the teal surface is satisfactory.

The full-room red/mesh overlay is now off by default. It remains available under the ellipsis menu as a diagnostic option.

## Output coordinate frame

- X: left face toward right face
- Y: bottom face toward top face
- Z: front face toward back face
- Origin: lower-left-front corner of the six-face box

The app removes likely floor/table triangles close to the bottom plane before preview and STL export.

## Important limitations

The teal surface is ARKit's LiDAR scene-reconstruction mesh filtered by the user-defined box. It is not a textured photogrammetry model and is not equivalent to a CMM or industrial structured-light scanner. Very small features, holes, threads, reflective surfaces, transparent surfaces, thin edges, and hidden undersides can be incomplete or inaccurate.
