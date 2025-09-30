#!/usr/bin/env python3
"""
Harvest LICENSE and NOTICE files from Hugging Face model repos.
Vendor SPDX canonical text if LICENSE is missing.
Generate /licenses directory tree for fat images.
"""

import argparse
import json
import os
import sys
from pathlib import Path
from typing import Dict, Optional
from huggingface_hub import hf_hub_download, list_repo_files, model_info
import requests


# Canonical SPDX license texts (abbreviated - use full text in production)
SPDX_TEXTS = {
    "apache-2.0": """Apache License 2.0

[NOTE: This is a vendored SPDX canonical text. The upstream repository
did not include a LICENSE file but declared license: apache-2.0 in metadata.]

Full text available at: https://www.apache.org/licenses/LICENSE-2.0
""",
    "mit": """MIT License

[NOTE: This is a vendored SPDX canonical text. The upstream repository
did not include a LICENSE file but declared license: mit in metadata.]

Full text available at: https://opensource.org/licenses/MIT
""",
    # Add other licenses as needed
}


def fetch_file_from_hf(repo_id: str, filename: str, revision: Optional[str] = None) -> Optional[str]:
    """
    Fetch a file from HF repo.

    Args:
        repo_id: HF model repository ID
        filename: File to fetch (e.g., LICENSE, NOTICE)
        revision: Git revision/commit SHA

    Returns:
        File contents as string, or None if not found
    """
    try:
        local_path = hf_hub_download(
            repo_id=repo_id,
            filename=filename,
            revision=revision,
            repo_type="model"
        )
        with open(local_path, "r", encoding="utf-8") as f:
            return f.read()
    except Exception as e:
        print(f"  Could not fetch {filename}: {e}", file=sys.stderr)
        return None


def fetch_spdx_canonical_text(spdx_id: str) -> Optional[str]:
    """
    Fetch canonical SPDX license text from spdx.org or use vendored version.

    Args:
        spdx_id: SPDX license identifier

    Returns:
        License text or None
    """
    # Try vendored first
    if spdx_id.lower() in SPDX_TEXTS:
        return SPDX_TEXTS[spdx_id.lower()]

    # Try to fetch from SPDX.org
    try:
        url = f"https://raw.githubusercontent.com/spdx/license-list-data/main/text/{spdx_id}.txt"
        response = requests.get(url, timeout=10)
        if response.status_code == 200:
            return f"""[NOTE: This is canonical SPDX text for {spdx_id}.
The upstream repository did not include a LICENSE file.]

{response.text}
"""
    except Exception as e:
        print(f"  Could not fetch SPDX text for {spdx_id}: {e}", file=sys.stderr)

    return None


def generate_project_notice(repo_id: str, license_id: Optional[str], has_upstream_license: bool, has_upstream_notice: bool) -> str:
    """
    Generate project-level NOTICE file.

    Args:
        repo_id: HF model repository ID
        license_id: SPDX license identifier
        has_upstream_license: Whether upstream LICENSE was found
        has_upstream_notice: Whether upstream NOTICE was found

    Returns:
        NOTICE file content
    """
    notice = f"""NOTICE

This Docker image contains multiple components with different licenses:

1. Infrastructure Code (this repository)
   License: CC0-1.0
   Location: /licenses/CC0

2. Model: {repo_id}
   License: {license_id or 'unknown'}
"""

    if has_upstream_license:
        notice += "   Location: /licenses/model/LICENSE\n"
    else:
        notice += "   Location: /licenses/model/LICENSE (vendored SPDX canonical text)\n"

    if has_upstream_notice:
        notice += "   Upstream NOTICE: /licenses/model/NOTICE\n"

    notice += """
3. vLLM (base image)
   License: Apache-2.0
   See: https://github.com/vllm-project/vllm

Modifications: This image bundles the model weights and adds startup scripts.
All trademarks are property of their respective owners.
"""

    return notice


