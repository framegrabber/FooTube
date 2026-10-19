import Foundation

public enum AppInfo {
    public static let name = "FooTube"
    /// The app's bundle ID (set per developer in Config/Signing.local.xcconfig); filter logs with
    /// `subsystem ENDSWITH ".FooTube"`.
    public static let logSubsystem = Bundle.main.bundleIdentifier ?? name
}
