import Foundation

/// Launch arguments for the simulator screenshot job.
/// `-screenshotMode -screenshotScreen sleep` fills sample data and opens that screen.
/// Production launches never pass these arguments.
enum ScreenshotMode {
    static var isActive: Bool {
        ProcessInfo.processInfo.arguments.contains("-screenshotMode")
    }

    static var screen: String {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "-screenshotScreen"), index + 1 < args.count else { return "sleep" }
        return args[index + 1]
    }
}
