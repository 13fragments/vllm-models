#!/usr/bin/env python3
"""
Generate GitHub Actions job summary with build results.
"""

import argparse
import json
import sys


def format_size(bytes_size: int) -> str:
    """Format bytes as human-readable size."""
    for unit in ['B', 'KB', 'MB', 'GB', 'TB']:
        if bytes_size < 1024.0:
            return f"{bytes_size:.2f} {unit}"
        bytes_size /= 1024.0
    return f"{bytes_size:.2f} PB"


def generate_summary(matrix_entry: dict, reg_ghcr: str = "ghcr.io/13fragments", reg_dh: str = "13fragments") -> str:
    """
    Generate markdown summary for a single model build.

    Args:
        matrix_entry: Build matrix entry from resolve_models.py
        reg_ghcr: GHCR registry path - passed explicitly to avoid GitHub Actions masking
        reg_dh: Docker Hub registry path - passed explicitly to avoid GitHub Actions masking

    Returns:
        Markdown summary
    """
    model_id = matrix_entry["id"]
    short = matrix_entry["short"]
    revision = matrix_entry["revision"]
    license_id = matrix_entry["license"]
    permissive = matrix_entry["permissive"]
    gated = matrix_entry["gated"]
    build_fat = matrix_entry["build_fat"]
    image = matrix_entry["image"]
    version = matrix_entry["version"]

    summary = f"""## Build Summary: {model_id}

### Model Information
- **Model ID**: `{model_id}`
- **Short Name**: `{short}`
- **Revision**: `{revision}`
- **License**: `{license_id}`
- **Permissive**: `{permissive}`
- **Gated**: `{gated}`

### Build Decision
"""

    if build_fat:
        summary += "- **Slim Image**: ✅ Built\n"
        summary += "- **Fat Image**: ✅ Built (permissive, non-gated)\n"
    else:
        summary += "- **Slim Image**: ✅ Built\n"
        if gated:
            summary += "- **Fat Image**: ❌ Skipped (gated model)\n"
        elif not permissive:
            summary += "- **Fat Image**: ❌ Skipped (non-permissive license)\n"
        else:
            summary += "- **Fat Image**: ❌ Skipped (unknown reason)\n"

    summary += f"""
### Image Tags

**Slim**:
"""

    # Generate tag list
    if matrix_entry.get("publish_ghcr", True):
        summary += f"- `{reg_ghcr}/{image}:{version}-slim`\n"
        summary += f"- `{reg_ghcr}/{image}:r{revision[:7]}-slim`\n"

    if matrix_entry.get("publish_dh", True):
        summary += f"- `{reg_dh}/{image}:{version}-slim`\n"
        summary += f"- `{reg_dh}/{image}:r{revision[:7]}-slim`\n"

    if build_fat:
        summary += "\n**Fat**:\n"
        if matrix_entry.get("publish_ghcr", True):
            summary += f"- `{reg_ghcr}/{image}:{version}-fat`\n"
            summary += f"- `{reg_ghcr}/{image}:r{revision[:7]}-fat`\n"

        if matrix_entry.get("publish_dh", True):
            summary += f"- `{reg_dh}/{image}:{version}-fat`\n"
            summary += f"- `{reg_dh}/{image}:r{revision[:7]}-fat`\n"

    summary += f"""
### Compliance
- **Licenses Bundled**: {'✅ Yes (/licenses/)' if build_fat else 'N/A (slim only)'}
- **OCI Labels**: ✅ Applied
- **Security Scan**: See Trivy results below

### Usage

**Slim** (downloads model at runtime):
```bash
docker run -p 8000:8000 \\
  -v $(pwd)/models:/models \\
  -e HUGGING_FACE_HUB_TOKEN=your_token \\
  {reg_ghcr}/{image}:{version}-slim
```
"""

    if build_fat:
        summary += f"""
**Fat** (model embedded):
```bash
docker run -p 8000:8000 \\
  {reg_ghcr}/{image}:{version}-fat
```
"""

    summary += "\n---\n"

    return summary


def main():
    """Main entry point."""
    parser = argparse.ArgumentParser(description="Generate build summary")
    parser.add_argument("--matrix", required=True, help="JSON matrix entry")
    parser.add_argument("--reg-ghcr", default="ghcr.io/13fragments", help="GHCR registry path")
    parser.add_argument("--reg-dh", default="13fragments", help="Docker Hub registry path")

    args = parser.parse_args()

    try:
        matrix_entry = json.loads(args.matrix)
    except json.JSONDecodeError as e:
        print(f"Error parsing matrix JSON: {e}", file=sys.stderr)
        sys.exit(1)

    summary = generate_summary(matrix_entry, args.reg_ghcr, args.reg_dh)
    print(summary)


if __name__ == "__main__":
    main()