def harvest_licenses(model_id: str, revision: Optional[str], output_dir: str, license_id: Optional[str] = None):
    """
    Main harvesting logic.

    Args:
        model_id: HF model repository ID
        revision: Git revision/commit SHA
        output_dir: Output directory for licenses
        license_id: SPDX license identifier (optional, will fetch from HF if not provided)
    """
    print(f"Harvesting licenses for {model_id} (revision: {revision or 'main'})", file=sys.stderr)

    output_path = Path(output_dir)
    output_path.mkdir(parents=True, exist_ok=True)

    # Create subdirectories
    model_license_dir = output_path / "model"
    model_license_dir.mkdir(exist_ok=True)

    # Fetch model info if license not provided
    if not license_id:
        try:
            info = model_info(model_id, revision=revision)
            license_id = getattr(info, "license", None)
            if hasattr(info, "card_data") and info.card_data:
                license_id = info.card_data.get("license", license_id)
        except Exception as e:
            print(f"  Warning: Could not fetch model info: {e}", file=sys.stderr)

    # Fetch LICENSE from HF
    upstream_license = fetch_file_from_hf(model_id, "LICENSE", revision)
    if not upstream_license:
        # Try alternative filenames
        upstream_license = fetch_file_from_hf(model_id, "LICENSE.md", revision)
    if not upstream_license:
        upstream_license = fetch_file_from_hf(model_id, "LICENSE.txt", revision)

    has_upstream_license = upstream_license is not None

    # If no LICENSE found, try to vendor SPDX text
    if not upstream_license and license_id:
        print(f"  No LICENSE file found, vendoring SPDX text for {license_id}", file=sys.stderr)
        upstream_license = fetch_spdx_canonical_text(license_id)

    # Write model LICENSE
    if upstream_license:
        with open(model_license_dir / "LICENSE", "w", encoding="utf-8") as f:
            f.write(upstream_license)
        print(f"  ✓ Wrote model LICENSE", file=sys.stderr)
    else:
        print(f"  ⚠ No LICENSE available for model", file=sys.stderr)

    # Fetch NOTICE from HF
    upstream_notice = fetch_file_from_hf(model_id, "NOTICE", revision)
    if not upstream_notice:
        upstream_notice = fetch_file_from_hf(model_id, "NOTICE.md", revision)
    if not upstream_notice:
        upstream_notice = fetch_file_from_hf(model_id, "NOTICE.txt", revision)

    has_upstream_notice = upstream_notice is not None

    # Write model NOTICE if found
    if upstream_notice:
        with open(model_license_dir / "NOTICE", "w", encoding="utf-8") as f:
            f.write(upstream_notice)
        print(f"  ✓ Wrote model NOTICE", file=sys.stderr)

    # Copy CC0 license (our infrastructure code)
    cc0_source = Path(__file__).parent.parent / "LICENSE"
    if cc0_source.exists():
        with open(cc0_source, "r", encoding="utf-8") as f:
            cc0_text = f.read()
        with open(output_path / "CC0", "w", encoding="utf-8") as f:
            f.write(cc0_text)
        print(f"  ✓ Wrote CC0 license", file=sys.stderr)

    # Generate project NOTICE
    project_notice = generate_project_notice(
        model_id,
        license_id,
        has_upstream_license,
        has_upstream_notice
    )
    with open(output_path / "NOTICE", "w", encoding="utf-8") as f:
        f.write(project_notice)
    print(f"  ✓ Wrote project NOTICE", file=sys.stderr)

    # Generate OCI labels metadata
    oci_labels = {
        "org.opencontainers.image.licenses": f"CC0-1.0; includes third-party: {license_id or 'unknown'} (model), Apache-2.0 (vLLM)",
        "org.opencontainers.image.source": "https://github.com/13fragments/vllm-models",
        "org.opencontainers.image.url": f"https://huggingface.co/{model_id}",
    }

    with open(output_path / "oci-labels.json", "w", encoding="utf-8") as f:
        json.dump(oci_labels, f, indent=2)
    print(f"  ✓ Wrote OCI labels metadata", file=sys.stderr)

    print(f"✓ License harvesting complete", file=sys.stderr)


def main():
    """Main entry point."""
    parser = argparse.ArgumentParser(description="Harvest licenses from HuggingFace model repos")
    parser.add_argument("--id", required=True, help="Model ID (e.g., org/model-name)")
    parser.add_argument("--rev", help="Revision/commit SHA (optional)")
    parser.add_argument("--license", help="SPDX license ID (optional, will auto-detect)")
    parser.add_argument("--out", required=True, help="Output directory")

    args = parser.parse_args()

    harvest_licenses(args.id, args.rev, args.out, args.license)


if __name__ == "__main__":
    main()