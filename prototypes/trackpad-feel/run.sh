#!/bin/sh
# PROTOTYPE (ticket #7): build and run the throwaway trackpad Host on 127.0.0.1:8484,
# which `tailscale serve` already exposes at https://<your-mac>.<your-tailnet>.ts.net/
cd "$(dirname "$0")" && swift run -c release --package-path host TrackpadHost "$PWD/remote"
