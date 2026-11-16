import Foundation

/// Launch arguments used by tests, screenshots and manual QA:
/// `-resetData` wipes the store, `-demo` seeds sample data, `-tab=N` selects
/// the initial tab/section, `-screen=name` deep-links a sub-screen.
public enum LaunchArguments {
    private static var args: [String] { ProcessInfo.processInfo.arguments }

    /// Combined single-token form: "-cfg=tab=2|month=1|screen=export".
    /// (Simulator launch passes one argv token reliably; several tokens may be dropped.)
    private static func cfgValue(_ key: String) -> String? {
        for arg in args where arg.hasPrefix("-cfg=") {
            for pair in arg.dropFirst("-cfg=".count).split(separator: "|") {
                let kv = pair.split(separator: "=", maxSplits: 1)
                if kv.count == 2 && kv[0] == key { return String(kv[1]) }
            }
        }
        return nil
    }

    public static var resetData: Bool { args.contains("-resetData") || cfgValue("reset") == "1" }
    public static var demo: Bool { args.contains("-demo") || cfgValue("demo") == "1" }

    public static var tab: Int? {
        if let v = cfgValue("tab") { return Int(v) }
        for arg in args where arg.hasPrefix("-tab=") {
            return Int(arg.dropFirst("-tab=".count))
        }
        return nil
    }

    public static var monthOffset: Int {
        if let v = cfgValue("month") { return Int(v) ?? 0 }
        for arg in args where arg.hasPrefix("-month=") {
            return Int(arg.dropFirst("-month=".count)) ?? 0
        }
        return 0
    }

    public static var screen: String? {
        if let v = cfgValue("screen") { return v }
        for arg in args where arg.hasPrefix("-screen=") {
            return String(arg.dropFirst("-screen=".count))
        }
        return nil
    }
}
