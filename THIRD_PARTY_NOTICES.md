# Third-party notices

MyRemote's own code is under the GNU General Public License v3.0 (see `LICENSE`). It includes, or is
based on, the following work by others.

## Lucide icons

The Remote's icons (the sprite in `remote/index.html`) come from [Lucide](https://lucide.dev). Some of
them are derived from [Feather](https://feathericons.com). The play-pause and forward-delete icons are
made from Lucide icons. MyRemote's app icon and the Remote's Home Screen icon (drawn by
`scripts/icons.swift`) are Lucide's pointer on a gradient.

ISC License

Copyright (c) 2026 Lucide Icons and Contributors

Permission to use, copy, modify, and/or distribute this software for any
purpose with or without fee is hereby granted, provided that the above
copyright notice and this permission notice appear in all copies.

THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.

Lucide icons derived from Feather are also under this licence:

The MIT License (MIT) (for the icons listed above)

Copyright (c) 2013-present Cole Bemis

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

## Swift packages

The Host is built with these Swift packages, all under the Apache License 2.0 (some with the Swift
runtime library exception), each copyright its own authors:

Hummingbird and HummingbirdWebSocket (the Hummingbird Project), SwiftNIO, SwiftNIO Extras, SwiftNIO
HTTP/2, SwiftNIO SSL, SwiftNIO Transport Services, Swift HTTP Types, Swift HTTP Structured Headers,
Swift Async Algorithms, Swift Algorithms, Swift Atomics, Swift Collections, Swift Numerics, Swift
System, Swift Crypto, Swift ASN.1, Swift Certificates, Swift Log, Swift Metrics, Swift Distributed
Tracing, Swift Service Context, Swift Service Lifecycle, Swift Configuration and AsyncHTTPClient (Apple
Inc. and the SwiftNIO and Swift Server projects), CompressNIO (Adam Fowler) and swift-websocket (the
Hummingbird Project). SwiftNIO includes llhttp (MIT) and a SHA-1 implementation from FreeBSD (BSD), as
its NOTICE says.

The Host also embeds the Swift package [Sparkle](https://sparkle-project.org) (Sparkle.framework), which
updates the Release build from GitHub Releases. Sparkle is under the MIT License, copyright Andy Matuschak, Elgato Systems,
Kornel Lesiński, Mayur Pawashe and its other contributors; its LICENSE also carries the licences of the
code it includes (bsdiff, sais-lite, ed25519 and others).

`Package.resolved` pins the exact versions. `scripts/licenses.sh` copies every package's own LICENSE
and NOTICE files into the app, at `MyRemote.app/Contents/Resources/Licenses`, with a list of the
packages, their versions and where their source is. The Apache License 2.0 is at
<https://www.apache.org/licenses/LICENSE-2.0> and in each package's folder there, and Sparkle's licence
in `Licenses/sparkle`.

## Mac Mouse Fix

macOS has no public API for posting trackpad gestures. The facts the Host needs about them were learned
from [Mac Mouse Fix](https://github.com/noah-nuebling/mac-mouse-fix) by Noah Nuebling, which is under
the MMF License: which private `CGEvent` types and numbered fields carry zoom, rotate, smart zoom, page
swipes, gesture scrolls and dock swipes, the values those fields take, the 1.67 scale for gesture
scrolls, and that a dock swipe's end carries an exit speed. These are facts about how macOS reads its
own events, not Mac Mouse Fix's code. MyRemote posts the events with its own Swift code
(`Sources/MyRemoteHost/Injector.swift`, `Sources/HostCore`) and doesn't include Mac Mouse Fix's code.
