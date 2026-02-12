#!/usr/bin/env python3
"""Export trained model into a bundled on-device artifact.

This environment does not depend on coremltools. Instead, we emit a deterministic
`.mlmodelc`-shaped artifact directory with metadata and the trained payload.
The iOS service treats this as a packaged model bundle and can fall back safely
if native Core ML loading is unavailable.
"""

from __future__ import annotations

import argparse
import json
import pickle
import shutil
from pathlib import Path


def resolve_out_path(path: Path) -> Path:
    if path.suffix == ".mlmodel":
        return path.with_suffix(".mlmodelc")
    return path


def main() -> int:
    parser = argparse.ArgumentParser(description="Export recipe line classifier artifact")
    parser.add_argument("--model", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()

    if not args.model.exists():
        raise SystemExit(f"Model not found: {args.model}")

    out_dir = resolve_out_path(args.out)
    out_dir.mkdir(parents=True, exist_ok=True)

    payload_path = out_dir / "line_classifier.pkl"
    json_payload_path = out_dir / "line_classifier.json"
    manifest_path = out_dir / "Manifest.json"

    shutil.copy2(args.model, payload_path)
    state = pickle.loads(args.model.read_bytes())
    json_payload_path.write_text(json.dumps(state, indent=2) + "\n", encoding="utf-8")

    manifest = {
        "bundleFormat": "recipe-line-classifier",
        "bundleVersion": 1,
        "modelPayload": payload_path.name,
        "modelJSONPayload": json_payload_path.name,
        "sourceModel": str(args.model),
    }
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")

    print("EXPORT COMPLETE")
    print(f"Artifact: {out_dir}")
    if out_dir != args.out:
        print(f"Requested --out={args.out} mapped to compiled artifact directory {out_dir}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
