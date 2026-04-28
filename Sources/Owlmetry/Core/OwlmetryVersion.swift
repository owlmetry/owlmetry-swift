import Foundation

/// Owlmetry SDK identification and version. The `current` value is bumped by
/// the release workflow before tagging — see `.github/workflows/release.yml`.
public enum OwlmetryVersion {
    public static let name = "owlmetry-swift"
    public static let current = "0.2.1"
}
