import Foundation

/// Lightweight debug logger gated by `--verbose`, `--debug`, or the `NK_DEBUG`
/// environment variable. Uses `@autoclosure` so expensive string formatting
/// (e.g. call-stack symbols or coordinate dumps) is skipped entirely during
/// normal runs.
func NKLog(_ message: @autoclosure () -> String) {
    if NKLogConfig.isEnabled {
        NSLog("%@", message())
    }
}

enum NKLogConfig {
    static let isEnabled: Bool = {
        CommandLine.arguments.contains("--verbose") ||
        CommandLine.arguments.contains("--debug") ||
        ProcessInfo.processInfo.environment["NK_DEBUG"] != nil
    }()
}
