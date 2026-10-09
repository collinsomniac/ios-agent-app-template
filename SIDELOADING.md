# Sideloading a custom iOS app to this device — methodology

Written 2026-10-09 from a working setup: **iPhone 17 Pro Max (iPhone18,2), iOS 27.0**, no Mac, no paid
Apple Developer account. It records what worked, what failed, and the numbers that matter, so a future
agent can get from an idea to a measured result on the device in one sitting.

---

## 1. The two install paths

| path | how | trust cost | verdict |
|---|---|---|---|
| **A. Desktop, via `iloader`** | iTunes/Apple Devices provides the USB driver → iloader signs in with your Apple ID against Apple, signs + installs over USB | none beyond your own Apple ID | **preferred** |
| B. On-phone, via SideInstaller | installs SideStore using a *leaked enterprise certificate*, plus a DNS profile the site supplies | that certificate + a third-party app holding your Apple ID + a DNS server that **blocks `ocsp.apple.com`/`crl.apple.com`** (verified by querying it; this is what keeps revoked certs working) | last resort |

Why A wins beyond trust: the installer inside `iloader` (`isideload`) explicitly enables the
`INCREASED_MEMORY_LIMIT` capability on the App ID, so the app can request ~6 GB instead of ~3.3 GB.
SideStore's own on-device signer **drops** that entitlement (SideStore issue #1616, fix PR SideSign#4 open).

After either path, SideStore (re-signing with your free Apple ID) installs and refreshes apps on-device.

## 2. Free-account limits (verified)

- Signature expires **7 days** after signing; SideStore refreshes automatically in the background.
- **3 sideloaded apps** at a time; roughly **10 new App IDs** per rolling week.
- Unavailable to free teams: push notifications, iCloud, Sign in with Apple, associated domains,
  app groups across teams, `aps-environment`. Don't request them or signing fails.
- `com.apple.developer.kernel.increased-memory-limit` **is** grantable to free teams (confirmed by Apple
  docs + the iloader engine enabling it) — but only if the signer asks for it.

## 3. Build without a Mac

```
GitHub Actions (runs-on: xcode-27)            # iOS 27 SDK, Xcode 27, free for public repos
  xcodebuild -downloadComponent MetalToolchain # REQUIRED on Xcode 27 before building .metal sources
  xcodegen generate                            # project.yml is the source of truth
  xcodebuild -project X.xcodeproj -scheme X -sdk iphoneos -destination generic/platform=iOS \
      -skipMacroValidation -skipPackagePluginValidation \
      -archivePath build/X.xcarchive archive \
      CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=""
  # package: strip any existing signature, ad-hoc sign WITH entitlements, zip Payload/, publish release
```

Hard-won details:
1. **Xcode 27 does not bundle the Metal compiler**; MLX and any `.metal` source fail with
   `cannot execute tool 'metal' due to missing Metal Toolchain`. Download it in CI.
2. **Ad-hoc sign with entitlements before publishing**:
   `codesign -f -s - --entitlements App.entitlements App.app`. SideStore/AltStore read the *requested*
   entitlements from that signature when re-signing; an unsigned binary requests nothing and the
   entitlement silently never lands.
3. **`SWIFT_VERSION: "5.0"`** unless you want to satisfy Swift 6 strict concurrency: `[String: Any]`
   crossing an actor boundary is a hard error in Swift 6 language mode (and `MainActor.run` returning
   one too). Return JSON `Data` or an `@unchecked Sendable` box instead.
4. Verify API names against the SDK: `MTLDevice.supportsBFloat16` does not exist. When unsure, pin the
   package version and grep its source.
