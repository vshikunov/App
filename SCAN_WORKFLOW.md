# Scanning workflow

## One-object scan

1. Open the app.
2. Put the object on a table or stand.
3. Open **Setup** and set the crop volume in millimeters.
4. Aim at the middle of the object.
5. Tap **Set Center**.
6. Tap **Scan**.
7. Move around the object slowly. Keep the object still.
8. Tap **Stop**.
9. Tap **Export STL**.
10. Share the STL and CSV files.

## Tolerance setup

Open **Tolerances** and edit these dimensions:

- `bbox_x_mm` — width along the part X axis.
- `bbox_y_mm` — vertical height.
- `bbox_z_mm` — depth along the part Z axis.

The app uses the phone view direction and gravity when **Set Center** is tapped to define the part coordinate system.

## Better results

- Use matte, non-reflective surfaces.
- Use good lighting.
- Keep the part inside the crop volume.
- Avoid moving the object during scanning.
- Do not include the wall or table in the crop box unless you want it in the STL.
