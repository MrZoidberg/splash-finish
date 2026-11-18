# Splash Finish project rules

- The local checkout is `~/GitHub/bobuk.io/splash-fihish` (the folder name has a
  typo); the GitHub repository is `bobuk-io/splash-finish`. Use
  `io.bobuk.splash-finish` for the app and `io.bobuk` for new identifiers.
- Releases use the shared bobuk.io release kit in `Scripts/release/` (see its
  `README.md`); app facts live in `release.env`. The canonical kit is in
  `../ting/Scripts/release`: change it there and copy it with
  `Scripts/release/sync_kit.sh`; never edit the copy here.
- `Scripts/release_next.sh` (no arguments) does the whole next patch release. Prepare
  `docs/releases/v<version>.md`, commit the landing copy (clean `../landing` on
  main), set `APP_IDENTITY` and `NOTARY_PROFILE`, and check readiness with
  `Scripts/release/doctor.sh`. After a failure, run the same command again.
- Every release must be signed with Developer ID, notarized and stapled, signed for
  Sparkle, published to GitHub Releases with `SHA256SUMS` and the GitHub
  `appcast.xml` (for 0.3.12 and older), published to the Homebrew tap,
  **installed at `~/Applications/Splash Finish.app` and restarted**, and the landing
  site with `public/apps/splash-finish/appcast.xml` must be deployed.
- Test the kit only with the offline `Scripts/release/test_kit.sh`; never run
  `release_next.sh`, `release.sh` or `publish.sh` for a check.
- The Sparkle EdDSA private key stays in the login Keychain under account
  `io.bobuk.splash-finish`. Never export, print, commit or upload it.
- Release artifacts must pass `Scripts/release/check_privacy.swift` and
  `Tests/test_packaged_resources.py`; do not ship local home or build paths.
- After every release, update the Splash Finish pages on the landing site when the
  release needs it. See `../AGENTS.md`.
