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

**Pairing**:
The one-time step that authorizes a Remote to control a Host.
_Avoid_: login, auth, registration

**Laser**:
A glowing dot drawn by the Host on its screen during Presentation mode; distinct from the real cursor.
_Avoid_: pointer, cursor
