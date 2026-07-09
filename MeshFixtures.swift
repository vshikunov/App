import Foundation

public enum MeshFixtures {
    public static func makeBox(widthMM: Double, heightMM: Double, depthMM: Double) -> TriangleMesh {
        let x = widthMM / 2.0
        let y = heightMM / 2.0
        let z = depthMM / 2.0

        let vertices = [
            Vector3D(x: -x, y: -y, z: -z),
            Vector3D(x:  x, y: -y, z: -z),
            Vector3D(x:  x, y:  y, z: -z),
            Vector3D(x: -x, y:  y, z: -z),
            Vector3D(x: -x, y: -y, z:  z),
            Vector3D(x:  x, y: -y, z:  z),
            Vector3D(x:  x, y:  y, z:  z),
            Vector3D(x: -x, y:  y, z:  z)
        ]

        let faces = [
            TriangleFace(0, 2, 1), TriangleFace(0, 3, 2), // back
            TriangleFace(4, 5, 6), TriangleFace(4, 6, 7), // front
            TriangleFace(0, 1, 5), TriangleFace(0, 5, 4), // bottom
            TriangleFace(3, 6, 2), TriangleFace(3, 7, 6), // top
            TriangleFace(1, 2, 6), TriangleFace(1, 6, 5), // right
            TriangleFace(0, 4, 7), TriangleFace(0, 7, 3)  // left
        ]

        return TriangleMesh(vertices: vertices, faces: faces)
    }
}
