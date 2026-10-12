# MyRemote

Control your Mac from your iPhone over [Tailscale](https://tailscale.com). A menubar app on the Mac (the **Host**) serves a web app (the **Remote**) that you add to the iPhone's Home Screen. The Remote has four Modes: Trackpad, Keyboard, Media and Presentation.

Status: v1.1. All four Modes work, the trackpad does the Mac trackpad's Gestures, and a Remote has to be paired before it can control the Mac. There are no prebuilt downloads: you build it from source for your own Mac and tailnet. One install serves one user and one Mac.

## Requirements

- A Mac on macOS 15 or later, with the Swift 6 toolchain (Xcode, or just the Command Line Tools: `xcode-select --install`).
- An iPhone on iOS 18.4 or later.
- [Tailscale](https://tailscale.com/download) on both, logged in to the same tailnet.
- Node 24, only to run the Remote's tests.
- [BlackHole 2ch](https://github.com/ExistentialAudio/BlackHole), only to use the Phone Mic as a microphone in calls (see [Phone Mic](#phone-mic)).

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
git clone https://github.com/cmcaruso/MyRemote.git
cd MyRemote
scripts/bundle.sh --run
```

This builds `build/MyRemote.app` and opens it. A hand icon appears in the menu bar. macOS asks to allow MyRemote under **System Settings → Privacy & Security → Accessibility**. Turn it on, and the menu changes to "Accessibility: granted". You can move the app to `/Applications` if you like.

The app is signed ad hoc, so macOS asks for Accessibility again after every rebuild. `--run` quits System Settings and clears the old entry first. If the switch is on but the pointer doesn't move, remove MyRemote from the list with **−** and add `build/MyRemote.app` again with **+**. If you rebuild often, sign with a code-signing identity of your own. A self-signed one is enough: in Keychain Access, choose Keychain Access → Certificate Assistant → **Create a Certificate…**, give it a name, set Certificate Type to **Code Signing**, and create it. Then copy `scripts/signing.local.example` to `scripts/signing.local` (it's git-ignored) and set `MYREMOTE_SIGN_IDENTITY`. The grant then survives rebuilds.

The Host listens on `127.0.0.1:8484`. To use another port, run `defaults write io.github.cmcaruso.myremote port 9000` (or the bundle ID you set), and point `tailscale serve` at the same port.

The menu shows:

- whether the Host is serving, and on which port;
- whether `tailscale serve` reaches it. If it does, you get the Remote's address with **Copy Remote Address** (Universal Clipboard hands it to the iPhone). If it doesn't, you get the `tailscale serve --bg <port>` command to copy. If Funnel is on, the menu warns you: Funnel puts the Remote on the public internet. The Host reads this from Tailscale's CLI (`/Applications/Tailscale.app/Contents/MacOS/Tailscale`, or `tailscale` in `/usr/local/bin` or `/opt/homebrew/bin`). Without the CLI, the Host still works, and the menu just says it can't check;
- how many Remotes are connected;
- **Pair a Remote…**, and the **Paired Remotes** you can revoke (see below);
- the Accessibility grant, with a button to its settings if it's missing;
- **Launch at Login**. The login item remembers where the app is. It stays on when `bundle.sh` rebuilds the app in place, but if you move the app, turn it off first and on again from the new place. macOS may ask you to approve it in System Settings → General → Login Items.

### 3. Add the Remote to the iPhone

1. On the iPhone, open `https://<your-mac>.<your-tailnet>.ts.net` in Safari.
2. Tap Share → **Add to Home Screen**, then open the Remote from its icon. Always use it from there, not from a Safari tab.

### 4. Pair the Remote

The Remote opens on **Pair with your Mac**. On the Mac, choose **Pair a Remote…** in the MyRemote menu: a window shows a 6-digit code for 2 minutes. Type it into the Remote, and the window confirms and closes. Pair inside the Home Screen app: it keeps its own cookies, so pairing in a Safari tab doesn't carry over.

How Pairing protects the Mac:

- Each paired Remote holds a random token in an `HttpOnly`, `Secure`, `SameSite=Strict` cookie that lasts 400 days and renews whenever the Remote connects. The Host keeps only a hash of it, in `~/Library/Application Support/MyRemote/remotes.json`.
- Every request must come through `tailscale serve` with a tailnet login (`Tailscale-User-Login`), the same login the Remote paired under. Funnel traffic has no login, so it's refused.
- The WebSocket and the pairing request must come from a page the Host served (`Origin` matching `Host`), so a web page open on the Mac can't drive it.
- A code works once, and five wrong tries kill it.

**Paired Remotes** in the menu lists each Remote with when it paired and was last used. **Revoke** one, or **Revoke All**: it's disconnected at once and goes back to the pairing screen. On the Remote, ⚙ → **Unpair this Remote** does the same from the phone.

### 5. Presenting

**Present** turns the Remote into a clicker: **Next** and **Prev** send Page Down and Page Up, and holding **Black** for a moment sends `B` (black screen in Keynote and PowerPoint). Hold the red zone to show the **Laser**, a red dot on the display with the cursor, and turn the phone to steer it. If you'd rather steer with your thumb, choose ⚙ → Present → Laser: **Drag**. The zone then works like a trackpad, and the dot stays a moment after you lift so you can swipe again from where it is. The dot is drawn above full-screen slideshows on every Space, and the real cursor stays where it is. iOS asks for motion access the first time you lift your thumb off the zone, and again after every launch, because it doesn't remember the answer. Until you allow it, or if you refuse, drag your thumb in the zone instead. Drag never asks. Switch the zone from **Laser** to **Pointer** to get a trackpad for the real pointer, say to click a link or start a video. The phone stays awake while Present is showing.

With the Mic on, hold the phone upside down, mic toward your mouth, and the Remote turns round to match: iPhones with Face ID never rotate a page upside down, so it does it itself, only in Present, even when the phone went through landscape on the way over. It turns only while the Mic records from the iPhone itself: with AirPods or another headset, or the Mic off, the screen stays the right way up however you hold the phone. It reads the tilt, so it needs motion access, which iOS asks for when you turn on the Mic or use the Laser. To keep it the right way up, choose ⚙ → Present → Upside down: **Off**.

### Gestures

The Remote's trackpad follows the Mac's own trackpad settings for Gestures, so there's nothing to set up on the phone. ⚙ → **Gestures** lists them by the names System Settings → Trackpad uses, with the Mac's current choices: change them on the Mac and the list follows. Look up always shows as a three-finger tap when it's on, because a phone can't force-click. Tap to click, two-finger right-click and scroll direction stay the Remote's own.

On the pad:
- **Zoom in or out**: pinch two fingers, as on the Mac's trackpad. Apps zoom as the fingers move.
- **Rotate**: turn two fingers around each other, say in Preview or Photos.
- **Smart zoom**: double-tap with two fingers. The first tap still right-clicks at once, as before.
- **Swipe between pages**: scroll sideways with two fingers in Safari and the page slides with them, as on the Mac. If the Mac swipes between pages with three fingers, a three-finger swipe right goes back and left goes forward once you lift (a quarter of the pad's width, or a flick).
- **Look up & data detectors**: tap with three fingers to look up the word under the pointer. It works this way even when the Mac looks up with Force Click, because a phone can't force-click.
- **Three-finger drag**: if the Mac has it on (System Settings → Accessibility → Pointer Control → Trackpad Options), move three fingers to drag a window or select text; lift them all to let go. The three-finger swipes then take four fingers, as on the Mac, and three fingers no longer swipe between pages.
- **Notification Center**: put two fingers at the pad's right edge and swipe left. It opens at once, and the same swipe closes it.

- **Mission Control** and **App Exposé**: swipe up or down with three fingers (or four, as the Mac has it).
- **Swipe between full-screen apps**: swipe left or right with the same fingers to move between Spaces.
- **Show Desktop** and **Apps**: spread or pinch four or five fingers.

Mission Control, App Exposé, full-screen apps, Show Desktop and Apps follow your fingers as on the Mac: lift after a quarter of the way (half the pad's height or width is all the way), or flick, and it completes. Lift sooner and it springs back. A Gesture that's off on the Mac does nothing.

The dots turn purple for the app Gestures and green for the Dock ones and Notification Center, and the pad names the Gesture while it's on. The Remote waits 60 ms after your fingers land before deciding, and a Gesture keeps going until every finger is up. While you type in **Keys**, iOS's three-finger undo, redo and paste are blocked, so they can't edit the Mac's text. The pointer pad in **Present** stays a plain trackpad, though its sideways scrolls can swipe between pages too, as any trackpad's do.

### Phone Mic

Tap **Mic** in Present to speak into the iPhone and have the Mac hear it, for example as your microphone in a Teams call. iOS asks for the microphone every time the Remote launches. While it's on, **Mic on** turns red, a **MIC** badge shows in the other Modes, and the phone stays awake. Tap it again to turn it off.

The Host plays your voice into an audio output that you pick in the menu under **Send Phone Mic To**. macOS doesn't let an app add a microphone by itself, so for calls you need BlackHole, a free virtual audio device. Install it once:

```sh
brew install --cask blackhole-2ch
```

It asks for your password. The Host picks **BlackHole 2ch** by default once it's installed. In Teams (or Zoom, Meet, …), choose **BlackHole 2ch** as the microphone. To play your voice out loud instead, for example through a room's speakers, pick that output in the menu. The Host never plays it through an output you didn't pick: until BlackHole is installed or you pick one, the Mac doesn't play the Phone Mic at all, so you don't hear yourself out of the Mac's speakers. The menu says whether the Phone Mic is live and where it goes.

- Expect about a tenth to a fifth of a second of delay, depending on the network.
- iOS stops the mic when the Remote goes to the background or the phone locks. It starts again when you come back.
- If people in the call hear themselves, the Mac's speakers are reaching the phone. Use headphones on the Mac.

**In a room, through its speakers**, the phone hears its own voice again, like any microphone. The **echo guard**, on by default, does what a microphone setup does about it:
- iOS auto-gain is off, so the room isn't turned up between your words.
- A low cut takes out rumble.
- A voice gate turns everything but your voice down by 20 dB. Held at your mouth, you're far louder than the speakers.
- When feedback starts to ring, the Remote finds the tone within half a second and notches it out, up to four tones.

Turn it off under ⚙ → Present → Echo guard. Keep the phone at your mouth, and the room's volume no higher than it needs to be.

The room still hears the speakers a tenth to a fifth of a second after your own voice, because the sound travels over the network. Wireless microphones are near instant. Up close, the room mostly hears you directly. At the back, the speakers carry you, but the delay can sound like a slap-back echo. The delay is shortest with the phone and the Mac on the same network, and longest on mobile data.

## Known limitations

- **Reconnecting.** The Remote reconnects a second after it loses the Host. If it seems stuck after the phone or the Mac slept, close the Home Screen app and open it again.
- **Wi-Fi stutter.** With the Mac on Wi-Fi, the pointer can stall for about 100 ms a couple of times a second. The Mac's own Wi-Fi causes this, not the tailnet. A wired connection on the Mac avoids it.
- **Networks that block Tailscale.** Some campus and office Wi-Fi blocks Tailscale, and the Remote can't reach the Mac. Put the iPhone on mobile data, or the Mac on a wired network, or both.
- **Phone Mic in the background.** iOS doesn't let a web app use the microphone in the background, so keep the Remote open while you talk.
- **Look up in some apps.** The Remote presses Look up's shortcut (⌃⌘D), since a real three-finger tap or force click can't be faked, so apps that ignore the shortcut don't look up. It works in Safari and TextEdit on macOS 26; Mail has been reported to ignore it.
- **Dock Gestures on other macOS versions.** On macOS other than 26.x, Mission Control, App Exposé, Spaces, Show Desktop and Apps happen at once instead of following your fingers.
- **Not included:** brightness control and a now-playing display. The Laser is tested over PowerPoint, Google Slides and Safari full screen, but not Keynote.

## Development

```sh
swift test                                   # Host logic (HostCore)
node --test 'remote/test/*.test.js'          # Remote logic
swift run MyRemoteHost                       # run the Host unbundled, serving ./remote
```

On macOS 26, Mission Control, App Exposé, Spaces, Show Desktop and Apps follow the fingers; on any other macOS they happen at once. To try that fallback on macOS 26, start the Host with `MYREMOTE_ONE_SHOT_GESTURES=1 swift run MyRemoteHost`, or quit the app and run `MYREMOTE_ONE_SHOT_GESTURES=1 build/MyRemote.app/Contents/MacOS/MyRemote`. ⚙ → Gestures then says they happen at once.

When unbundled, the Host uses your terminal app's Accessibility grant, so rebuilding needs no new grant. Pairing has no bypass, so the Remote only works through `tailscale serve`: opening `http://127.0.0.1:8484` in a browser shows the pairing screen and refuses the code.

The layout:

- `Sources/HostCore`: the Host's pure logic (wire protocol, pointer and scroll math, keystrokes and keyboard layouts, the Laser's motion, Pairing, reading `tailscale serve` status, menu wording, the Phone Mic's jitter buffer, reading the Mac trackpad settings). It's unit-tested and has no AppKit.
- `Sources/MyRemoteHost`: the menubar app. It serves `remote/`, the `/ws` WebSocket, the Phone Mic's `/mic` WebSocket and the `/pair` and `/unpair` requests. It posts input with `CGEvent` and plays the Phone Mic with `AVAudioEngine`.
- `remote/`: the Remote, plain ES modules with no build step. The Host serves them as they are.
- `scripts/bundle.sh`: builds the `.app` and signs it (ad hoc unless you set an identity).

`CONTEXT.md` defines the project's vocabulary (Host, Remote, Mode, Gesture, Mac trackpad settings, Pairing, Laser, Phone Mic).

## License

MyRemote is free software under the [GNU General Public License v3.0](LICENSE).

The Remote's icons come from [Lucide](https://lucide.dev) (ISC licence; portions from Feather, MIT). The way the Host posts trackpad gesture events was learned from [Mac Mouse Fix](https://github.com/noah-nuebling/mac-mouse-fix) by Noah Nuebling. See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for their licences.

MyRemote is an independent project, not affiliated with or endorsed by Apple or Tailscale. Mac, macOS, iPhone, iOS, Safari and the other Apple product names are trademarks of Apple Inc., and Tailscale is a trademark of Tailscale Inc.; they're used here only to say what MyRemote works with.
