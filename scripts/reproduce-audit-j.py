#!/usr/bin/env python3
"""Reproduce the complete audit-J suite at its reviewed code revision."""
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import shutil
import subprocess
import tarfile
import tempfile
from urllib.parse import urlsplit
import zipfile

REVISION = "e895a5974166d09018c8ded04d4e9ea8cdf979a1"
FOUNDRY_VERSION = "1.9.0"
FOUNDRY_COMMIT = "6056c5845d34205a83cf7108042adb137325c9df"
BUN_VERSION = "1.4.4"
# SHA-256 pins for the official GitHub release archives.
ASSETS = {
    ("Darwin", "arm64"): (
        "darwin_arm64", "38f9af72b266c38ce2e4dfc659ae9cbd1f78c01b34738a76b6c4cb9610579426",
        "bun-darwin-aarch64", "c240d7f0ccb90c263a849fcdb09b7ee62630d921348ed6aafda86b9d577bc510"),
    ("Darwin", "x86_64"): (
        "darwin_amd64", "88f234f458652878499d9e363dea37eb06653a948dbe709adef8d8389e0a9025",
        "bun-darwin-x64", "50a3491f73abc2fe81673171a85762d3bc2cc1680ccecadd983de99adf77977e"),
    ("Linux", "aarch64"): (
        "linux_arm64", "22d3060fa83515fb901690a2c59a5f552bd41c241886195b2159562fc4947abc",
        "bun-linux-aarch64", "baa6bb36f51d6e58561e02bbea825038a9df454f673d6d776e8bbf86f8c7850e"),
    ("Linux", "x86_64"): (
        "linux_amd64", "8d17599b42e3139f1a9c171be3798c4ed8e743ae17b84cc3435e57bf2a51ae99",
        "bun-linux-x64-baseline", "e0446eb55995772eb9894bebae9a6be368d985a8b9271ee124486f9946eedd76"),
}


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def main():
    root = Path(__file__).resolve().parent.parent
    host = (platform.system(), platform.machine())
    if host not in ASSETS:
        raise SystemExit("Supported hosts: macOS/Linux, arm64/aarch64 or x86_64")
    for command in ("git", "curl", "tar"):
        if shutil.which(command) is None:
            raise SystemExit("Required command missing: " + command)
    storage = root / ".audit-tools"
    storage.mkdir(exist_ok=True)
    run = Path(tempfile.mkdtemp(prefix="audit-j-", dir=storage))
    logs = run / "logs"
    logs.mkdir()
    print("Audit J logs: " + str(logs), flush=True)
    # Do not inherit personal Foundry profiles, filters or compiler overrides.
    env = {k: v for k, v in os.environ.items()
           if not k.startswith(("FOUNDRY_", "DAPP_"))}
    rpc = env.get("API_URL_BASE_SEPOLIA") or "https://sepolia.base.org"
    env["API_URL_BASE_SEPOLIA"] = rpc
    env["FOUNDRY_PROFILE"] = "default"
    env["NO_COLOR"] = "1"
    commands = []

    def execute(argv, cwd=root, log="setup.log"):
        argv = [str(arg) for arg in argv]
        commands.append({"cwd": str(cwd), "argv": argv, "log": log})
        with (logs / log).open("a") as output:
            output.write("cwd: " + str(cwd) + "\nargv: " + json.dumps(argv) + "\n")
            output.flush()
            result = subprocess.run(argv, cwd=cwd, env=env, stdout=output,
                                    stderr=subprocess.STDOUT)
        (logs / "commands.json").write_text(json.dumps(commands, indent=2) + "\n")
        if result.returncode:
            raise SystemExit("Command failed; inspect " + str(logs / log))

    foundry_arch, foundry_hash, bun_asset, bun_hash = ASSETS[host]
    foundry_url = ("https://github.com/foundry-rs/foundry/releases/download/v" +
                   FOUNDRY_VERSION + "/foundry_v" + FOUNDRY_VERSION + "_" + foundry_arch + ".tar.gz")
    bun_url = ("https://github.com/oven-sh/bun/releases/download/bun-v" +
               BUN_VERSION + "/" + bun_asset + ".zip")
    bin_dir = storage / ("foundry-" + FOUNDRY_VERSION + "-bun-" + BUN_VERSION + "-" + foundry_arch) / "bin"
    bin_dir.mkdir(parents=True, exist_ok=True)
    # Re-extract verified archives on every run; never trust an existing binary.
    for label, url, expected in (("foundry.tar.gz", foundry_url, foundry_hash),
                                  ("bun.zip", bun_url, bun_hash)):
        archive = storage / (expected + "-" + label)
        if not archive.exists() or sha256(archive) != expected:
            execute(["curl", "--fail", "--location", "--retry", "3", "--output", archive, url])
        if sha256(archive) != expected:
            raise SystemExit("Archive checksum mismatch: " + str(archive))
        if label == "foundry.tar.gz":
            with tarfile.open(archive) as package:
                for name in ("forge", "cast", "anvil"):
                    with package.extractfile(name) as src, (bin_dir / name).open("wb") as dst:
                        shutil.copyfileobj(src, dst)
                    (bin_dir / name).chmod(0o755)
        else:
            with zipfile.ZipFile(archive) as package:
                with package.open(bun_asset + "/bun") as src, (bin_dir / "bun").open("wb") as dst:
                    shutil.copyfileobj(src, dst)
                (bin_dir / "bun").chmod(0o755)
    env["PATH"] = str(bin_dir) + os.pathsep + env.get("PATH", "")
    forge, bun = bin_dir / "forge", bin_dir / "bun"
    execute([forge, "--version"], log="versions.log")
    execute([bun, "--version"], log="versions.log")
    versions = (logs / "versions.log").read_text()
    if "forge Version: " + FOUNDRY_VERSION not in versions or FOUNDRY_COMMIT not in versions:
        raise SystemExit("Unexpected Foundry version; inspect versions.log")
    if subprocess.check_output([bun, "--version"], env=env, text=True).strip() != BUN_VERSION:
        raise SystemExit("Unexpected Bun version")

    source = run / "source"
    source.mkdir()
    execute(["git", "archive", "--format=tar", "--output=" + str(run / "source.tar"), REVISION])
    execute(["tar", "-xf", run / "source.tar", "-C", source])
    tracked = [p for p in source.rglob("*") if p.is_file()]
    original = {str(p.relative_to(source)): sha256(p) for p in tracked}
    execute([bun, "install", "--frozen-lockfile", "--ignore-scripts"], cwd=source)
    lock = source / "soldeer.lock"
    original_lock = lock.read_bytes()
    execute([forge, "soldeer", "install"], cwd=source)
    # Soldeer adds only a top-level format-version marker to this older lock.
    if re.sub(rb"\Aversion = 2\r?\n\r?\n", b"", lock.read_bytes()) != original_lock:
        if lock.read_bytes() != original_lock:
            raise SystemExit("Soldeer changed pinned dependency entries; inspect setup.log")
    lock.write_bytes(original_lock)
    metadata = {
        "revision": REVISION, "source": str(source), "host": host,
        "foundry_version": FOUNDRY_VERSION, "foundry_commit": FOUNDRY_COMMIT,
        "foundry_url": foundry_url, "foundry_sha256": foundry_hash,
        "bun_version": BUN_VERSION, "bun_url": bun_url, "bun_sha256": bun_hash,
        "rpc_host": urlsplit(rpc).hostname, "fork_block": 48000000,
        "rpc_storage_cache": False, "threads": 1,
    }
    (logs / "environment.json").write_text(json.dumps(metadata, indent=2) + "\n")
    execute([forge, "test", "--root", source, "--no-storage-caching", "--threads", "1", "-vv"],
            cwd=source, log="tests.log")
    output = (logs / "tests.log").read_text()
    if not re.search(r"81 tests passed, 0 failed, 0 skipped \(81 total tests\)", output):
        raise SystemExit("Expected 81 passing tests with no skips; inspect tests.log")
    for suite in ("Constants_CreateXFork", "WireQuipToken_Fork",
                  "WireQuipToken_ExplicitPinFork", "WireQuipToken_PeerFirstFork"):
        if not re.search(r"^Ran \d+ tests? for .*:" + suite + r"$", output, re.M):
            raise SystemExit("Missing fork suite: " + suite)
    changed = [name for name, digest in original.items() if sha256(source / name) != digest]
    if changed:
        raise SystemExit("Source files changed during reproduction: " + repr(changed))
    (logs / "result.json").write_text(json.dumps({
        "revision": REVISION, "passed": 81, "failed": 0, "skipped": 0,
        "fork_suites": 4, "tracked_source_unchanged": True,
    }, indent=2) + "\n")
    print("PASS: 81 tests, 0 failed, 0 skipped; four real fork suites. Logs: " + str(logs))


if __name__ == "__main__":
    main()
