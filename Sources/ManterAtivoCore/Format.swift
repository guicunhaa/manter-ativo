import Foundation

public enum PTFormat {
    public static func bytes(_ value: UInt64) -> String {
        let clamped = value > UInt64(Int64.max) ? Int64.max : Int64(value)
        return bytes(clamped)
    }

    public static func bytes(_ value: Int64) -> String {
        value.formatted(.byteCount(style: .memory, spellsOutZero: false))
    }

    public static func percent(_ value: Double, digits: Int = 0) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "pt_BR")
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = digits
        formatter.maximumFractionDigits = digits
        let number = formatter.string(from: NSNumber(value: value)) ?? String(format: "%.0f", value)
        return number + "%"
    }

    public static func decimal(_ value: Double, digits: Int = 1) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "pt_BR")
        formatter.minimumFractionDigits = digits
        formatter.maximumFractionDigits = digits
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    public static func mAh(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "pt_BR")
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        let number = formatter.string(from: NSNumber(value: value)) ?? "\(value)"
        return number + " mAh"
    }

    public static func watts(fromMilliWatts value: Int) -> String {
        decimal(Double(value) / 1000, digits: 1) + " W"
    }
}

public enum MenuTitle {
    public static func short(_ title: String, limit: Int = 30) -> String {
        if title.count <= limit { return title }
        let keep = max(0, limit - 1)
        return String(title.prefix(keep)) + "…"
    }
}
