#!/usr/bin/env python3
"""
Parse models.yaml and resolve model metadata from Hugging Face.
Outputs a JSON build matrix for GitHub Actions.
"""

import json
import sys
import os
from typing import Any, Dict, List, Optional
import yaml
from huggingface_hub import HfApi, model_info, hf_hub_url


def normalize_spdx(license_id: Optional[str]) -> Optional[str]:
    """Normalize SPDX license identifier to lowercase."""
    if not license_id:
        return None
    return license_id.lower().strip()


def is_permissive(license_id: Optional[str], whitelist: List[str], override: Optional[str]) -> bool:
    """
    Determine if a license is permissive.

    Args:
        license_id: SPDX license identifier from HF
        whitelist: List of permissive SPDX IDs
        override: Manual override value (true/false/null)

    Returns:
        True if permissive, False otherwise
    """
    if override is not None:
        return override

    if not license_id:
        return False

    normalized = normalize_spdx(license_id)
    normalized_whitelist = [normalize_spdx(lid) for lid in whitelist]

    return normalized in normalized_whitelist


def resolve_model(model_config: Dict[str, Any], defaults: Dict[str, Any], api: HfApi) -> Dict[str, Any]:
    """
    Resolve a single model configuration.

    Args:
        model_config: Model configuration from models.yaml
        defaults: Default configuration values
        api: HuggingFace API client

    Returns:
        Resolved model configuration for build matrix
    """
    model_id = model_config["id"]
    short = model_config["short"]
    revision = model_config.get("revision")
    permissive_override = model_config.get("permissive")
    gated_override = model_config.get("gated")

    print(f"Resolving model: {model_id}", file=sys.stderr)

    try:
        # Fetch model info from HF
        info = model_info(model_id, revision=revision)

        # Get license
        license_id = getattr(info, "license", None)
        if hasattr(info, "card_data") and info.card_data:
            license_id = info.card_data.get("license", license_id)

        # Get gated status
        gated = getattr(info, "gated", False)

        # Resolve revision SHA
        if not revision:
            revision = info.sha

        print(f"  License: {license_id}, Gated: {gated}, Revision: {revision}", file=sys.stderr)

    except Exception as e:
        print(f"  Warning: Could not fetch model info: {e}", file=sys.stderr)
        license_id = None
        gated = False
        if not revision:
            revision = "main"

    # Apply policy
    whitelist = defaults["spdx_permissive_whitelist"]

    # Resolve permissive flag
    if permissive_override == "auto":
        permissive = is_permissive(license_id, whitelist, None)
    else:
        permissive = permissive_override if permissive_override is not None else False

    # Resolve gated flag
    if gated_override == "auto":
        is_gated = gated
    else:
        is_gated = gated_override if gated_override is not None else False

    # Determine if fat image should be built
    build_fat = permissive and not is_gated

    # Build image name
    image_name = f"hf-{short}"

    # Get base image version
    base_image = defaults["base_image"]
    base_version = base_image.split(":")[-1] if ":" in base_image else "latest"

    # Get publish settings
    publish = model_config.get("publish", defaults.get("publish", {}))

    # Build matrix entry
    matrix_entry = {
        "id": model_id,
        "short": short,
        "revision": revision,
        "license": license_id or "unknown",
        "permissive": permissive,
        "gated": is_gated,
        "build_fat": build_fat,
        "image": image_name,
        "base_image": base_image,
        "version": base_version,
        "serve_args": " ".join(model_config.get("serve_args", [])),
        "oci_title": model_config.get("oci", {}).get("title", f"vLLM + {model_id}"),
        "oci_description": model_config.get("oci", {}).get("description", ""),
        "oci_url": model_config.get("oci", {}).get("url", f"https://huggingface.co/{model_id}"),
        "publish_ghcr": publish.get("ghcr", True),
        "publish_dh": publish.get("dockerhub", True),
        "download_root": defaults["download_root"],
        "hf_cache_dir": defaults["hf_cache_dir"],
    }

    print(f"  Build fat: {build_fat}, Image: {image_name}", file=sys.stderr)

    return matrix_entry


def main():
    """Main entry point."""
    if len(sys.argv) < 2:
        print("Usage: resolve_models.py <models.yaml>", file=sys.stderr)
        sys.exit(1)

    config_file = sys.argv[1]

    # Load configuration
    with open(config_file, "r") as f:
        config = yaml.safe_load(f)

    defaults = config.get("defaults", {})
    models = config.get("models", [])

    if not models:
        print("No models defined in configuration", file=sys.stderr)
        sys.exit(1)

    # Initialize HF API
    api = HfApi()

    # Resolve all models
    matrix = []
    for model_config in models:
        try:
            matrix_entry = resolve_model(model_config, defaults, api)
            matrix.append(matrix_entry)
        except Exception as e:
            print(f"Error resolving model {model_config.get('id', 'unknown')}: {e}", file=sys.stderr)
            continue

    if not matrix:
        print("No models could be resolved", file=sys.stderr)
        sys.exit(1)

    # Output JSON matrix
    output = {"include": matrix}
    print(json.dumps(output, indent=2))


if __name__ == "__main__":
    main()