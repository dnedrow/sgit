import Foundation

/// Lightweight ANSI terminal styling and output helpers.
enum Terminal {
    /// Whether ANSI colors should be emitted (disabled when not a TTY or NO_COLOR is set).
    static let colorsEnabled: Bool = {
        if ProcessInfo.processInfo.environment["NO_COLOR"] != nil { return false }
        return isatty(fileno(stdout)) == 1
    }()

    enum Style: String {
        case reset = "\u{001B}[0m"
        case bold = "\u{001B}[1m"
        case dim = "\u{001B}[2m"
        case red = "\u{001B}[31m"
        case green = "\u{001B}[32m"
        case yellow = "\u{001B}[33m"
        case blue = "\u{001B}[34m"
        case magenta = "\u{001B}[35m"
        case cyan = "\u{001B}[36m"
    }

    static func style(_ text: String, _ styles: Style...) -> String {
        guard colorsEnabled, !styles.isEmpty else { return text }
        let prefix = styles.map(\.rawValue).joined()
        return prefix + text + Style.reset.rawValue
    }

    static func print(_ text: String = "") {
        Swift.print(text)
    }

    /// Prints an error to standard error, prefixed and colored red.
    static func error(_ text: String) {
        let prefix = style("error:", .bold, .red)
        FileHandle.standardError.write(Data("\(prefix) \(text)\n".utf8))
    }

    static func warning(_ text: String) {
        let prefix = style("warning:", .bold, .yellow)
        Swift.print("\(prefix) \(text)")
    }
}
