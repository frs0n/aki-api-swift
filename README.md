# AkiAPI

A small Swift Package port of [`jgoralcz/aki-api`](https://github.com/jgoralcz/aki-api).

It wraps Akinator's web endpoints with async Swift APIs and has no third-party dependencies.

## Platforms

- macOS 12+
- iOS 15+
- tvOS 15+

## Install

Add this package in Xcode or SwiftPM:

```swift
.package(url: "https://github.com/frs0n/aki-api-swift.git", from: "0.1.0")
```

## Usage

```swift
import AkiAPI

let aki = Akinator(region: .en, childMode: false)
try await aki.start()

print(aki.question)
print(aki.answers)

switch try await aki.step(.yes) {
case .step(let step):
    print(step.question)
case .guess(let guess):
    print(guess.nameProposition)
}
```

## License

MIT. Original project copyright belongs to Joshua Goralczyk.
