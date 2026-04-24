# OwlMetry Swift SDK

[![Tests](https://github.com/owlmetry/owlmetry-swift/actions/workflows/test.yml/badge.svg)](https://github.com/owlmetry/owlmetry-swift/actions/workflows/test.yml)
[![Release](https://img.shields.io/github/v/release/owlmetry/owlmetry-swift?display_name=tag&sort=semver)](https://github.com/owlmetry/owlmetry-swift/releases/latest)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](./LICENSE)
[![Platforms](https://img.shields.io/badge/platforms-iOS%2016%2B%20%7C%20macOS%2013%2B-lightgrey)](./Package.swift)

Native Swift SDK for iOS, iPadOS, and macOS — event logging, structured metrics, funnels, identity, A/B experiments, screen tracking, and Apple Search Ads attribution capture. Zero external runtime dependencies.

Part of the [OwlMetry](https://owlmetry.com) self-hosted metrics platform.

**Full setup guide & API reference: [owlmetry.com/docs/sdks/swift](https://owlmetry.com/docs/sdks/swift)**

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

Call `configure` once at app launch (e.g. from your `App` init). It throws on invalid input.

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
