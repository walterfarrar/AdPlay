import AppTrackingTransparency
import Foundation

/// Requests App Tracking Transparency permission once before ad SDKs start.
/// Required when App Store Connect declares data used to track the user.
enum AppTracking {
    private static var requestTask: Task<ATTrackingManager.AuthorizationStatus, Never>?

    /// Shows the system ATT prompt if status is `.notDetermined`. Concurrent callers share one request.
    @MainActor
    @discardableResult
    static func requestIfNeeded() async -> ATTrackingManager.AuthorizationStatus {
        let current = ATTrackingManager.trackingAuthorizationStatus
        if current != .notDetermined {
            return current
        }
        if let requestTask {
            return await requestTask.value
        }
        let task = Task { @MainActor in
            // ATT requires an active scene; brief yield so the first frame can present.
            await Task.yield()
            return await withCheckedContinuation { (cont: CheckedContinuation<ATTrackingManager.AuthorizationStatus, Never>) in
                ATTrackingManager.requestTrackingAuthorization { status in
                    cont.resume(returning: status)
                }
            }
        }
        requestTask = task
        let status = await task.value
        requestTask = nil
        return status
    }
}
