"""Regression checks for issue #1; run against a packaged app, without touching the installed app."""

import argparse
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import time
import uuid


def check(app_source: Path, gui: bool) -> None:
    with tempfile.TemporaryDirectory(prefix="splash-resources-") as temporary:
        root = Path(temporary)
        app = root / "Splash Finish.app"
        shutil.copytree(app_source, app, symlinks=True)
        executable = app / "Contents/MacOS/SplashFinish"
        info_path = app / "Contents/Info.plist"
        info = plistlib.loads(info_path.read_bytes())
        version = info["CFBundleShortVersionString"]
        assert info["SUFeedURL"] == "https://bobuk.io/apps/splash-finish/appcast.xml"
        # Isolate GUI preferences and disable update checks in this disposable app.
        info["CFBundleIdentifier"] = f"io.bobuk.splash-finish.test-{uuid.uuid4().hex}"
        info["SUEnableAutomaticChecks"] = False
        info_path.write_bytes(plistlib.dumps(info))
        subprocess.run(["codesign", "--force", "--sign", "-", str(app)], check=True, capture_output=True)
        bin_dir = root / "bin"
        bin_dir.mkdir()
        link = bin_dir / "splash-finish"
        link.symlink_to(executable)
        environment = {**os.environ, "SPLASH_FINISH_HOME": str(root / "inbox"),
                       "PATH": f"{bin_dir}:{os.environ.get('PATH', '')}"}

        def run(arguments: list[str], executable_path: Path | None = None) -> subprocess.CompletedProcess[str]:
            return subprocess.run(arguments, executable=executable_path, env=environment,
                                  cwd=root, capture_output=True, text=True, timeout=20)

        for command in (str(executable), str(link), "./bin/splash-finish", "splash-finish"):
            result = run([command, "--version"])
            assert result.returncode == 0 and result.stdout.strip() == version, (command, result)
            result = run([command, "doctor"])
            assert result.returncode == 0, (command, result)
        # An explicitly bare argv[0] must not be interpreted relative to cwd.
        result = run(["splash-finish", "--version"], link)
        assert result.returncode == 0 and result.stdout.strip() == version, result
        print("PASS: version and doctor via direct, absolute/relative symlink, PATH and bare argv[0]")

        if gui:
            with tempfile.TemporaryFile() as log:
                process = subprocess.Popen([str(executable)], cwd=root, env=environment, stdout=log, stderr=log)
                try:
                    time.sleep(7)  # The integration check runs three seconds after startup.
                    assert process.poll() is None, f"GUI exited: {process.returncode}"
                    assert (root / "inbox/app.lock").exists(), "GUI did not use the isolated inbox"
                finally:
                    if process.poll() is None:
                        process.terminate()
                    process.wait(timeout=10)
            print("PASS: isolated GUI survives delayed integration resource lookup")

            runs = Path(tempfile.gettempdir()) / "io.bobuk.splash-finish.homebrew-update"
            runs.mkdir(mode=0o700, exist_ok=True)
            with tempfile.TemporaryDirectory(dir=runs) as run_folder:
                run_path = Path(run_folder)
                (run_path / "status").write_text("0\n")
                (run_path / "output.log").write_text("Already up to date\n")
                for argument, owns_inbox in [("--homebrew-update-viewer", False), ("--homebrew-update-log", True)]:
                    inbox = root / argument.removeprefix("--")
                    with tempfile.TemporaryFile() as log:
                        process = subprocess.Popen([str(executable), argument, run_folder], cwd=root,
                                                   env={**environment, "SPLASH_FINISH_HOME": str(inbox)},
                                                   stdout=log, stderr=log)
                        try:
                            time.sleep(3)
                            assert process.poll() is None, f"{argument} exited: {process.returncode}"
                            assert (inbox / "app.lock").exists() == owns_inbox, argument
                            assert (run_path / "handled").exists(), f"{argument} did not show the result"
                        finally:
                            if process.poll() is None:
                                process.terminate()
                            process.wait(timeout=10)
                    (run_path / "handled").unlink()
            print("PASS: Homebrew recovery viewer and post-update GUI launch modes")

        # The developer's real .build remains available. It must NOT mask this failure.
        shutil.rmtree(app / "Contents/Resources/SplashFinish_SplashFinish.bundle")
        # The packager also copies loose resources: those must not mask a missing bundle.
        result = run([str(link), "doctor"])
        assert result.returncode == 1, result
        assert "Integration resources are missing" in result.stderr, result
        print("PASS: missing packaged bundle reports a recoverable error despite local .build")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=Path)
    parser.add_argument("--gui", action="store_true", help="Also launch an isolated GUI process for seven seconds")
    arguments = parser.parse_args()
    check(arguments.app.resolve(), arguments.gui)
