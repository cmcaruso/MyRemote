#!/bin/sh
# PROTOTYPE (ticket #12): build and run the throwaway Laser overlay. A 🔴 appears in the menubar.
cd "$(dirname "$0")" && mkdir -p .build && swiftc -O -o .build/LaserOverlay LaserOverlay.swift && exec .build/LaserOverlay
