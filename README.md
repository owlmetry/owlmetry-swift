# OwlMetry Swift SDK

Native Swift SDK for iOS, iPadOS, and macOS — event logging, structured metrics, funnels, identity, A/B experiments, screen tracking, and Apple Search Ads attribution capture. Zero external runtime dependencies.

Part of the [OwlMetry](https://owlmetry.com) self-hosted metrics platform.

## Install

### Package.swift

```swift
dependencies: [
    .package(url: "https://github.com/owlmetry/owlmetry-swift.git", branch: "main"),
]
```

Add `OwlMetry` to your target's `dependencies`.

> For stable releases, pin to a version instead: `.package(url: "…", from: "X.Y.Z")`. See [releases](https://github.com/owlmetry/owlmetry-swift/releases/latest) for the latest.

### Xcode

`File` → `Add Package Dependencies…` → enter `https://github.com/owlmetry/owlmetry-swift.git`, choose `main` branch (or a specific version), add to your app target.

## Quickstart

```swift
import OwlMetry

try Owl.configure(
    endpoint: "https://ingest.owlmetry.com",
    apiKey: "owl_client_..."
)

Owl.info("app_launched")
```

Call `configure` once at app launch (e.g. from your `App` init). It throws on invalid input. For the full configuration options (attribution, network tracking, compression, offline queue) see the [setup guide](https://owlmetry.com/docs/sdks/swift).

## Examples

### Logging

```swift
Owl.info("feed_loaded", screenName: "Feed")
Owl.warn("cache_miss", attributes: ["key": "user_profile"])
Owl.error("upload_failed", attributes: ["reason": "timeout"])
```

### Identify a user

```swift
Owl.setUser("user_12345")
Owl.setUserProperties(["plan": "premium"])
```

### Measure an operation

```swift
let op = Owl.startOperation("photo_upload", attributes: ["format": "heic"])
// … do work …
op.complete(attributes: ["size_kb": "512"])
// or op.fail(attributes: ["reason": "network"])
```

### Record a funnel step

```swift
Owl.step("welcome-screen")
Owl.step("create-account")
Owl.step("first-post")
```

Full documentation: **[owlmetry.com/docs/sdks/swift](https://owlmetry.com/docs/sdks/swift)**

## Testing

Unit tests run self-contained:

```bash
swift test --skip SDKIntegrationTests --skip AppleSearchAdsAttributionTests
```

Integration tests require the OwlMetry server running on `http://127.0.0.1:4111`. See the [main repo](https://github.com/owlmetry/owlmetry) for running the server locally; then:

```bash
OWLMETRY_TEST_ENDPOINT=http://127.0.0.1:4111 \
    swift test --filter "(SDKIntegrationTests|AppleSearchAdsAttributionTests)"
```

## Related repos

- **[owlmetry/owlmetry](https://github.com/owlmetry/owlmetry)** — server, dashboard, CLI, Node SDK, documentation.

## License

MIT. See [LICENSE](./LICENSE).
