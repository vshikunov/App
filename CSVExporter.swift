import Foundation

public enum CSVExporter {
    public static func toleranceReportCSV(results: [ToleranceResult]) -> String {
        var lines = ["name,measured_mm,nominal_mm,lower_limit_mm,upper_limit_mm,error_mm,status"]
        for result in results {
            let measured = numberOrBlank(result.measuredMM)
            let error = numberOrBlank(result.errorMM)
            lines.append([
                escape(result.name),
                measured,
                format(result.nominalMM),
                format(result.lowerLimitMM),
                format(result.upperLimitMM),
                error,
                result.status.rawValue
            ].joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    public static func measurementsCSV(measurements: [MeshMeasurement]) -> String {
        var lines = ["name,value,unit"]
        for item in measurements {
            lines.append([escape(item.name), format(item.value), escape(item.unit)].joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func numberOrBlank(_ value: Double?) -> String {
        guard let value else { return "" }
        return format(value)
    }

    private static func format(_ value: Double) -> String {
        String(format: "%.6f", locale: Locale(identifier: "en_US_POSIX"), value)
    }

    private static func escape(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return value
    }
}
