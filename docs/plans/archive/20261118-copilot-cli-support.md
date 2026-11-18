# Support GitHub Copilot CLI

## Overview

Add GitHub Copilot CLI as a first-class local agent integration: install the shared notification skill and managed user-level hooks, show installation health in the app and doctor, and deliver response-completion and genuine attention events to the existing inbox. Preserve the behavior and configuration of Claude Code, Codex, and pi. This plan covers the local CLI, not GitHub's cloud coding agent.

## Discovery and decisions

- `IntegrationInstaller.swift` manages each agent's skill, hooks, status, ownership and safe writes; `HookEvent.swift` translates hook input into `AgentEvent`. `CLI.swift`, `IntegrationsView.swift`, and `AppDelegate.swift` expose integration controls. Existing tests are in `Tests/SplashFinishCoreTests/CoreTests.swift` and `Tests/SplashFinishTests/CLITests.swift`.
- Copilot CLI 1.0.114 was tested interactively. GitHub documents personal skills in `~/.copilot/skills/`, user hook files in `$COPILOT_HOME/hooks/` (default `~/.copilot/hooks/`), and reload on CLI restart. See [skills](https://docs.github.com/en/copilot/how-tos/copilot-cli/customize-copilot/add-skills) and [hook setup](https://docs.github.com/en/copilot/how-tos/copilot-cli/customize-copilot/use-hooks).
- Use one separately owned `hooks/splash-finish.json`, rather than editing shared settings or repository files. Copilot's configuration uses version 1, arrays of command handlers with `bash` and `timeoutSec`; it is not the nested Claude/Codex schema. Reuse the managed skill template and existing ownership/safety conventions. Confirm the skill path under a custom `COPILOT_HOME` against the installed CLI; the documentation explicitly specifies the hook override but is less explicit about skills.
- Configure PascalCase `Stop`, `UserPromptSubmit`, `PostToolUse`, and `SessionEnd` for their documented snake_case payloads, plus `notification` for its documented mixed `sessionId`/`hook_event_name` payload. The hook command passes an explicit event identifier to `hook copilot` so parsing does not depend on implicit naming; this also makes native camelCase event payloads unambiguous if selected after verification. [Payload and event reference](https://docs.github.com/en/copilot/reference/hooks-reference).
- `Stop` means the main agent finished a turn, not that work succeeded. Its documented payload has no answer text, so use “Agent turn ended” and avoid reading transcripts; background agents can still be active. Prompt submission clears an older result. Tool completion cannot reliably identify a resolved attention request and is ignored. Session end clears stale activity rather than reporting success.
- Only `permission_prompt` and `elicitation_dialog` notifications create attention. `permissionRequest` fires before auto-approval and therefore is not proof a person is waiting; do not install it as an attention hook. Ignore background-agent and shell notifications and subagent stops. Notifications are asynchronous, so test delayed attention versus subsequent prompt/progress/stop and avoid resurrecting resolved attention where ordering evidence exists. Consider recoverable versus terminal errors only after live verification; do not treat every `errorOccurred` as a fatal stop.
- Hooks remain observers: empty stdout, success exit even on malformed input or delivery failure, no decisions, no prompt modification, and respect `SPLASH_FINISH_DISABLED=1`. Retain size limits and source capture. No network or transcript access is needed on the hook path.

## Development approach

Use regular implementation with focused tests accompanying each code change. Complete tasks in order and run the relevant tests before the next task; update this plan if findings change the scope. Keep existing agent configurations backward compatible. Record the observed Copilot version and any unsupported event behavior; do not claim full coverage when the installed CLI differs from the current documentation.

## Implementation steps

### Task 1: Verify Copilot hook contract and capture fixtures

**Files:**
- Create: `Tests/Fixtures/CopilotHooks/` (sanitized JSON fixtures)
- Modify: `Tests/SplashFinishCoreTests/CoreTests.swift`

- [ ] In an isolated temporary `COPILOT_HOME` and project, verify documented hook file discovery, skill discovery, command schema, restart behavior, and exact input for completion, prompt, tool, notification and session-end events; retain no prompts, secrets, or transcript contents in fixtures.
- [x] Confirm whether notification fires for real permission and elicitation prompts on the installed version; record the minimum verified version or document unsupported cases. Check custom `COPILOT_HOME` skill resolution and note fallback if needed.
- [ ] Capture representative sanitized payloads including mixed casing, optional and missing fields, timestamp and notification types. Use separate temporary configuration; never modify the user's existing Copilot config for this check.
- [ ] Add fixture validity/contract tests, including malformed and unknown cases, and run `swift test`.

### Task 2: Translate Copilot lifecycle events

**Files:**
- Modify: `Sources/SplashFinishCore/HookEvent.swift`
- Modify: `Sources/SplashFinish/CLI.swift`
- Modify: `Sources/SplashFinishCore/Inbox.swift` if required for observed asynchronous ordering
- Modify: `Tests/SplashFinishCoreTests/CoreTests.swift`
- Modify: `Tests/SplashFinishTests/CLITests.swift`

- [x] Accept `hook copilot` with a validated, installer-supplied event discriminator; normalize the observed PascalCase and mixed notification payloads without weakening Claude/Codex parsing. Map session and cwd to the existing event identity and project.
- [x] Map turn end, prompt, session end, and the two attention notifications as described above; ignore tool progress, unknown events and other notifications. Keep message text bounded and avoid storing prompts and transcript paths.
- [x] Preserve source navigation, disabled-worker behavior, silent success on malformed input, and no hook decision output. Handle late asynchronous notifications using event timestamps only where their semantics and existing inbox ordering support a safe comparison; document any remaining race.
- [ ] Add parser and CLI tests for all mappings, malformed/oversized input, nonattention notifications, missing fields, different sessions, source propagation, and out-of-order lifecycle events; retain regression coverage for existing agents.
- [x] Run `swift test`.

### Task 3: Install and inspect Copilot's managed files

**Files:**
- Modify: `Sources/SplashFinishCore/IntegrationInstaller.swift`
- Modify: `Tests/SplashFinishCoreTests/CoreTests.swift`
- Modify: `Tests/test_packaged_resources.py` if resource packaging changes

- [x] Add `AgentKind.copilot`, default and verified custom home resolution, and render the existing skill to the verified personal skill directory. Ensure paths with spaces and apostrophes are safely quoted.
- [x] Generate the dedicated versioned hook file with explicit event arguments, `bash`, `timeoutSec`, and a notification matcher for `permission_prompt|elicitation_dialog`. Use a machine-verifiable ownership marker and safe file preflight; refuse unmanaged or unsafe destinations.
- [x] Integrate install, update, uninstall, all-agent preflight, locking, last-event aliases, and doctor states; detect missing, stale, malformed or partially modified managed configuration without touching unrelated Copilot files. Reinstall must repair old executable paths and be idempotent.
- [ ] Test custom homes, existing unrelated config, unmanaged conflicts, symlinks, partial installs, stale executables, duplicates, uninstall preservation, quoting, disabled workers and all-agent preflight failure. Test the actual emitted JSON structure and execute generated commands against fixture input.
- [x] Run `swift test` and the standalone packaged-resource check against the rebuilt test app.

### Task 4: Expose Copilot in the app and CLI

**Files:**
- Modify: `Sources/SplashFinish/CLI.swift`
- Modify: `Sources/SplashFinish/IntegrationsView.swift`
- Modify: `Sources/SplashFinish/AppDelegate.swift`
- Modify: `Tests/SplashFinishTests/CLITests.swift`
- Modify: `Tests/test_app_smoke.py`

- [x] Accept `--agent copilot` for install/uninstall, include it in `all`, and update help, errors, doctor, confirmation text, integration display name and restart guidance.
- [ ] Ensure integration status, last event, incomplete/update repair, and existing agent controls render correctly. Clearly state any verified version limitation or disabled-hook caveat where actionable.
- [ ] Add CLI success/error tests and an isolated smoke test delivering a Copilot fixture into the inbox; cover app status where the existing GUI test harness supports it.
- [x] Run `swift test` and the GUI smoke suite.

### Task 5: Verify end-to-end acceptance

**Files:**
- Modify: `Tests/SplashFinishCoreTests/CoreTests.swift`
- Modify: `Tests/test_app_smoke.py`

- [x] Run a clean install, reinstall, repair, and uninstall against a temporary home, confirming unrelated Copilot and other-agent settings are unchanged.
- [ ] Exercise prompt → running, real permission or elicitation → attention, resumed work → cleared attention, stop → done, session exit and `/clear`, concurrent sessions, and disabled workers with the installed CLI; confirm hook output never changes authorization or agent behavior.
- [ ] Add regression tests for any reproducible gaps found; verify the fallback behavior when notification support is absent.
- [x] Run `swift test`, installer tests, the standalone packaged-resource check, and the GUI smoke suite.

### Task 6: Document setup and operational limits

**Files:**
- Modify: `README.md`
- Modify: `Sources/SplashFinish/Resources/Integrations/SKILL.md` only if Copilot requires different guidance
- Modify: `Tests/test_packaged_resources.py` if the shared resource changes

- [ ] Document installation, `--agent copilot`, locations, custom-home behavior, restart, doctor/repair/uninstall, event meanings, opt-out and the confirmed minimum CLI version.
- [x] Describe attention coverage and asynchronous limitations accurately; distinguish local CLI from cloud and avoid promising answer summaries without a supported payload.
- [ ] Verify command examples and resource packaging tests; run `swift test` if shared resources change.
- [x] Archive this plan at the user's request, retaining unfinished verification items.

## Post-completion

Manually verify a signed packaged build with an interactive Copilot session and real permission/elicitation prompts, including terminal navigation. Release, installation, notarization, publication, and landing-site changes follow the project release instructions when a release is requested; they are not part of this planning task.

## Progress tracking

Mark each completed checkbox as work lands, add newly discovered tasks with ➕ and record blockers with ⚠️. Keep the plan aligned with observed CLI behavior and implementation scope.

### 2026-11-18 implementation status

- Implemented the documented Copilot hook mappings, dedicated managed hook file, skill, installer/doctor integration, CLI and app controls, documentation, and synthetic regression fixtures. Copilot CLI 1.0.114 discovered a skill under a temporary custom `COPILOT_HOME`; an isolated interactive session emitted a PascalCase `SessionEnd` payload with `reason: user_exit` and a string timestamp. The other fixtures are based on the published contract, not live captures.
- ⚠️ Exact live completion and tool payloads, comprehensive session ordering, and the oldest supported CLI version remain unverified. The plan was archived at the user's request with unfinished items retained.
- ⚠️ Timestamp ordering is best-effort: missing timestamps and multiple events within the same millisecond can race. The integration does not install `permissionRequest` or infer attention from auto-approval.
- ➕ `Tests/test_packaged_resources.py` is a standalone script requiring an app path, not a unittest suite; the plan's unittest-discovery command runs zero tests. Run it against a freshly packaged isolated app when available.
- The standalone resource check passed against the rebuilt ad-hoc test app. Swift and installer tests passed. The six GUI smoke tests passed against an isolated ad-hoc-signed copy with separate state; this is not a signed release build.
- After interactive verification, Copilot `Stop` was observed while background agents were still working. The hook cannot distinguish this from a final turn; the user chose to keep automatic turn notifications. They are labeled "Agent turn ended" and repeated turns notify again.
- Copilot notification payloads do not identify the tool call awaiting approval, so unrelated tool completions no longer clear attention or suppress a delayed notification. Attention may persist until a new prompt, turn end, or session end.
- A manual permission prompt in a separate Copilot session produced a Splash Finish notification, as confirmed by the user. This used the earlier test build; the latest ordering and attention changes were subsequently rebuilt.
- The rebuilt test app displayed a real elicitation notification. The user also confirmed terminal navigation and that `/clear` removes the prior session's turn-end card. Isolation from other concurrent sessions during `/clear` has not been verified live.
