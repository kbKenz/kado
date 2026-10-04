#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p work/SwiftModuleCache
swiftc -parse-as-library -module-cache-path work/SwiftModuleCache \
  Packages/KadoCore/Sources/KadoCore/Services/Calendar/GoogleCalendarEvent.swift \
  Packages/KadoCore/Sources/KadoCore/Services/Calendar/GoogleCalendarClient.swift \
  Scripts/check-google-calendar.swift -o work/check-google-calendar
work/check-google-calendar
