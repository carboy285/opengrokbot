#!/usr/bin/env python3
"""Prepare the pinned native Hermes payload for inclusion in an installer.

Run separately on each target OS/architecture. This is a build-time operation;
it does not install Hermes on an end user's machine or alter their workspace.
"""
import argparse
from pathlib import Path
import subprocess
import sys

REVISION = "45219aa35c2b3538192cdff448eefb3d0facd89a"
REPOSITORY = "https://github.com/NousResearch/hermes-agent.git"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--build-root", type=Path, required=True)
    args = parser.parse_args()
    root = args.build_root.resolve()
    root.mkdir(parents=True, exist_ok=True)
    source = root / "source"
    if not source.exists():
        subprocess.run(["git", "clone", "--no-checkout", REPOSITORY, str(source)], check=True)
        subprocess.run(["git", "-C", str(source), "checkout", "--detach", REVISION], check=True)
    actual = subprocess.check_output(["git", "-C", str(source), "rev-parse", "HEAD"], text=True).strip()
    if actual != REVISION:
        raise RuntimeError("Build source does not match the pinned Hermes revision.")
    dirty = subprocess.check_output(["git", "-C", str(source), "status", "--porcelain"], text=True)
    if dirty.strip():
        raise RuntimeError("Hermes source has local changes; use a clean build directory.")
    subprocess.run([sys.executable, str(source / "scripts/bundles/native_build.py"),
                    "--source", str(source), "--work", str(root / "work"),
                    "--cache", str(root / "cache"), "--out", str(root / "payload"),
                    "--ref", REVISION], cwd=source, check=True)


if __name__ == "__main__":
    main()
