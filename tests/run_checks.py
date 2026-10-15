"""Run Godot checks against real project modules; no third-party Python dependencies."""

import argparse
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--godot", default="godot")
    args = parser.parse_args()
    executable = shutil.which(args.godot)
    if not executable:
        print(f"Godot executable not found: {args.godot}", file=sys.stderr)
        return 1
    root = Path(__file__).resolve().parent.parent
    with tempfile.TemporaryDirectory(prefix="vector-duel-checks-") as temporary:
        environment = os.environ.copy()
        if os.name != "nt":
            for key, directory in (
                ("XDG_DATA_HOME", "data"),
                ("XDG_CONFIG_HOME", "config"),
                ("XDG_CACHE_HOME", "cache"),
            ):
                path = Path(temporary) / directory
                path.mkdir()
                environment[key] = str(path)

        def run(label: str, arguments: list[str]) -> bool:
            print(f"\n--- {label} ---", flush=True)
            try:
                result = subprocess.run(
                    [executable, *arguments],
                    cwd=root,
                    env=environment,
                    text=True,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.STDOUT,
                    timeout=120,
                    check=False,
                )
            except subprocess.TimeoutExpired:
                print("FAIL: Godot check timed out after 120 seconds", file=sys.stderr)
                return False
            print(result.stdout, end="", flush=True)
            return result.returncode == 0 and not re.search(
                r"(?m)^(?:SCRIPT ERROR:|ERROR:)|Parse Error:", result.stdout
            )

        version = subprocess.run(
            [executable, "--version"], env=environment, text=True, capture_output=True, check=False
        )
        if version.returncode or not version.stdout.strip().startswith("4.6.3."):
            print("FAIL: This project requires Godot 4.6.3", file=sys.stderr)
            return 1
        common = ["--headless", "--path", str(root)]
        if not run("Project import and script parsing", [*common, "--editor", "--quit"]):
            return 1
        tests = [
            "combat/tests/run.gd",
            "input/tests/run_tests.gd",
            "input/tests/engine_input_tests.gd",
            "tests/integration_smoke.gd",
        ]
        for relative in tests:
            if not run(relative, [*common, "--script", f"res://{relative}"]):
                return 1
        for fps in (30, 144):
            if not run(
                f"Engine input at {fps} render FPS",
                [*common, "--max-fps", str(fps), "--script", "res://input/tests/engine_input_tests.gd"],
            ):
                return 1
        if not run("Production scene startup", [*common, "--quit-after", "120"]):
            return 1
    print("PASS: all selected Godot checks completed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
