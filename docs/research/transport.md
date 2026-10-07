# Research: how the Remote talks to the Host over Tailscale

Resolves ticket #3. Researched 2026-10-07 against Tailscale docs and source, MDN browser-compat-data, WebKit and Apple docs. Claims carry a source tag like **[S3]**; the source list is at the bottom. Anything marked *unverified* still needs a quick on-device check.

## Recommendation (TL;DR)

1. **Transport: one WebSocket (`wss://`) carrying small messages, with the Remote coalescing pointer deltas once per animation frame. No WebRTC.**
2. **HTTPS: use `tailscale serve --bg` in front of a Host server that listens only on `127.0.0.1`.** The Host never deals with certificates. It does not need the Tailscale CLI at runtime: serve is configured once and comes back by itself after reboots.
3. **Exposure: there are three layers.** (a) The Host binds to loopback only, so serve is the only way in from the tailnet. (b) Optionally, a tailnet grant lets only the iPhone reach the Mac's :443. (c) The Pairing token is checked on every HTTP request and on the WebSocket upgrade. The `Tailscale-User-*` headers name the *user*, not the *device*, so on their own they can't tell "my phone" apart from "my other laptop". They are defence in depth, not authorization.
4. **Pairing token: an `HttpOnly; Secure; SameSite=Strict` cookie set by the Host.** Pairing must happen *inside the Home Screen web app*, because on iOS its storage is separate from Safari's.

## 1. Transport: WebSocket vs WebRTC DataChannel

### What the network underneath looks like

- On a **direct** tailnet path, all traffic is WireGuard over UDP, peer to peer **[S5]**. A WebSocket's TCP runs *inside* that tunnel. TCP head-of-line blocking only hurts when a packet is lost, and on a home LAN, or Wi-Fi to the Mac, that is rare.
- On a **DERP-relayed** path, Tailscale relays "use HTTPS streams" **[S6]**. DERP servers "have limited quality of service … generally slower than direct connections" **[S5]**. So on a relayed path every packet already travels over a TCP stream to the relay. An unordered, unreliable DataChannel **gains nothing there**: the loss recovery and ordering happen underneath it anyway.
- Connections start on DERP and move to direct once NAT traversal succeeds. `tailscale ping` / `tailscale status` show which path is in use **[S5]**.

### Why not WebRTC

- iOS Safari does support `RTCDataChannel` with `ordered` and `maxRetransmits` (Safari 11+) **[S11]**. So the obstacle isn't browser support. The obstacles are elsewhere:
  - `tailscale serve` proxies HTTP(S) and TCP only. Its flags are `--http`, `--https`, `--tcp` and `--tls-terminated-tcp`, and there is no UDP mode **[S2]**. WebRTC would need its own ICE/UDP path to the Mac's tailnet IP, outside serve, and that loses the identity headers and the loopback-only binding.
  - A native macOS Host would need a WebRTC stack (libwebrtc or similar) plus a signalling channel, and signalling would be a WebSocket anyway.
  - The latency benefit only exists on lossy direct paths, which are uncommon for a phone on the same Wi-Fi as the Mac. On DERP the benefit is zero (see above).
- **Verdict:** use WebSocket. Measure before reconsidering. Run `tailscale ping <mac>` to confirm the path is direct, and log round-trip times with an echo message.

### Message rate and coalescing (the part that actually sets latency)

- **Send relative deltas, never absolute positions.** Deltas can be added together, so dropping or merging frames loses nothing.
- **Coalesce on `requestAnimationFrame`.** Add up `dx/dy` (and scroll) from pointer events between frames, then send at most one `move` per frame. That is about 60 Hz, or up to 120 Hz on ProMotion. iOS Safari has `PointerEvent.getCoalescedEvents()` / `getPredictedEvents()` from 18.2 **[S11]**. The total delta is the same with or without them, so they are optional.
- **Backpressure:** if `ws.bufferedAmount > 0` at frame time, keep adding to the pending delta and don't send. This stops a stale queue from building up behind a TCP stall: the cursor jumps once instead of replaying old motion.
- **Discrete events** (clicks, keys, media keys, slide next/prev) are sent immediately and never merged. Ordering matters for them, and TCP gives it for free.
- **Laser**: send orientation as the latest absolute value (last one wins) at frame rate, not as deltas. The Host smooths it.
- Keep messages tiny: compact JSON is fine at these rates, and a binary format is optional. Turn on `TCP_NODELAY` on any Host socket you own. Serve's proxy is Go, and Go sets no-delay by default.

