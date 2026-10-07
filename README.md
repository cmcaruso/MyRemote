# MyRemote

Control your Mac from your iPhone over [Tailscale](https://tailscale.com). A menubar app on the Mac (the **Host**) serves a web app (the **Remote**) that you add to the iPhone's Home Screen. The Remote has four Modes: Trackpad, Keyboard, Media and Presentation.

Status: early. The walking skeleton works (one finger on the Remote moves the Mac's pointer). The other Modes are being built.

## Requirements

- A Mac on macOS 15 or later, with the Swift 6 toolchain (Xcode, or just the Command Line Tools: `xcode-select --install`).
- An iPhone on iOS 18.4 or later.
- Tailscale on both, logged in to the same tailnet.
- Node 24, only to run the Remote's tests.

## Build from source

### 1. Tailscale

1. In the [admin console's DNS page](https://login.tailscale.com/admin/dns), enable **MagicDNS** and **HTTPS Certificates**.
2. On the Mac, run Tailscale.app → Settings → **CLI integration**. If the CLI isn't on your `PATH`, use `/Applications/Tailscale.app/Contents/MacOS/Tailscale` in its place.
3. Tell Tailscale to proxy HTTPS to the Host. This persists across reboots:

   ```sh
   tailscale serve --bg 8484
   ```

   `tailscale serve status` shows your Mac's address, `https://<your-mac>.<your-tailnet>.ts.net`.

### 2. Signing

macOS remembers the Accessibility permission by the app's code signature. If the app is signed ad hoc, that signature changes on every build, and macOS asks again each time. To avoid that, make a stable self-signed identity once:

1. Open **Keychain Access** → **Keychain Access → Certificate Assistant → Create a Certificate…**
2. Set **Name** to `MyRemote Signing`, **Identity Type** to *Self-Signed Root*, and **Certificate Type** to *Code Signing*. Tick **Let me override defaults**.
3. Set **Validity Period** to `3650` days and keep the other defaults. Save it in the *login* keychain.
4. Check it's there: `security find-identity -p codesigning` lists `MyRemote Signing`.

To use another name or bundle ID, copy `scripts/signing.local.example` to `scripts/signing.local` (it's git-ignored) and edit it. To skip this step, set `MYREMOTE_SIGN_IDENTITY=-`: the app is then signed ad hoc and will ask for Accessibility after every rebuild.

### 3. Build and run

```sh
scripts/bundle.sh --run
```

This builds `build/MyRemote.app`, signs it, and opens it. A hand icon appears in the menu bar. The first time, macOS asks to allow MyRemote under **System Settings → Privacy & Security → Accessibility**. Turn it on, and the menu changes to "Accessibility: granted". You can move the app to `/Applications` if you like.

The Host listens on `127.0.0.1:8484`. To use another port, run `defaults write io.github.cmcaruso.myremote port 9000` (or the bundle ID you set), and point `tailscale serve` at the same port.

### 4. Add the Remote to the iPhone

1. On the iPhone, open `https://<your-mac>.<your-tailnet>.ts.net` in Safari.
2. Tap Share → **Add to Home Screen**, then open the Remote from its icon. Always use it from there, not from a Safari tab.

## Development

```sh
swift test                                   # Host logic (HostCore)
node --test 'remote/test/*.test.js'          # Remote logic
swift run MyRemoteHost                       # run the Host unbundled, serving ./remote
```

When unbundled, macOS attributes Accessibility to your terminal app.

The layout:

- `Sources/HostCore`: the Host's pure logic (wire protocol, pointer math). It's unit-tested and has no AppKit.
- `Sources/MyRemoteHost`: the menubar app. It serves `remote/` and the `/ws` WebSocket, and posts input with `CGEvent`.
- `remote/`: the Remote, plain ES modules with no build step. The Host serves them as they are.
- `scripts/bundle.sh`: builds and signs the `.app`.

`CONTEXT.md` defines the project's vocabulary (Host, Remote, Mode, Pairing, Laser).
