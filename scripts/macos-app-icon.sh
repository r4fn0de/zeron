#!/usr/bin/env bash
# The app's icon, into a bundle's Contents/Resources:
#
#   Assets.car   dist/macos/Zeron.icon, which follows the system's light, dark,
#                clear and tinted looks on macOS 26 and later
#   zeron.icns   dist/macos/icon-1024.png, for earlier macOS and the dmg
#
#   scripts/macos-app-icon.sh <Contents/Resources>
#
# Compiling Zeron.icon takes Xcode 26 or later. Runner images install several
# Xcodes and select an older one by default (macos-15-intel defaults to 16.4
# and also carries 26.x), and an actool that cannot read Icon Composer's .icon
# exits 0 after compiling nothing — so the catalog is compiled with the
# selected Xcode first and then with the other installs, newest first.
# ALLOW_MISSING_ICON_CATALOG=1 downgrades "no catalog anywhere" to a warning
# for images that carry no Xcode 26 at all; the bundle then ships with
# zeron.icns alone, which is what every macOS before 26 reads anyway.
# XCODE_SEARCH_DIRS (colon-separated) adds roots besides /Applications.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RESOURCES="$1"

# Command Line Tools have no actool; Xcode may be installed without being the
# selected developer directory.
if ! xcrun --find actool >/dev/null 2>&1; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

ICONSET="$WORK/zeron.iconset"
mkdir "$ICONSET"
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" "$ROOT/dist/macos/icon-1024.png" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  retina=$((size * 2))
  sips -z "$retina" "$retina" "$ROOT/dist/macos/icon-1024.png" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$RESOURCES/zeron.icns"

# actool also writes a Zeron.icns of its own, which would land on zeron.icns on
# a case-insensitive disk, so only its catalog is taken.
compile_catalog() {
  local dev="${1:-}"
  rm -rf "$WORK/car"
  mkdir "$WORK/car"
  if [[ -n "$dev" ]]; then
    DEVELOPER_DIR="$dev" xcrun actool "$ROOT/dist/macos/Zeron.icon" \
      --compile "$WORK/car" \
      --platform macosx \
      --minimum-deployment-target 13.0 \
      --app-icon Zeron \
      --output-partial-info-plist "$WORK/partial.plist" >/dev/null 2>&1 || true
  else
    xcrun actool "$ROOT/dist/macos/Zeron.icon" \
      --compile "$WORK/car" \
      --platform macosx \
      --minimum-deployment-target 13.0 \
      --app-icon Zeron \
      --output-partial-info-plist "$WORK/partial.plist" >/dev/null 2>&1 || true
  fi
  [[ -f "$WORK/car/Assets.car" ]]
}

if ! compile_catalog; then
  roots=(/Applications)
  IFS=: read -r -a extra_roots <<<"${XCODE_SEARCH_DIRS:-}"
  roots+=("${extra_roots[@]}")
  for dir in "${roots[@]}"; do
    [[ -n "$dir" ]] || continue
    # Newest name first: any install that can read the .icon will do.
    for dev in $(ls -d "$dir"/Xcode*.app/Contents/Developer 2>/dev/null | sort -r); do
      compile_catalog "$dev" && break 2
    done
  done
fi

if [[ -f "$WORK/car/Assets.car" ]]; then
  mv "$WORK/car/Assets.car" "$RESOURCES/Assets.car"
elif [[ "${ALLOW_MISSING_ICON_CATALOG:-}" == 1 ]]; then
  echo "warning: no installed actool could compile Zeron.icon; packaging with zeron.icns only" >&2
else
  echo "error: actool produced no Assets.car; compiling Zeron.icon takes Xcode 26 or later" >&2
  exit 1
fi
