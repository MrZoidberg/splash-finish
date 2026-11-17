#!/usr/bin/env bash
# Offline publication ordering checks; all remote/version-control commands are test doubles.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/Scripts" "$TMP/dist" "$TMP/bin" "$TMP/landing/public" "$TMP/docs/releases"
cp "$ROOT/Scripts/publish.sh" "$TMP/Scripts/"
printf 'MARKETING_VERSION=1.2.3\nBUILD_NUMBER=19\n' > "$TMP/version.env"
printf 'archive\n' > "$TMP/dist/SplashFinish-1.2.3-universal.zip"
(cd "$TMP/dist" && shasum -a 256 SplashFinish-1.2.3-universal.zip > SHA256SUMS)
printf '<sparkle:version>19</sparkle:version>\n' > "$TMP/dist/appcast.xml"
printf 'Release notes\n' > "$TMP/docs/releases/v1.2.3.md"
export EVENTS="$TMP/events" LANDING="$TMP/landing"
cat > "$TMP/bin/git" <<'MOCK'
#!/bin/sh
case "$1" in
  status) exit 0 ;;
  rev-parse) echo test-head ;;
  ls-remote) printf 'test-head\trefs/heads/main\n' ;;
  *) exit 1 ;;
esac
MOCK
cat > "$TMP/bin/gh" <<'MOCK'
#!/bin/sh
case "$1 $2" in
  'release view') exit 1 ;;
  'release create') echo draft >> "$EVENTS" ;;
  'release edit') echo publish >> "$EVENTS"; exit "${FAIL_EDIT:-0}" ;;
  *) exit 1 ;;
esac
MOCK
cat > "$TMP/bin/curl" <<'MOCK'
#!/bin/sh
case "$*" in
  *bobuk.io*)
    while [ "$1" != -o ]; do shift; done
    printf '<sparkle:version>%s</sparkle:version>\n' "${SITE_BUILD:-18}" > "$2"
    printf '%s' "${SITE_STATUS:-200}" ;;
  *) printf '<sparkle:version>18</sparkle:version>\n' ;;
esac
MOCK
cat > "$TMP/Scripts/update_homebrew.sh" <<'MOCK'
#!/bin/sh
test "$1" = --publish
test -f "$LANDING/public/apps/splash-finish/appcast.xml"
echo cask >> "$EVENTS"
MOCK
chmod +x "$TMP/bin/"*
export PATH="$TMP/bin:$PATH"
FEED="$LANDING/public/apps/splash-finish/appcast.xml"
bash "$TMP/Scripts/publish.sh"
cmp "$TMP/dist/appcast.xml" "$FEED"
printf 'draft\npublish\ncask\n' > "$TMP/expected"
cmp "$TMP/expected" "$EVENTS"
rm "$FEED" "$EVENTS"
SITE_STATUS=404 bash "$TMP/Scripts/publish.sh"
cmp "$TMP/dist/appcast.xml" "$FEED"
rm "$FEED" "$EVENTS"
for scenario in 'SITE_BUILD=20' 'SITE_STATUS=503' 'FAIL_EDIT=1'; do
  if env "$scenario" bash "$TMP/Scripts/publish.sh"; then echo "Accepted $scenario" >&2; exit 1; fi
  [[ ! -f "$FEED" ]]
  if [[ -f "$EVENTS" ]]; then
    ! grep -q cask "$EVENTS"
    rm "$EVENTS"
  fi
done
echo 'Publication ordering and migration tests passed.'
