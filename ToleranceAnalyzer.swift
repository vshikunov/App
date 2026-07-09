import Foundation

public enum ToleranceStatus: String, Codable, Hashable, Sendable {
    case pass = "PASS"
    case failLow = "FAIL_LOW"
    case failHigh = "FAIL_HIGH"
    case missing = "MISSING"
}

public struct ToleranceResult: Codable, Hashable, Identifiable, Sendable {
    public var id: String { name }
    public var name: String
    public var measuredMM: Double?
    public var nominalMM: Double
    public var lowerLimitMM: Double
    public var upperLimitMM: Double
    public var errorMM: Double?
    public var status: ToleranceStatus

    public init(
        name: String,
        measuredMM: Double?,
        nominalMM: Double,
        lowerLimitMM: Double,
        upperLimitMM: Double,
        errorMM: Double?,
        status: ToleranceStatus
    ) {
        self.name = name
        self.measuredMM = measuredMM
        self.nominalMM = nominalMM
        self.lowerLimitMM = lowerLimitMM
        self.upperLimitMM = upperLimitMM
        self.errorMM = errorMM
        self.status = status
    }
}

public enum ToleranceAnalyzer {
    public static func analyze(measurements: [String: Double], specs: [ToleranceSpec]) -> [ToleranceResult] {
        specs.filter(\.enabled).map { spec in
            guard let measured = measurements[spec.name] else {
                return ToleranceResult(
                    name: spec.name,
                    measuredMM: nil,
                    nominalMM: spec.nominalMM,
                    lowerLimitMM: spec.lowerLimitMM,
                    upperLimitMM: spec.upperLimitMM,
                    errorMM: nil,
                    status: .missing
                )
            }

            let status: ToleranceStatus
            if measured < spec.lowerLimitMM {
                status = .failLow
            } else if measured > spec.upperLimitMM {
                status = .failHigh
            } else {
                status = .pass
            }

            return ToleranceResult(
                name: spec.name,
                measuredMM: measured,
                nominalMM: spec.nominalMM,
                lowerLimitMM: spec.lowerLimitMM,
                upperLimitMM: spec.upperLimitMM,
                errorMM: measured - spec.nominalMM,
                status: status
            )
        }
    }
}
