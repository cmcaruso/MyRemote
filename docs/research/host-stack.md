# Research: which stack should the Host be built in?

Ticket: [#2](https://github.com/cmcaruso/MyRemote/issues/2) · Researched 2026-10-07 · Environment checked: macOS 26.6.2, Swift 6.4, Xcode 27.0, Node 24.11.1, Tailscale.app installed, **0 code-signing identities in the keychain**.

## Recommendation

**Build the Host Swift-native**, as one app bundle:

- SwiftUI `MenuBarExtra` plus `LSUIElement` for the menubar, and `SMAppService.mainApp` for the login item.
- **Hummingbird 2** (with `hummingbird-websocket`) for static Remote assets and the WebSocket command channel, bound to `127.0.0.1`.
- `CGEvent` for input.
- An `NSPanel` overlay for the Laser.
- Signing with **one stable, non-ad-hoc identity**, so the Accessibility grant survives rebuilds.

Use `tailscale serve --bg` for HTTPS to start with, and keep a fallback where the Host terminates TLS itself (see Risks).

Why:

1. **Every hard requirement is a first-party AppKit API in Swift.** The other stacks either reach these APIs through wrappers that are missing pieces, or bolt a Swift helper on anyway. The hard requirements are the login item, an overlay above full-screen apps on all Spaces, CGEvent injection, and media keys.
2. **One process gets one TCC identity.** Accessibility is granted to a single signed bundle, and nothing depends on TCC tracing "responsibility" from a child process back to its parent.
3. **It has the shortest input path.** A WebSocket frame becomes an in-process `CGEvent.post` call, with no IPC hop to a helper or native addon.
4. **The toolchain is already installed.** Xcode 27 and Swift 6.4 are there, and nothing else needs installing. Node 24 is still useful for building and testing the Remote's web assets.

## Comparison

| Criterion | Swift-native (AppKit/SwiftUI + Hummingbird) | Node/TS + Swift helper | Tauri 2 | Electron |
|---|---|---|---|---|
| **Input latency** (host side) | In-process `CGEvent.post` straight from the WS handler. Lowest. | WS in Node, then a native addon (nut.js) *or* IPC to the Swift helper. One extra hop if the helper does the input. | Rust handler, then a CGEvent crate (e.g. `enigo`/`core-graphics`). Comparable to Swift. | Node main process, then a native addon. **Electron has no OS-level input API**: `webContents.sendInputEvent` only targets its own page. |
| **Menubar** | `MenuBarExtra` (macOS 13+) plus `LSUIElement`. | Provided by the Swift helper (Node has no menubar). | Built-in tray icon. | `Tray` plus `app.dock.hide()`. |
| **Login item (SMAppService)** | `SMAppService.mainApp.register()` directly. | Only if the Swift helper is the bundle's main app. | **The autostart plugin does not use SMAppService.** It writes a `~/Library/LaunchAgents` plist or adds the item via AppleScript. | `app.setLoginItemSettings({type: 'mainAppService'})` wraps SMAppService. |
| **Laser overlay** (transparent, click-through, above full screen, all Spaces) | Full control: `NSPanel`, `ignoresMouseEvents`, `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]`, high window level. | Swift helper does it (same as Swift-native). | **Known gap.** Transparency needs `macOSPrivateApi`. Open bug [tauri#9557](https://github.com/tauri-apps/tauri/issues/9557): a window can't join other Spaces or draw over full-screen apps even with `alwaysOnTop` and `visibleOnAllWorkspaces`. | `transparent`, `setIgnoreMouseEvents`, `setAlwaysOnTop('screen-saver')`, `setVisibleOnAllWorkspaces(true, {visibleOnFullScreen: true})`. Workable, but it's a Chromium compositor layer for a dot. |
| **Accessibility (TCC) under self-signing** | One bundle, one designated requirement (DR). Stable if signed with a fixed identity. | **Two programs.** The grant has to reach Node through TCC's "responsible code" chain, which is fragile (see below). nut.js says it needs Accessibility **and Screen Recording** for "the executing application, e.g. your terminal". | One bundle. Same signing rules apply. | One bundle, but it contains Electron Framework and helpers, so signing has more parts. Has `systemPreferences.isTrustedAccessibilityClient()`. |
| **Static web assets + WS** | Hummingbird `FileMiddleware` plus `hummingbird-websocket` (2.27.0 / 2.8.0, Sept 2026, Swift 6 tools). Network.framework alone has WS but no HTTP server. | Trivial (Node `http`, `ws`, or Fastify). Best ecosystem. | Embedded webview assets are easy. An *external* HTTP/WS server for the phone is extra Rust (axum etc.). | Trivial (Node). |
| **Dev loop / tooling** | Xcode 27 or `xcodebuild` plus `swift test` on a core package. Swift 6 strict concurrency (AppKit is `@MainActor`) is a learning cost. | Two toolchains and two build artifacts, plus the packaging of Node inside the .app. | Rust toolchain (not installed) plus Node. | Node only, but heavy: ~200 MB bundle and a native-addon rebuild against the Electron ABI. |
| **Dependency risk** | Hummingbird (actively maintained, Swift Server Workgroup project). | **nut.js is no longer published to npm.** Prebuilt binaries need a paid subscription, or you build from source. Alternatives: robotjs forks. | Tauri plus `tauri-nspanel`-style community workarounds for the overlay. | Electron plus a native input addon (same nut.js/robotjs issue). |
| **Verdict** | **Recommended.** | Rejected: you need Swift anyway, plus two-process TCC and a nut.js licensing hassle. | Rejected: wrong login-item mechanism, and an open bug on exactly the overlay requirement. | Rejected: no native input, so it needs an addon anyway; heavy for a menubar utility. |

## Key facts and sources

### Login item
- `SMAppService` (macOS 13+) registers LoginItems, LaunchAgents and LaunchDaemons. `mainApp` is "an app service object that corresponds to the main application as a login item". For the main app, after `register()`, "the application launches on subsequent logins". `openSystemSettingsLoginItems()` and `status` are there for the approval UI. [SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice), [mainApp](https://developer.apple.com/documentation/servicemanagement/smappservice/mainapp), [register()](https://developer.apple.com/documentation/servicemanagement/smappservice/register())
- Electron's `setLoginItemSettings` `type` defaults to `mainAppService` and points to SMAppService. [Electron app API](https://www.electronjs.org/docs/latest/api/app)
- Tauri's `MacosLauncher` is either `LaunchAgent` ("installing a Launch Agent plist under `~/Library/LaunchAgents`") or `AppleScript`. It's not SMAppService. [plugins-workspace/autostart/src/lib.rs](https://github.com/tauri-apps/plugins-workspace/blob/v2/plugins/autostart/src/lib.rs)

### Menubar
- `MenuBarExtra` is SwiftUI on macOS 13+. Add `LSUIElement` so there's no Dock icon. [MenuBarExtra](https://developer.apple.com/documentation/swiftui/menubarextra)

### Overlay (Laser)
- The `NSWindow.CollectionBehavior` options that matter here:
  - `canJoinAllSpaces`: "The window can appear in all spaces."
  - `fullScreenAuxiliary`: "The window displays on the same space as the full screen window."
  - `stationary`: "Mission Control doesn't affect the window".
  - `ignoresCycle`.
  - `canJoinAllApplications` is a newer option for full screen and Stage Manager, and is mutually exclusive with `primary`/`auxiliary`.

  [CollectionBehavior](https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct)
- `ignoresMouseEvents`: "whether the window is transparent to mouse events". [ignoresMouseEvents](https://developer.apple.com/documentation/appkit/nswindow/ignoresmouseevents)
- Electron equivalents: `setVisibleOnAllWorkspaces` with `visibleOnFullScreen` ("visible above fullscreen windows"), `setIgnoreMouseEvents`, and the `screen-saver` level. [BrowserWindow](https://www.electronjs.org/docs/latest/api/browser-window)
- Tauri: `macOSPrivateApi` "Enables the transparent background API". There's an open bug that windows can't be drawn over full-screen apps on other Spaces ([#9557](https://github.com/tauri-apps/tauri/issues/9557), still OPEN; related [#11488](https://github.com/tauri-apps/tauri/issues/11488)). [Tauri config](https://v2.tauri.app/reference/config/)

### Input
- `CGEvent.post(tap:)` posts "into the event stream at a specified location". `CGPreflightPostEventAccess()` / `CGRequestPostEventAccess()` (macOS 10.15+) check for and request permission to post events. [post(tap:)](https://developer.apple.com/documentation/coregraphics/cgevent/post(tap:)), [CGRequestPostEventAccess](https://developer.apple.com/documentation/coregraphics/cgrequestposteventaccess())
- Electron's only synthetic-input API, `contents.sendInputEvent`, "Sends an input `event` to the page". It doesn't reach the OS. [webContents](https://www.electronjs.org/docs/latest/api/web-contents)
- nut.js: "still open source … you'll just have to build it from sources". "Pre-built packages are available for subscription plans" via a private registry. It needs Accessibility and Screen Recording for the executing app. [nut-tree/nut.js README](https://github.com/nut-tree/nut.js)

### TCC stability across rebuilds (applies to every stack)
- TN3127: macOS records an app's **designated requirement** in the privacy database and checks later versions against it. "Ad hoc signed code, called Sign to Run Locally by Xcode, has a DR but it's tied to that specific version of the code … macOS can't reliably track the identity of the code." That means an ad-hoc rebuild loses the Accessibility grant. [TN3127: Inside Code Signing: Requirements](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements)
- What to do: sign every build with the same identity and a fixed bundle ID. The DR then names the identifier plus the signer, so it doesn't change between builds. There are two options, since the keychain currently has none:
  - **(a)** An "Apple Development" certificate from a free Personal Team (sign into Xcode with an Apple ID).
  - **(b)** A self-signed code-signing certificate made in Keychain Access → Certificate Assistant. Check the result with `codesign -d -r- MyRemote.app`: it should show `identifier … and certificate leaf = H"…"`, not `cdhash`.
- Child processes: TCC attributes an operation to the *responsible code* by walking from child to parent. In Apple DTS's test that inheritance worked, but the forum thread exists because it failed for a Swift-parent / Python-child app. [Apple Developer Forums 805245](https://developer.apple.com/forums/thread/805245). This is the fragility the Node+helper design would take on.

### Serving and HTTPS
- Hummingbird 2.27.0 (2026-09-21) declares `swift-tools-version:6.2` and has `FileMiddleware` for static files. `hummingbird-websocket` 2.8.0 (2026-09-28) upgrades HTTP/1 to WebSocket, and its router lets middleware (e.g. a Pairing check) run on the upgrade request. [hummingbird](https://github.com/hummingbird-project/hummingbird), [hummingbird-websocket](https://github.com/hummingbird-project/hummingbird-websocket)
- Network.framework has `NWProtocolWebSocket` (macOS 10.15+). macOS 26 adds `NetworkListener` and a `WebSocket` protocol type for structured concurrency. There's no HTTP server or static-file layer, so you'd hand-roll HTTP. [NetworkListener](https://developer.apple.com/documentation/network/networklistener), [NWProtocolWebSocket](https://developer.apple.com/documentation/network/nwprotocolwebsocket)
- `tailscale serve` proxies tailnet-only HTTPS to a local port with automatically provisioned certs. With `--bg` it "runs persistently in the background" and resumes after reboot. You turn it off with `tailscale serve reset`. [Tailscale Serve](https://tailscale.com/kb/1312/serve), [serve CLI](https://tailscale.com/kb/1242/tailscale-serve)
- App Store or Standalone Tailscale CLI: `/Applications/Tailscale.app/Contents/MacOS/Tailscale` (Standalone can install `/usr/local/bin/tailscale`). Serving *files* needs the open-source variant, but proxying to a port works on all variants. [Tailscale CLI](https://tailscale.com/kb/1080/cli)

## Risks

1. **WebSocket through `tailscale serve` has open bugs:**
   - [#20882](https://github.com/tailscale/tailscale/issues/20882) (Aug 2026): WS upgrades are lost when the client negotiates HTTP/2. The reporter says browsers do this by default.
   - [#18827](https://github.com/tailscale/tailscale/issues/18827): WS drops every 10–40 s with code 1001.
   - [#18651](https://github.com/tailscale/tailscale/issues/18651): query params stripped on WS upgrade, reported via Funnel.

   Mitigation, which the Swift stack supports: fall back to `tailscale serve --tcp` passthrough, or have the Host terminate TLS itself (HummingbirdTLS / NIOSSL) with the cert from `tailscale cert`. The transport ticket should verify this against iOS Safari before committing.
2. **Signing setup is a prerequisite.** There are no identities in the keychain today. Without one, every rebuild re-prompts for Accessibility. Solve this in the walking-skeleton slice.
3. **The overlay needs a spike on macOS 26.** The full-screen and all-Spaces behaviour above comes from documented flags, but it hasn't been checked on this Mac (e.g. against Stage Manager or `canJoinAllApplications`). Do a 30-minute prototype early.
4. **Swift 6 strict concurrency.** Hummingbird handlers are async and off the main actor, while `NSPanel`/`CGEvent` work belongs on `@MainActor`. Design one clear hop, such as an `AsyncStream` of commands consumed on the main actor.
5. **Media/volume keys** need `NSEvent.otherEvent(.systemDefined, subtype 8)` posting or a CoreAudio volume API. Both are reachable from Swift. Their exact mechanics belong to the input-injection research.

## Open questions handed on
- Repo layout: an Xcode app target plus a local SwiftPM package for testable core logic (protocol decoding, Pairing), or SwiftPM plus a bundle/sign script. This is decided in the repo-layout/dev-loop ticket.
- Whether the Host or `tailscale serve` terminates TLS. This is decided in the transport ticket, given Risk 1.
