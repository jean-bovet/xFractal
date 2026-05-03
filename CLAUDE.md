# xFractal — working notes for Claude

## Use TDD by default

For any change that touches non-trivial logic, follow red → green → refactor:

1. **Red.** Write a failing test in `Tests/` that captures the desired behavior. Run the test target and confirm it fails for the right reason.
2. **Green.** Write the smallest production-code change that makes the new test pass. Don't generalize ahead of the test.
3. **Refactor.** Once green, clean up — extract helpers, simplify, dedupe — keeping the suite green between each step.

When fixing a bug, the failing test must reproduce the bug *before* the fix is applied. When a behavior is hard to express as a test (UI gestures, Metal rendering, Sparkle), say so explicitly and fall back to manual verification — but check first that the underlying logic isn't actually pure math that *could* be lifted into `FractalMath.swift` and tested.

## Where things live

- **Pure logic** (math, state transitions, journal coalescing, double-float split, Mandelbrot kernel) → `xFractal/FractalMath.swift` or `xFractal/FractalState.swift`. Always testable.
- **Tests** → `Tests/*.swift`. Bundled into the `xFractalTests` macOS unit-test target.
- **SwiftUI views, gesture wiring, Metal pipeline glue, Sparkle integration** → not unit-tested. Cover the math the gestures use; verify the wiring manually.

## Running the tests

```sh
xcodebuild test -project xFractal.xcodeproj -scheme xFractal -configuration Debug
```

The `xFractal` scheme's test action runs `xFractalTests`. Tests must pass before any commit.

## Project regeneration

The `*.xcodeproj` is generated from `project.yml` by XcodeGen and is gitignored. After editing `project.yml`, run `xcodegen generate`. If Xcode applies new build settings (e.g. "Update to Recommended Settings"), bake them into `project.yml` so they survive regeneration.

## Platforms

Two app targets share the `xFractal/` source tree: `xFractal` (macOS, with Sparkle) and `xFractal-iOS` (iPhone/iPad, no Sparkle). Use `#if os(macOS)` / `#if os(iOS)` for platform-specific UI; keep math platform-agnostic.
