#!/usr/bin/env bash
# Offline tests: never touch the real tap, application or user configuration.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/Scripts" "$TMP/dist" "$TMP/bin"
cp "$ROOT/Scripts/update_homebrew.sh" "$TMP/Scripts/"
printf 'MARKETING_VERSION=1.2.3\n' > "$TMP/version.env"
printf 'test archive\n' > "$TMP/dist/SplashFinish-1.2.3-universal.zip"
export TEST_SHA=$(shasum -a 256 "$TMP/dist/SplashFinish-1.2.3-universal.zip" | cut -d ' ' -f1)
export TEST_TMP="$TMP"
cat > "$TMP/bin/gh" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
case "$*" in
  'api repos/bobuk-io/splash-finish/releases/tags/v1.2.3')
    jq -n --arg digest "sha256:${TEST_DIGEST:-$TEST_SHA}" --argjson draft "${TEST_DRAFT:-false}" \
      '{draft:$draft,prerelease:false,assets:[{name:"SplashFinish-1.2.3-universal.zip",digest:$digest}]}' ;;
  'api repos/bobuk-io/homebrew-tap/contents/Casks/splash-finish.rb')
    if [[ -n "${TEST_STATUS:-}" ]]; then printf '{"status":"%s"}\n' "$TEST_STATUS"; exit 1; fi
    jq -n --arg content "${TEST_CONTENT:-}" '{sha:"test-sha",content:$content}' ;;
  'api --method PUT repos/bobuk-io/homebrew-tap/contents/Casks/splash-finish.rb --input -')
    tee "$TEST_TMP/request.json" ;;
  *) echo "Unexpected gh call: $*" >&2; exit 1 ;;
esac
MOCK
chmod +x "$TMP/bin/gh"
export PATH="$TMP/bin:$PATH"
SCRIPT="$TMP/Scripts/update_homebrew.sh"
bash "$SCRIPT" > "$TMP/cask.rb"
grep -q 'version "1.2.3"' "$TMP/cask.rb"
grep -q "sha256 \"$TEST_SHA\"" "$TMP/cask.rb"
grep -q 'auto_updates true' "$TMP/cask.rb"
grep -Fq 'binary "#{appdir}/Splash Finish.app/Contents/MacOS/SplashFinish", target: "splash-finish"' "$TMP/cask.rb"
grep -Fq '"~/Library/Application Support/Splash Finish"' "$TMP/cask.rb"
[[ ! -e "$TMP/request.json" ]]
bash "$SCRIPT" --publish
jq -e '.sha == "test-sha" and .message == "chore(splash-finish): update cask to 1.2.3"' "$TMP/request.json" >/dev/null
jq -r '.content' "$TMP/request.json" | base64 --decode > "$TMP/uploaded.rb"
cmp "$TMP/cask.rb" "$TMP/uploaded.rb"
rm "$TMP/request.json"
TEST_CONTENT=$(base64 < "$TMP/cask.rb" | tr -d '\n') bash "$SCRIPT" --publish
[[ ! -e "$TMP/request.json" ]]
TEST_STATUS=404 bash "$SCRIPT" --publish
jq -e 'has("sha") == false and has("content")' "$TMP/request.json" >/dev/null
rm "$TMP/request.json"
if TEST_STATUS=500 bash "$SCRIPT" --publish; then echo 'Accepted server failure' >&2; exit 1; fi
[[ ! -e "$TMP/request.json" ]]
if TEST_DIGEST=wrong bash "$SCRIPT" --publish; then echo 'Accepted wrong digest' >&2; exit 1; fi
if TEST_DRAFT=true bash "$SCRIPT" --publish; then echo 'Accepted draft' >&2; exit 1; fi
if bash "$SCRIPT" --invalid; then echo 'Accepted invalid argument' >&2; exit 1; fi
rm "$TMP/dist/SplashFinish-1.2.3-universal.zip"
if bash "$SCRIPT"; then echo 'Accepted missing archive' >&2; exit 1; fi
[[ ! -e "$TMP/request.json" ]]
echo 'Homebrew publisher tests passed.'
