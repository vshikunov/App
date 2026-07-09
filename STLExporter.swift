import Foundation

public enum STLExporter {
    public static func asciiSTL(mesh: TriangleMesh, name: String = "scan") -> String {
        let cleanName = sanitizeSolidName(name)
        var lines: [String] = []
        lines.reserveCapacity(mesh.faces.count * 7 + 2)
        lines.append("solid \(cleanName)")

        for face in mesh.faces {
            guard face.a >= 0, face.b >= 0, face.c >= 0,
                  face.a < mesh.vertices.count,
                  face.b < mesh.vertices.count,
                  face.c < mesh.vertices.count else {
                continue
            }

            let v0 = mesh.vertices[face.a]
            let v1 = mesh.vertices[face.b]
            let v2 = mesh.vertices[face.c]
            let normal = (v1 - v0).cross(v2 - v0).normalized()

            lines.append(String(format: "  facet normal %.9g %.9g %.9g", locale: Locale(identifier: "en_US_POSIX"), normal.x, normal.y, normal.z))
            lines.append("    outer loop")
            lines.append(vertexLine(v0))
            lines.append(vertexLine(v1))
            lines.append(vertexLine(v2))
            lines.append("    endloop")
            lines.append("  endfacet")
        }

        lines.append("endsolid \(cleanName)")
        return lines.joined(separator: "\n") + "\n"
    }

    public static func writeASCII(mesh: TriangleMesh, name: String = "scan", to url: URL) throws {
        let text = asciiSTL(mesh: mesh, name: name)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    private static func vertexLine(_ vertex: Vector3D) -> String {
        String(format: "      vertex %.9g %.9g %.9g", locale: Locale(identifier: "en_US_POSIX"), vertex.x, vertex.y, vertex.z)
    }

    private static func sanitizeSolidName(_ name: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-"))
        let scalars = name.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" }
        let value = String(scalars)
        return value.isEmpty ? "scan" : value
    }
}
