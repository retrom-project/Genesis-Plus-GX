#!/usr/bin/env python3
"""Turn a verified clean core candidate into immutable release assets."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[2]


def git(*args):
    return subprocess.check_output(["git", "-C", str(ROOT), *args], text=True).strip()


def release(candidate, output, tag):
    config = json.loads((ROOT / "retrom-fork.json").read_text())
    if not re.fullmatch(config["releaseTagPattern"], tag):
        raise ValueError("RETROM_CORE_RELEASE_TAG_INVALID")
    if git("status", "--porcelain"):
        raise ValueError("RETROM_CORE_RELEASE_SOURCE_DIRTY")
    descriptor = json.loads((candidate / "retrom-core-candidate.json").read_text())
    commit = git("rev-parse", "HEAD")
    source_digest = subprocess.check_output(
        ["python3", str(ROOT / ".github/rpg-runtime/candidate_descriptor.py"), "digest", str(candidate)],
        text=True,
    ).strip()
    if (descriptor.get("dirty") is not False or descriptor.get("commit") != commit
            or descriptor.get("repository") != config["forkRepository"]
            or descriptor.get("adapterAbi") != config["adapterAbi"]
            or descriptor.get("sourceTreeSha256") != source_digest):
        raise ValueError("RETROM_CORE_RELEASE_SOURCE_INVALID")
    expected = set(config["releaseAssets"]) - {"rpg-runtime-release.json"}
    records = descriptor["files"]
    if (len(records) != len(expected) or {record["filename"] for record in records} != expected
            or {path.name for path in candidate.iterdir()} != expected | {"retrom-core-candidate.json"}):
        raise ValueError("RETROM_CORE_RELEASE_FILES_INVALID")
    for record in records:
        path = candidate / record["filename"]
        if (path.is_symlink() or not path.is_file() or path.stat().st_size != record["sizeBytes"]
                or hashlib.sha256(path.read_bytes()).hexdigest() != record["sha256"]):
            raise ValueError("RETROM_CORE_RELEASE_INTEGRITY_INVALID")
    output.mkdir(parents=True, exist_ok=True)
    if any(output.iterdir()):
        raise ValueError("RETROM_CORE_RELEASE_OUTPUT_NOT_EMPTY")
    for name in sorted(expected):
        shutil.copyfile(candidate / name, output / name)
    assets = [{"filename": record["filename"], "sizeBytes": record["sizeBytes"],
               "observedSha256": record["sha256"]} for record in records]
    metadata = {"schemaVersion": 1, "repository": config["forkRepository"], "tag": tag,
                "commit": commit, "adapterAbi": config["adapterAbi"], "assets": assets,
                "digestPolicy": "OBSERVED_CACHE_INTEGRITY_ONLY"}
    (output / "rpg-runtime-release.json").write_text(json.dumps(metadata, indent=2, sort_keys=True) + "\n")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--candidate", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--tag", required=True)
    args = parser.parse_args()
    release(args.candidate, args.output, args.tag)
