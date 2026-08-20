import Foundation

/// Codemagic / Simulator listing shots pass `-AdPlayScreenshot` so system
/// permission sheets do not cover Play.
enum ScreenshotLaunch {
    static var isActive: Bool {
        ProcessInfo.processInfo.arguments.contains("-AdPlayScreenshot")
    }
}
