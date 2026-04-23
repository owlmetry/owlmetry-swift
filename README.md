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

### Xcode

`File` → `Add Package Dependencies…` → enter `https://github.com/owlmetry/owlmetry-swift.git`, choose `main` branch, add to your app target.

## Quickstart

```swift
import OwlMetry

Owl.configure(.init(
    clientKey: "owl_client_...",
    endpoint: URL(string: "https://ingest.owlmetry.com")!
))

Owl.log(.info, "app_launched")
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
