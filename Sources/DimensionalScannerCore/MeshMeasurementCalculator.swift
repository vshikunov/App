import Foundation

public struct MeshMeasurement: Codable, Hashable, Identifiable, Sendable {
    public var id: String { name }
    public var name: String
    public var value: Double
    public var unit: String

    public init(name: String, value: Double, unit: String) {
        self.name = name
        self.value = value
        self.unit = unit
    }
}

public enum MeshMeasurementCalculator {
    public static func measurements(for mesh: TriangleMesh) -> [MeshMeasurement] {
        var output: [MeshMeasurement] = [
            MeshMeasurement(name: "vertex_count", value: Double(mesh.vertices.count), unit: "count"),
            MeshMeasurement(name: "triangle_count", value: Double(mesh.validFaceCount()), unit: "count")
        ]

        if let box = mesh.boundingBox() {
            output.append(contentsOf: [
                MeshMeasurement(name: "bbox_x_mm", value: box.size.x, unit: "mm"),
                MeshMeasurement(name: "bbox_y_mm", value: box.size.y, unit: "mm"),
                MeshMeasurement(name: "bbox_z_mm", value: box.size.z, unit: "mm")
            ])
        }

        return output
    }

    public static func dictionary(for mesh: TriangleMesh) -> [String: Double] {
        Dictionary(uniqueKeysWithValues: measurements(for: mesh).map { ($0.name, $0.value) })
    }
}
