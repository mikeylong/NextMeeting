#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# Exercise packaging with synthetic bundles. The small tool doubles keep this
# test runnable without a Mac; CI also builds and signs the real application.
python3 - "$PROJECT_DIR" <<'PY'
import os
import pathlib
import plistlib
import shutil
import subprocess
import sys
import tempfile

source = pathlib.Path(sys.argv[1])
with tempfile.TemporaryDirectory(prefix="nextmeeting-preview-") as temporary:
    project = pathlib.Path(temporary) / "checkout with spaces"
    scripts = project / "scripts"
    scripts.mkdir(parents=True)
    shutil.copy2(source / "scripts/build-preview.sh", scripts)
    resources = project / "Resources"
    resources.mkdir()
    (resources / "NextMeeting.entitlements").write_text("synthetic entitlements")
    tools = pathlib.Path(temporary) / "tools"
    tools.mkdir()

    def tool(name, body):
        path = tools / name
        path.write_text("#!/usr/bin/env python3\n" + body)
        path.chmod(0o755)

    tool("ditto", """import shutil, sys
shutil.copytree(sys.argv[1], sys.argv[2])
""")
    tool("plutil", """import pathlib, plistlib, sys
assert len(sys.argv) == 6 and sys.argv[1] == '-replace', sys.argv
path = pathlib.Path(sys.argv[5])
data = plistlib.loads(path.read_bytes())
kind, value = sys.argv[3:5]
assert kind in ('-bool', '-string'), sys.argv
data[sys.argv[2]] = value == 'true' if kind == '-bool' else value
path.write_bytes(plistlib.dumps(data))
""")
    tool("codesign", """import os, pathlib, sys
assert pathlib.Path(sys.argv[-1], 'Contents', 'Info.plist').is_file()
sys.exit(1 if os.environ.get('FAIL_PREVIEW_SIGNING') else 0)
""")
    environment = dict(os.environ, PATH=str(tools) + os.pathsep + os.environ["PATH"])

    def run(*arguments, succeeds=True, **extra_environment):
        result = subprocess.run(
            ["bash", str(scripts / "build-preview.sh"), *arguments],
            env=dict(environment, **extra_environment),
            text=True, capture_output=True,
        )
        assert (result.returncode == 0) == succeeds, result.stdout + result.stderr
        return result

    run(succeeds=False)  # A missing main build is not a valid preview source.
    main = project / "build" / "Next Meeting.app"
    contents = main / "Contents"
    (contents / "MacOS").mkdir(parents=True)
    executable = contents / "MacOS" / "NextMeeting"
    executable.write_text("synthetic executable")
    executable.chmod(0o755)
    main_info = contents / "Info.plist"
    main_info.write_bytes(plistlib.dumps({
        "CFBundleIdentifier": "systems.surfaces.NextMeeting",
        "CFBundleName": "Next Meeting",
        "CFBundleDisplayName": "Next Meeting",
        "LSUIElement": True,
    }))
    original_info = main_info.read_bytes()
    preview = project / "build" / "qa" / "NextMeetingPreview.app"

    # Start with light, then exercise every other state and the default. Each
    # rebuild must remove stale flags and files from the previous preview.
    for arguments in [("light",), ("agenda",), ("empty",), ("denied",), ("popover",), ()]:
        if preview.exists():
            (preview / "stale-file").write_text("must not survive a rebuild")
        result = run(*arguments)
        assert f"Built {preview}" in result.stdout
        info = plistlib.loads((preview / "Contents" / "Info.plist").read_bytes())
        scenario = arguments[0] if arguments else "agenda"
        assert info["CFBundleIdentifier"] == "systems.surfaces.NextMeeting.preview"
        assert info["CFBundleName"] == "NextMeetingPreview"
        assert info["CFBundleDisplayName"] == "Next Meeting Preview"
        assert info["LSUIElement"] is False
        assert info["NextMeetingPreview"] is True
        assert info["NextMeetingPreviewState"] == scenario
        assert (info.get("NextMeetingPreviewAppearance") == "light") == (scenario == "light")
        assert not (preview / "stale-file").exists()
        assert main_info.read_bytes() == original_info
        assert list(preview.parent.iterdir()) == [preview]

    previous_info = (preview / "Contents" / "Info.plist").read_bytes()
    run("unknown", succeeds=False)
    run("agenda", "extra", succeeds=False)
    run("light", succeeds=False, FAIL_PREVIEW_SIGNING="1")
    assert (preview / "Contents" / "Info.plist").read_bytes() == previous_info
    assert list(preview.parent.iterdir()) == [preview]

    # Refuse to replace an unexpected symlink at the fixed output path.
    shutil.rmtree(preview)
    preview.symlink_to(main, target_is_directory=True)
    run("agenda", succeeds=False)
    assert main_info.read_bytes() == original_info

print("Preview packaging checks passed: one identity, clean rebuilds, and failure safety.")
PY
