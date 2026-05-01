import Foundation

/// Owlmetry SDK identification and version. The `current` value is bumped by
/// the release workflow before tagging — see `.github/workflows/release.yml`.
public enum OwlmetryVersion {
    /// SDK identifier sent on every event as `sdk_name`.
    public static let name = "owlmetry-swift"
    /// Semantic version of this SDK build, sent on every event as `sdk_version`.
    public static let current = "1.0.0"
}
