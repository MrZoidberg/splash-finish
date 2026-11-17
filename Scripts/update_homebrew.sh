#!/usr/bin/env bash
# Render the cask from an immutable release archive; --publish updates the tap.
# Safe to rerun independently if publishing the tap failed after a release.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
source version.env
if [[ $# -gt 1 || ( $# -eq 1 && "$1" != --publish ) ]]; then
  echo "Usage: Scripts/update_homebrew.sh [--publish]" >&2
  exit 1
fi
[[ "$MARKETING_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "Invalid version." >&2; exit 1; }
ARCHIVE="SplashFinish-${MARKETING_VERSION}-universal.zip"
ZIP="dist/$ARCHIVE"
[[ -f "$ZIP" ]] || { echo "Missing $ZIP." >&2; exit 1; }
SHA256=$(shasum -a 256 "$ZIP" | cut -d ' ' -f1)
CASK=$(printf '%s\n' \
  'cask "splash-finish" do' \
  "  version \"$MARKETING_VERSION\"" \
  "  sha256 \"$SHA256\"" \
  '' \
  '  url "https://github.com/bobuk-io/splash-finish/releases/download/v#{version}/SplashFinish-#{version}-universal.zip"' \
  '  name "Splash Finish"' \
  '  desc "Shared inbox for AI agent notifications and questions"' \
  '  homepage "https://bobuk.io/apps/splash-finish/"' \
  '' \
  '  livecheck do' \
  '    url :url' \
  '    strategy :github_latest' \
  '  end' \
  '' \
  '  auto_updates true' \
  '  depends_on macos: :sonoma' \
  '' \
  '  app "Splash Finish.app"' \
  '  binary "#{appdir}/Splash Finish.app/Contents/MacOS/SplashFinish", target: "splash-finish"' \
  '' \
  '  zap trash: [' \
  '    "~/Library/Application Support/Splash Finish",' \
  '    "~/Library/Caches/io.bobuk.splash-finish",' \
  '    "~/Library/Preferences/io.bobuk.splash-finish.plist",' \
  '    "~/Library/Saved Application State/io.bobuk.splash-finish.savedState",' \
  '  ]' \
  'end')
if [[ "${1:-}" != --publish ]]; then
  printf '%s\n' "$CASK"
  exit 0
fi

# Do not point Homebrew at a draft, prerelease, missing or mismatched archive.
RELEASE=$(gh api "repos/bobuk-io/splash-finish/releases/tags/v${MARKETING_VERSION}")
printf '%s' "$RELEASE" | jq -e --arg name "$ARCHIVE" --arg digest "sha256:$SHA256" \
  '.draft == false and .prerelease == false and any(.assets[]; .name == $name and .digest == $digest)' >/dev/null || {
  echo "The published release does not match $ZIP." >&2
  exit 1
}
ENDPOINT="repos/bobuk-io/homebrew-tap/contents/Casks/splash-finish.rb"
if ! EXISTING=$(gh api "$ENDPOINT"); then
  # A new cask has no SHA yet. Only an explicit 404 permits creation; fail on
  # authentication, network or server errors instead of treating them as absence.
  if ! printf '%s' "$EXISTING" | jq -e '.status == "404"' >/dev/null; then
    echo "Cannot read the existing Homebrew cask." >&2; exit 1
  fi
  EXISTING='{}'
fi
CONTENT=$(printf '%s\n' "$CASK" | base64 | tr -d '\n')
if [[ "$(printf '%s' "$EXISTING" | jq -r '.content' | tr -d '\n')" == "$CONTENT" ]]; then
  echo "Homebrew cask is already up to date."
  exit 0
fi
printf '%s' "$EXISTING" | jq --arg content "$CONTENT" --arg version "$MARKETING_VERSION" \
  '{message: ("chore(splash-finish): update cask to " + $version), content: $content} + (if .sha then {sha: .sha} else {} end)' |
  gh api --method PUT "$ENDPOINT" --input - >/dev/null
echo "HOMEBREW_UPDATED: bobuk-io/tap/splash-finish $MARKETING_VERSION"