### WebSockets through `tailscale serve`

The serve docs don't mention WebSockets **[S1][S2]**. The source does settle it: serve's HTTP proxy is Go's `httputil.ReverseProxy` **[S3]**, and that type documents "Upgrade requests (RFC 9110, section 7.8) are forwarded" **[S4]**. **WebSockets therefore pass through serve.** One caveat from the same code: upgrades fail on "non-HTTP/1 connection" requests **[S4]**. Browsers open WebSockets over HTTP/1.1 by default, so in practice this should not matter. *Unverified on iOS. Check this in the first spike.*

## 2. HTTPS: `tailscale serve` vs `tailscale cert`

HTTPS is mandatory: on a non-loopback host, plain `http://` is not a secure context **[S12]**, and motion permission and Wake Lock both need one (section 4).

| | `tailscale serve --bg` → `http://127.0.0.1:PORT` | Host terminates TLS with `tailscale cert` |
|---|---|---|
| Certificate | Provisioned automatically for `<mac>.<tailnet>.ts.net` **[S1]**. Renewal is handled because no files are handed off **[S7]** | Let's Encrypt, 90-day expiry. "You are responsible for renewing" **[S7][S8]** |
| CLI needed at runtime? | **No.** With `--bg` it "runs persistently … When you reboot the device … Serve automatically resumes" **[S2]** | **Yes**, every ~60–90 days, to renew and reload |
| Identity headers | Yes: `Tailscale-User-Login`, `-Name`, `-Profile-Pic` **[S1][S3]** | No. The Host would have to call whois itself |
| Host binds to | `127.0.0.1` only (serve only proxies to `http://127.0.0.1`) **[S2]** | The tailnet interface/IP, which the Host has to discover and track |
| Host code | Plain HTTP + WS server (for example `NWListener` + `NWProtocolWebSocket`, macOS 10.15+ **[S13]**) | The same, plus TLS config and cert reload |

**Choose serve.** It is a one-time setup step that the Host can show as instructions or a copy-paste command:

```sh
# once, on the Mac (App Store variant path shown; standalone variant can install /usr/local/bin/tailscale) [S9]
/Applications/Tailscale.app/Contents/MacOS/Tailscale serve --bg 127.0.0.1:<PORT>
```

Prerequisites: MagicDNS on, and **Enable HTTPS** in the admin console's DNS page **[S7]**. Privacy note: the machine name is published in the public Certificate Transparency logs, so give the Mac a non-sensitive tailnet name **[S7]**.

Optionally, the Host can check whether serve is configured by running `tailscale serve status` (the `status` subcommand **[S9]**) and show a "not set up" state in the menubar. That one call is the only CLI use, and it is optional.

## 3. Restricting exposure and learning who is calling

