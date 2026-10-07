# MyRemote

Control your Mac from your iPhone over [Tailscale](https://tailscale.com). A menubar app on the Mac (the **Host**) serves a web app (the **Remote**) that you add to the iPhone's Home Screen. The Remote has four Modes: Trackpad, Keyboard, Media and Presentation.

Status: early. Trackpad and Media Modes work. Keyboard, Presentation and Pairing are being built, so until Pairing lands, anyone who can reach the Remote can control the Mac.

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

### 2. Build and run

```sh
scripts/bundle.sh --run
```

This builds `build/MyRemote.app` and opens it. A hand icon appears in the menu bar. macOS asks to allow MyRemote under **System Settings → Privacy & Security → Accessibility**. Turn it on, and the menu changes to "Accessibility: granted". You can move the app to `/Applications` if you like.

The app is signed ad hoc, so macOS asks for Accessibility again after every rebuild. `--run` quits System Settings and clears the old entry first. If the switch is on but the pointer doesn't move, remove MyRemote from the list with **−** and add `build/MyRemote.app` again with **+**. If you rebuild often, sign with a code-signing identity of your own: copy `scripts/signing.local.example` to `scripts/signing.local` (it's git-ignored) and set `MYREMOTE_SIGN_IDENTITY`. The grant then survives rebuilds.

The Host listens on `127.0.0.1:8484`. To use another port, run `defaults write io.github.cmcaruso.myremote port 9000` (or the bundle ID you set), and point `tailscale serve` at the same port.

The menu shows:

- whether the Host is serving, and on which port;
- whether `tailscale serve` reaches it. If it does, you get the Remote's address with **Copy Remote Address** (Universal Clipboard hands it to the iPhone). If it doesn't, you get the `tailscale serve --bg <port>` command to copy. If Funnel is on, the menu warns you: Funnel puts the Remote on the public internet. The Host reads this from Tailscale's CLI (`/Applications/Tailscale.app/Contents/MacOS/Tailscale`, or `tailscale` in `/usr/local/bin` or `/opt/homebrew/bin`). Without the CLI, the Host still works, and the menu just says it can't check;
- how many Remotes are connected;
- the Accessibility grant, with a button to its settings if it's missing;
- **Launch at Login**. Move `MyRemote.app` to `/Applications` before you turn it on, because the login item remembers where the app is. macOS may ask you to approve it in System Settings → General → Login Items.

### 3. Add the Remote to the iPhone

1. On the iPhone, open `https://<your-mac>.<your-tailnet>.ts.net` in Safari.
2. Tap Share → **Add to Home Screen**, then open the Remote from its icon. Always use it from there, not from a Safari tab.

## Development

```sh
swift test                                   # Host logic (HostCore)
node --test 'remote/test/*.test.js'          # Remote logic
swift run MyRemoteHost                       # run the Host unbundled, serving ./remote
```

When unbundled, the Host uses your terminal app's Accessibility grant, so rebuilding needs no new grant.

The layout:

- `Sources/HostCore`: the Host's pure logic (wire protocol, pointer and scroll math, reading `tailscale serve` status, menu wording). It's unit-tested and has no AppKit.
- `Sources/MyRemoteHost`: the menubar app. It serves `remote/` and the `/ws` WebSocket, and posts input with `CGEvent`.
- `remote/`: the Remote, plain ES modules with no build step. The Host serves them as they are.
- `scripts/bundle.sh`: builds the `.app` and signs it (ad hoc unless you set an identity).

`CONTEXT.md` defines the project's vocabulary (Host, Remote, Mode, Pairing, Laser).
