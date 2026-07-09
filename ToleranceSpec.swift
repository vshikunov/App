import Foundation

public struct ToleranceSpec: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var nominalMM: Double
    public var lowerToleranceMM: Double
    public var upperToleranceMM: Double
    public var enabled: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        nominalMM: Double,
        lowerToleranceMM: Double,
        upperToleranceMM: Double,
        enabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.nominalMM = nominalMM
        self.lowerToleranceMM = lowerToleranceMM
        self.upperToleranceMM = upperToleranceMM
        self.enabled = enabled
    }

    public var lowerLimitMM: Double { nominalMM + lowerToleranceMM }
    public var upperLimitMM: Double { nominalMM + upperToleranceMM }
}

public extension ToleranceSpec {
    static var defaultObjectSpecs: [ToleranceSpec] {
        [
            ToleranceSpec(name: "bbox_x_mm", nominalMM: 70.0, lowerToleranceMM: -1.0, upperToleranceMM: 1.0),
            ToleranceSpec(name: "bbox_y_mm", nominalMM: 110.0, lowerToleranceMM: -1.0, upperToleranceMM: 1.0),
            ToleranceSpec(name: "bbox_z_mm", nominalMM: 50.0, lowerToleranceMM: -1.0, upperToleranceMM: 1.0)
        ]
    }
}
