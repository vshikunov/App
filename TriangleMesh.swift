import Foundation

public struct TriangleFace: Codable, Hashable, Sendable {
    public var a: Int
    public var b: Int
    public var c: Int

    public init(_ a: Int, _ b: Int, _ c: Int) {
        self.a = a
        self.b = b
        self.c = c
    }
}

public struct BoundingBox: Codable, Hashable, Sendable {
    public var min: Vector3D
    public var max: Vector3D

    public init(min: Vector3D, max: Vector3D) {
        self.min = min
        self.max = max
    }

    public var size: Vector3D {
        Vector3D(
            x: max.x - min.x,
            y: max.y - min.y,
            z: max.z - min.z
        )
    }

    public var center: Vector3D {
        Vector3D(
            x: (min.x + max.x) / 2.0,
            y: (min.y + max.y) / 2.0,
            z: (min.z + max.z) / 2.0
        )
    }
}

public struct TriangleMesh: Codable, Hashable, Sendable {
    public var vertices: [Vector3D]
    public var faces: [TriangleFace]

    public init(vertices: [Vector3D] = [], faces: [TriangleFace] = []) {
        self.vertices = vertices
        self.faces = faces
    }

    public var isEmpty: Bool {
        vertices.isEmpty || faces.isEmpty
    }

    public mutating func append(vertices newVertices: [Vector3D], faces newFaces: [TriangleFace]) {
        let offset = vertices.count
        vertices.append(contentsOf: newVertices)
        faces.append(contentsOf: newFaces.map { TriangleFace($0.a + offset, $0.b + offset, $0.c + offset) })
    }


    public func scaled(by factor: Double) -> TriangleMesh {
        TriangleMesh(
            vertices: vertices.map { Vector3D(x: $0.x * factor, y: $0.y * factor, z: $0.z * factor) },
            faces: faces
        )
    }

    public func boundingBox() -> BoundingBox? {
        guard let first = vertices.first else { return nil }
        var minX = first.x
        var minY = first.y
        var minZ = first.z
        var maxX = first.x
        var maxY = first.y
        var maxZ = first.z

        for vertex in vertices.dropFirst() {
            minX = Swift.min(minX, vertex.x)
            minY = Swift.min(minY, vertex.y)
            minZ = Swift.min(minZ, vertex.z)
            maxX = Swift.max(maxX, vertex.x)
            maxY = Swift.max(maxY, vertex.y)
            maxZ = Swift.max(maxZ, vertex.z)
        }

        return BoundingBox(
            min: Vector3D(x: minX, y: minY, z: minZ),
            max: Vector3D(x: maxX, y: maxY, z: maxZ)
        )
    }

    public func validFaceCount() -> Int {
        faces.filter { face in
            face.a >= 0 && face.b >= 0 && face.c >= 0 &&
            face.a < vertices.count && face.b < vertices.count && face.c < vertices.count
        }.count
    }
}
