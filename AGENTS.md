# AGENTS.md — rules for an agent building an iOS app from this template

## Your loop
1. Edit `App/*.swift` (and `rust/` if used). Keep `project.yml` the single source of build truth.
2. `git push` to `main`. CI builds on `xcode-27`. Run `tools/ci <owner>/<repo>` — it waits for the run of *your* HEAD commit and prints only the failing step and `error:` lines.
3. On success, ask the user to tap **Update** in SideStore (one tap). Then verify with `tools/appctl ping` / `status` / `device`.
4. Never claim a feature works until you've exercised it through the control API or seen the user confirm it on screen.

## Verify API facts before writing code
Fast-moving Swift packages (MLX, swift-transformers, etc.) change names between minor versions. Before using a type or function:
- shallow-clone the dependency at the pinned version and `grep` the symbol, or read its examples repo;
- prefer copying patterns from the library's own example apps.
One CI round trip costs ~10 minutes; one grep costs seconds.

## Known pitfalls (each cost a CI round trip once)
- Xcode 27 ships the Metal compiler separately: CI must run `xcodebuild -downloadComponent MetalToolchain` before building anything with `.metal` sources (MLX does).
- Packages with Swift macros need `-skipMacroValidation` (and `-skipPackagePluginValidation`) in CI.
- Commit *all* changed files: `git add -A`. A workflow change left unstaged means CI runs the old workflow (or no run if the trigger paths didn't match).
- `SWIFT_VERSION` is "5.0" on purpose: Swift 6 mode turns every `[String: Any]` crossing an actor/`MainActor.run` boundary into a hard error. Return JSON `Data` (or an `@unchecked Sendable` box) across isolation boundaries instead.
- Verify Metal API names against the SDK (e.g. `MTLDevice.supportsBFloat16` does not exist). When in doubt, guard with `responds(to:)` or leave it out.
- The trigger `paths:` filter decides whether a push builds at all. Tooling-only pushes don't trigger builds by design.
- Don't add capabilities free teams can't have (push, iCloud, app groups, associated domains, Sign in with Apple) — re-signing fails or strips them.
- Loopback server: bind `127.0.0.1` explicitly (`requiredLocalEndpoint`), require a token, and add `NSLocalNetworkUsageDescription` anyway.
- The app is suspended when not in the foreground. Control-API calls only work while it's on screen (or within a short background window). Ask the user to keep it open during experiments, or add a `processing` background task for long jobs.
- `os_proc_available_memory()` is the number that matters for "how big a model fits", not physical RAM.

## Rust
- Build with `cargo build --release --target aarch64-apple-ios` (CI installs the target with `rustup target add aarch64-apple-ios`).
- Expose a C ABI (`#[no_mangle] extern "C"`), write `core.h`, add it via a bridging header. Return owned strings with a matching free function.
- GPU from Rust: `wgpu` (→ Metal) or `objc2-metal`. ML: `candle` (Metal backend), `burn`.

## Ask the human only for
Apple ID sign-in, taps on the phone (install/update/trust), copying the control token, and physical observations (screen, heat). Ask for one step at a time, with what "done" looks like.