5. `git add -A`. A workflow edit left unstaged means CI runs the old workflow (or none, if the trigger
   `paths:` filter didn't match). Cost: an hour, once.

## 4. Loading (publishing to SideStore)

- CI publishes the `.ipa` plus a **SideStore source JSON** to a GitHub release; a stable URL is
  `https://github.com/<owner>/<repo>/releases/latest/download/sidestore-source.json`.
- **The version inside the IPA must equal the version string in the source JSON.** SideStore refuses with
  "The downloaded version does not match the version specified by the source. Expected 0.1.0.4, Found 0.1.0".
  Fix: set `CFBundleShortVersionString` to a value that increments per build (e.g. `0.1.<run_number>`) and
  write that same string into the source JSON.
- Bump `CFBundleVersion` too, so SideStore orders updates correctly.
- After publishing a new build, **pull-to-refresh the source in SideStore** before tapping Get/Update.

## 5. Device facts that shape development (measured, iPhone18,2 / iOS 27.0)

| what | value | why it matters |
|---|---|---|
| physical RAM | 12.26 GB | headline number; not what you get |
| memory available to the process | **3.51 GB** without the entitlement (measured) | the real budget for weights + cache + activations |
| `recommendedMaxWorkingSetSize` (Metal) | 8.59 GB | GPU-side suggestion |
| `maxBufferLength` | 6.44 GB | largest single Metal buffer |
| GPU | Apple A19 Pro GPU, families `apple7/8/9/metal3/**apple10**`, unified memory, raytracing | target `apple10` for new kernels |
| GPU peak bandwidth (chip spec) | 76.8 GB/s (12 GB LPDDR5X-9600) | ceiling for decode speed |
| **measured weight-streaming** | **39 GB/s**, equal for 1/2/4 tokens per weight read, 28.5 GB/s at 8; identical for thread-per-row and simdgroup kernels | ~51% of peak; batch ≤4 is nearly free (the WaveFront premise) |
| CPU | 2 P-cores + 4 E-cores; P L2 16 MB, E L2 6 MB; L1D 64 KB; 128 B cache line; 16 KB pages | size tiny kernels to L2; align to 128 B |
| browser (Safari/WebKit + WebGPU) | 42 GB/s, `timestamp-query` present, no subgroups, 1 GiB buffers, ~1.5 GB per tab | good for portable experiments, memory-capped |
| iSH (emulated Linux) | 0.36 GB/s on the same matvec | orchestration only — never compute |

## 6. Optimal primitives (what to reach for)

- **App + UI + GPU kernels: Swift / SwiftUI + Metal (MSL).** Native is the only place you get the full
  memory budget, `apple10` GPU features, unified memory, and no per-tab cap.
- **ML: MLX Swift** (`mlx-swift` + `mlx-swift-lm`). On an iPhone 17 Pro, MLX measured ~179 tok/s on
  Qwen3-0.6B-4bit vs ~122 (LiteRT-LM) and 117–193 (Apple Core AI), 38 (legacy Core ML). It also supports
  `MTLCompileOptions`-free runtime kernel compilation (`makeLibrary(source:)`), which is how you hot-swap
  GPU experiments without a rebuild.
- **Rust: yes, for compute-heavy, allocation-heavy inner loops**, built as a `staticlib` for
  `aarch64-apple-ios` and called from Swift through a C header (verified working in CI end-to-end).
  GPU from Rust: `wgpu` (→ Metal) or `candle`. **Go: no** — no serious GPU/ML story on iOS.
- **No JIT**: iOS forbids `mprotect(PROT_EXEC)` for third-party apps. This rules out runtimes that need
  JIT (e.g. most JS engines outside the system WebView, some emulators). Interpreters (iSH) work but are
  ~100× slower. Metal shader compilation is unaffected because shaders are data to the GPU driver.
- **WebGPU/WASM**: portable and fine for substrate measurement, but capped by tab memory and missing
  subgroups. Use it to prototype kernels; move to Metal to ship.

## 7. The loop an agent should run

1. Edit code → `git push` → `tools/ci <owner>/<repo>` waits for *your* commit's run and prints only the
   failing step and `error:` lines. (~5 min; SwiftPM dependency resolution dominates the first build.)
2. Publish → the user taps **Update** in SideStore (one tap), or `iloader` re-installs over USB.
3. Drive the app through its **loopback JSON API** (`tools/appctl` / `tools/ll`), and verify on the device.

**The constraint that shapes everything: an iOS app is suspended when it is not on screen.** GPU work
cannot run in the background. Cross-app loopback *does* work on this device (verified: another process
reached a server inside iSH on 127.0.0.1), but the target app must be in the foreground to answer.
So the correct pattern is **job-based**, not interactive:

```
agent writes a job spec  ──▶  app (foreground) runs the whole battery, appends JSONL results
       ▲                                     │
       └──── agent reads results later ◀──────┘   (from app storage, or POSTed to the desktop over the tailnet)
```

Interactive back-and-forth only works while the app is on screen — useful for smoke tests, hopeless for
a 20-minute benchmark battery.

Security: keep the control server bound to **loopback** by default. Binding it to the tailnet interface
gives remote access; if you do that, keep the token check, and treat the tailnet as the trust boundary.
