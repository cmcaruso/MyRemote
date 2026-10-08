# MyRemote

A personal remote control for one Mac, driven from an iPhone browser over Tailscale.

## Language

**Host**:
The menubar app on the Mac that serves the Remote and turns its commands into input on the Mac.
_Avoid_: server, agent, daemon, desktop app

**Remote**:
The web app opened on the iPhone that the user touches to control the Host.
_Avoid_: client, controller, phone app

**Mode**:
One of the Remote's screens: Trackpad, Keyboard, Media, or Presentation.
_Avoid_: tab, view, page

**Gesture**:
A multi-finger motion on the Remote's trackpad that the Host turns into what the Mac's own trackpad would do: pinch, rotate, smart zoom, the swipes, look up or three-finger drag.
_Avoid_: shortcut, action

**Mac trackpad settings**:
The Mac's own choices of which Gestures are on and how many fingers each takes; the Remote follows them rather than keeping its own. Only the Gesture settings: tap to click, secondary click and scroll direction stay the Remote's, since the phone has no button to press.
_Avoid_: prefs, config

**Pairing**:
The one-time step that authorizes a Remote to control a Host.
_Avoid_: login, auth, registration

**Pairing code**:
The 6-digit code the Host shows for 2 minutes and the user types into the Remote to pair it; it works once.
_Avoid_: PIN, password, OTP

**Paired Remote**:
A Remote the Host has paired and not revoked; it carries a token in a cookie and is listed in the menubar.
_Avoid_: device, session, client

**Laser**:
A glowing dot the Host draws on one display only while the user holds it in Presentation mode, steered by turning the phone; distinct from the real cursor, which it never moves.
_Avoid_: pointer, cursor

**Phone Mic**:
The iPhone's microphone streamed to the Host, which plays it into an output picked in the menu: BlackHole 2ch, for a call to use as its microphone, or speakers.
_Avoid_: microphone (alone), audio, voice