- **Loopback-only binding is required, not just nice to have.** Tailscale: "it's best practice to only have the service listen on localhost. Otherwise, any user that can call your service directly … could trivially provide their own values for these HTTP headers" **[S1]**. Serve also deletes any incoming `Tailscale-User-*` headers before adding its own **[S3]**.
- **What the headers prove:** serve calls `WhoIs` on the source address. It **skips the headers for tagged nodes** and for traffic it can't attribute, such as the local machine, and on Funnel it sets `Tailscale-Funnel-Request` instead **[S3]**. Header values may be RFC 2047 Q-encoded **[S1]**. The headers identify the tailnet **user**. You own both the Mac and the iPhone, so the headers can't tell *which of your devices* is calling.
- **Device identity, if wanted:** serve sets `X-Forwarded-For` to the caller's tailnet IP **[S3]**. `tailscale whois <ip>` returns machine name, ID and addresses, plus the user **[S9]**. That would bring back a runtime CLI dependency, so **don't do it in v1.** The Pairing token already binds a specific Remote.
- **Local processes are still a threat model:** anything on the Mac can reach `127.0.0.1:PORT` directly and fake headers. This is a second reason the **Pairing token is the real authorization check**. Check it on every request, *including the WebSocket upgrade*.
- **Optional tailnet-level lock:** a grant can allow only the iPhone (or your user's devices) to reach the Mac on `tcp:443`. Grants deny by default **[S10]**. This is admin-console config, not something the Host does.

**Answer to "can the Host learn the caller's Tailscale identity?":** yes, the user, from serve headers at no cost. The device needs `whois` on `X-Forwarded-For`. Use the user login only as a sanity check, for example to refuse requests whose login is not yours, and authorize with Pairing.

## 4. iOS Safari capabilities (iPhone)

All of these assume the Remote is served over HTTPS (a secure context). Versions come from MDN browser-compat-data **[S11]** unless noted otherwise.

| Capability | iOS Safari support | Secure context | User gesture | Notes for MyRemote |
|---|---|---|---|---|
| `DeviceOrientationEvent` / `DeviceMotionEvent.requestPermission()` (gyro for Laser) | 14.5+ **[S11]** | Yes **[S14]** | **Yes**, transient activation, otherwise `NotAllowedError` **[S14]** | Put a "Start Laser" button in Presentation mode and call `requestPermission()` in its tap handler |
| Screen Wake Lock (`navigator.wakeLock.request('screen')`) | 16.4+ in Safari tabs. **18.4+ in Home Screen web apps** (16.4–18.3: "Does not work in standalone Home Screen Web Apps") **[S11][S15]** | Yes **[S16]** | No (not required by spec) | Released when the page is hidden. Re-acquire on `visibilitychange` **[S16]**. Set the minimum to iOS 18.4 |
| Vibration (`navigator.vibrate`) | **Not supported** (Safari `version_added: false`; iOS mirrors it) **[S11]** | n/a | n/a | No vibration API |
| Haptics workaround | Tapping `<input type=checkbox switch>` (Safari 17.4+ **[S17]**) gives a system haptic on iOS 18+. Since WebKit 288403@main this **requires user activation** **[S18]** | – | Yes | Only works on a real tap, which suits a "click" tick on tap. It can't fire for Host-initiated events. Treat as a nice-to-have hack |
| Fullscreen API (`requestFullscreen`) | **iPad only, not iPhone** **[S11]** | – | Yes | Use a Home Screen web app (`display: standalone`) instead: it removes the browser chrome |
| Home Screen web app | Manifest `display: standalone`/`fullscreen` makes it a web app (16.4+) **[S19]**. iOS 26: **every** site added to the Home Screen opens as a web app by default ("Open as Web App" toggle) **[S20]** | – | – | Ship a manifest with `display: standalone` |
| WebSocket / WebRTC DataChannel | Both supported (DataChannel 11+) **[S11]** | `wss://` from an https page | – | WebSocket chosen (section 1) |

**Minimum supported iOS: 18.4.** That is the first version where Wake Lock works in the installed web app.

## 5. PWA storage isolation and the Pairing token

- **Separate storage:** "the website data of home screen web applications is kept isolated from Safari" **[S21]**. On iOS, a token stored in a Safari tab **is not visible to the Home Screen app**, and vice versa. On macOS, Safari copies *cookies only* into an Add-to-Dock web app at install time and "does not copy over any other kind of local storage" **[S22]**. No equivalent iOS statement was found, so *assume nothing is copied on iOS*.
- **ITP 7-day cap:** Safari deletes "all cookies created in JavaScript and all other script-writeable storage" (localStorage, IndexedDB, SW caches…) after 7 days without user interaction. **Home Screen web apps are exempt** **[S21]**. A **server-set cookie** is not on that list.

**What this means for Pairing:**

1. Store the token as an **`HttpOnly; Secure; SameSite=Strict` cookie** set by the Host in the Pairing response, with a long `Max-Age`. It is server-set, so it falls outside the 7-day script-storage cap even in a Safari tab. Same-origin `wss://` upgrades send it automatically, so the Host checks it in the handshake, and page JS never sees it.
2. **Pair inside the installed web app.** A pairing QR code scanned with the camera opens **Safari**, not the Home Screen app. The token would land in the wrong storage. Flow: open the URL in Safari → Add to Home Screen → open the app → Pairing screen → enter a short code shown in the Host's menubar (or the Host shows the code after the app makes a pairing request). Don't depend on a QR deep link carrying the token.
3. If the user deletes and re-adds the Home Screen icon, the storage is gone and they must pair again. The Host should let you revoke and re-issue tokens from the menubar.

## Open items to check in the first spike

- WebSocket upgrade through `tailscale serve` from iOS Safari / the Home Screen app works end to end (expected from [S3][S4]).
- Typical round-trip time on your network: run `tailscale ping`. Check whether the phone↔Mac path stays direct.
- Switch-control haptic in a Home Screen web app on your iOS version.
- Whether iOS 26 copies cookies from Safari into a newly added web app, as macOS does. It doesn't change the design: still pair in-app.

## Sources

- **[S1]** Tailscale KB, *Tailscale Serve* (identity headers, spoofing, localhost best practice) — https://tailscale.com/kb/1312/serve
- **[S2]** Tailscale KB, *tailscale serve command* (`--bg` persistence, flags, proxies only to `http://127.0.0.1`) — https://tailscale.com/kb/1242/tailscale-serve
- **[S3]** Tailscale source, `ipn/ipnlocal/serve.go` (`httputil.ReverseProxy`, `addTailscaleIdentityHeaders`, `addProxyForwardedHeaders`, tagged-node skip) — https://github.com/tailscale/tailscale/blob/3d62394afc62273e4d6a3e9ffaa82987179fad2d/ipn/ipnlocal/serve.go#L1088-L1127
- **[S4]** Go source, `net/http/httputil/reverseproxy.go` ("Upgrade requests … are forwarded", `handleUpgradeResponse`) — https://github.com/golang/go/blob/master/src/net/http/httputil/reverseproxy.go
- **[S5]** Tailscale KB, *Connection types* (direct vs DERP vs peer relay; DERP QoS) — https://tailscale.com/kb/1257/connection-types
- **[S6]** Tailscale blog, *How Tailscale works* (DERP "use HTTPS streams") — https://tailscale.com/blog/how-tailscale-works
- **[S7]** Tailscale KB, *Enabling HTTPS* (MagicDNS + Enable HTTPS, CT log exposure, renewal) — https://tailscale.com/kb/1153/enabling-https
- **[S8]** Tailscale KB, *CLI — `tailscale cert`* (90-day expiry, you renew) — https://tailscale.com/kb/1080/cli
- **[S9]** Tailscale KB, *CLI* (macOS CLI paths, `serve status`, `whois` output) — https://tailscale.com/kb/1080/cli
- **[S10]** Tailscale KB, *Grants* — https://tailscale.com/kb/1324/grants
- **[S11]** MDN browser-compat-data (`api/Navigator.json` vibrate/wakeLock, `WakeLock.json`, `DeviceOrientationEvent.json`, `DeviceMotionEvent.json`, `Element.json` requestFullscreen, `RTCDataChannel.json`, `PointerEvent.json`) — https://github.com/mdn/browser-compat-data/tree/main/api
- **[S12]** MDN, *Secure contexts* — https://developer.mozilla.org/en-US/docs/Web/Security/Secure_Contexts
- **[S13]** Apple, `NWProtocolWebSocket` (macOS 10.15+) — https://developer.apple.com/documentation/network/nwprotocolwebsocket
- **[S14]** MDN, `DeviceOrientationEvent.requestPermission()` — https://developer.mozilla.org/en-US/docs/Web/API/DeviceOrientationEvent/requestPermission_static
- **[S15]** WebKit bug 254545, Wake Lock in Home Screen web apps (fixed in iOS 18.4) — https://bugs.webkit.org/show_bug.cgi?id=254545
- **[S16]** MDN, *Screen Wake Lock API* — https://developer.mozilla.org/en-US/docs/Web/API/Screen_Wake_Lock_API
- **[S17]** WebKit blog, *An HTML switch control* (Safari 17.4) — https://webkit.org/blog/15054/an-html-switch-control/
- **[S18]** WebKit bug 285120, "haptic feedback for `<input type=checkbox switch>` should require user activation" (fixed, 288403@main) — https://bugs.webkit.org/show_bug.cgi?id=285120
- **[S19]** WebKit blog, *Web Push for Web Apps on iOS and iPadOS* (manifest `display`) — https://webkit.org/blog/13878/web-push-for-web-apps-on-ios-and-ipados/
- **[S20]** WebKit blog, *News from WWDC25: WebKit in Safari 26 beta* ("every website added to the Home Screen opens as a web app") — https://webkit.org/blog/16993/news-from-wwdc25-web-technology-coming-this-fall-in-safari-26-beta/
- **[S21]** WebKit, *Tracking Prevention* (7-day cap; Home Screen apps exempt and isolated) — https://webkit.org/tracking-prevention/
- **[S22]** WebKit blog, *WebKit Features in Safari 17.0* (macOS web apps copy cookies only) — https://webkit.org/blog/14445/webkit-features-in-safari-17-0/
