# vLLM Model Image Publisher

Config-driven Docker image builder for vLLM + Hugging Face models. Automatically publishes **slim** (runtime download) and **fat** (embedded weights) image variants to GHCR and Docker Hub.

## Features

- **Two image variants per model**:
  - **Slim**: Downloads model weights at runtime to a mounted volume
  - **Fat**: Embeds model weights in the image (only for permissive-licensed, non-gated models)
- **Automatic license compliance**: Harvests LICENSE/NOTICE from HF, vendors SPDX text when needed
- **Multi-registry publishing**: GHCR (`ghcr.io/13fragments`) and Docker Hub (`13fragments`)
- **Security scanning**: Trivy integration with vulnerability reporting
- **One-config-entry workflow**: Add a model by editing `models.yaml`; CI does the rest

## Quick Start

### Pull and Run

**Slim image** (downloads model at startup):
```bash
docker run -p 8000:8000 \
  -v $(pwd)/models:/models \
  -e HUGGING_FACE_HUB_TOKEN=your_token \
  ghcr.io/13fragments/hf-deepseek-r1-distill-qwen-15b:v0.6.0-slim
```

**Fat image** (model embedded):
```bash
docker run -p 8000:8000 \
  ghcr.io/13fragments/hf-deepseek-r1-distill-qwen-15b:v0.6.0-fat
```

### Adding a New Model

1. Edit `models.yaml`:
```yaml
models:
  - id: "your-org/your-model"
    short: "your-model-short-name"
    revision: null                    # optional: specific commit SHA
    permissive: auto                  # auto | true | false
    gated: auto                       # auto | true | false
    serve_args: ["--host", "0.0.0.0", "--port", "8000"]
    oci:
      title: "vLLM + Your Model"
      description: "Slim/Fat images; see /licenses"
      url: "https://huggingface.co/your-org/your-model"
    publish:
      ghcr: true
      dockerhub: true
```

2. Commit to `main` → CI builds and publishes automatically

## Configuration Schema

### `models.yaml` Structure

```yaml
defaults:
  base_image: "vllm/vllm-openai:v0.6.0"
  arch: "linux/amd64"
  download_root: "/models"
  hf_cache_dir: "/root/.cache/huggingface"
  spdx_permissive_whitelist:
    - apache-2.0
    - mit
    - bsd-2-clause
    - bsd-3-clause
    - isc
    - cc0-1.0
    - unlicense
  publish:
    ghcr: true
    dockerhub: true

models:
  - id: "org/model-name"              # Required: HF repo ID
    short: "model-short-name"         # Required: kebab-case short name
    revision: null                    # Optional: HF commit SHA (default: latest)
    permissive: auto                  # auto | true | false
    override_spdx: null               # Optional: force SPDX ID
    gated: auto                       # auto | true | false
    serve_args: ["--host", "0.0.0.0", "--port", "8000"]
    oci:
      title: "vLLM + Model Name"
      description: "Image description"
      url: "https://huggingface.co/org/model-name"
    publish:
      ghcr: true
      dockerhub: true
```

### Policy Rules

- **`permissive: auto`**: Checks HF license metadata against whitelist
- **`gated: auto`**: Detects gated status via HF API
- **Fat images** are built only if:
  - License is permissive (per whitelist or `permissive: true`)
  - Model is not gated
- **Slim images** are always built

## Local Development

### Prerequisites

- Docker with Buildx
- Python 3.11+
- `make`

### Install Dependencies

```bash
pip install -r requirements.txt
```

### Build Locally

```bash
# Build slim image
make build-slim MODEL=deepseek-ai/DeepSeek-R1-Distill-Qwen-1.5B SHORT=deepseek-r1-distill-qwen-15b

# Build fat image (requires license harvesting)
make build-fat MODEL=deepseek-ai/DeepSeek-R1-Distill-Qwen-1.5B SHORT=deepseek-r1-distill-qwen-15b
```

### Run Locally

```bash
# Run slim (provide HF_TOKEN for gated models)
make run-slim MODEL=deepseek-ai/DeepSeek-R1-Distill-Qwen-1.5B SHORT=deepseek-r1-distill-qwen-15b HF_TOKEN=hf_xxx

# Run fat
make run-fat MODEL=deepseek-ai/DeepSeek-R1-Distill-Qwen-1.5B SHORT=deepseek-r1-distill-qwen-15b
```

### Test Configuration

```bash
make test
```

## Image Naming & Tagging

**Pattern**: `<registry>/hf-<model-short>:<tag>`

**Examples**:
- `ghcr.io/13fragments/hf-deepseek-r1-distill-qwen-15b:v0.6.0-slim`
- `13fragments/hf-deepseek-r1-distill-qwen-15b:r<sha>-fat`

**Tags**:
- `<version>-slim` / `<version>-fat`: vLLM version + variant
- `r<model-sha>-slim` / `r<model-sha>-fat`: Model revision + variant

## Runtime Requirements

### Slim Images

- **Volume mount**: `-v /host/path:/models` (for model persistence)
- **HF Token** (gated models): `-e HUGGING_FACE_HUB_TOKEN=hf_xxx`
- **First run**: Downloads model (may take minutes depending on size)
- **Subsequent runs**: Uses cached model from volume

### Fat Images

- **No volume mount needed**: Model embedded in image
- **No HF token needed**: Weights pre-downloaded
- **Larger image size**: Full model included in layers

## License Compliance

### Infrastructure Code
- **License**: CC0-1.0 (public domain dedication)
- **Location**: `/licenses/CC0` in fat images

### Model Licenses
- Fat images include `/licenses/model/LICENSE` (upstream or vendored SPDX)
- Fat images include `/licenses/model/NOTICE` if present upstream
- OCI labels declare all licenses

### Policy
- **Permissive whitelist**: apache-2.0, mit, bsd-*, isc, cc0-1.0, unlicense
- **Non-permissive/gated**: Slim-only (no weight redistribution)
- **Unknown license**: Defaults to slim-only (safe default)

## CI/CD Pipeline

### Triggers
- Push to `main`
- Manual workflow dispatch

### Jobs
1. **Prepare**: Parse `models.yaml` → generate build matrix
2. **Build** (per model):
   - Harvest licenses from HF
   - Build & push slim to GHCR + Docker Hub
   - Build & push fat (if permitted) to GHCR + Docker Hub
   - Trivy security scan
   - Generate job summary

### Required Secrets
- `GITHUB_TOKEN` (automatic): GHCR publishing
- `DOCKERHUB_USERNAME`: Docker Hub username
- `DOCKERHUB_TOKEN`: Docker Hub access token

## Architecture

```
.
├── .ci/
│   ├── resolve_models.py     # Parse config, query HF API, output matrix
│   ├── harvest_licenses.py   # Fetch LICENSE/NOTICE, vendor SPDX
│   └── summary.py            # Generate job summary markdown
├── docker/
│   ├── Dockerfile.slim       # Runtime model download
│   └── Dockerfile.fat        # Embedded weights + licenses
├── slim/
│   └── entrypoint.sh         # Bootstrap script for slim images
├── .github/workflows/
│   └── build-publish.yml     # CI/CD pipeline
├── models.yaml               # Model configuration
├── Makefile                  # Local development targets
└── README.md
```

## Published Images

All images are available at:
- **GHCR**: `ghcr.io/13fragments/hf-<model>`
- **Docker Hub**: `13fragments/hf-<model>`

### Current Models
- `hf-deepseek-r1-distill-qwen-15b` (DeepSeek-R1-Distill-Qwen-1.5B)

## Troubleshooting

### Slim image fails to download model
- **Cause**: Gated model without HF token
- **Fix**: Provide `-e HUGGING_FACE_HUB_TOKEN=hf_xxx`

### Fat image build fails
- **Cause**: Model is gated or non-permissive
- **Fix**: Check `permissive` and `gated` settings; use slim image instead

### Security scan fails
- **Cause**: HIGH/CRITICAL vulnerabilities in base image
- **Fix**: Update `base_image` in `models.yaml` to newer vLLM version

## Contributing

1. Fork the repository
2. Add your model to `models.yaml`
3. Test locally: `make test && make build-slim`
4. Submit PR

## License

Infrastructure code: **CC0-1.0** (see `LICENSE`)

Individual models and vLLM: See respective licenses in `/licenses/` within images.

## Support

- **Issues**: https://github.com/13fragments/vllm-models/issues
- **vLLM Docs**: https://docs.vllm.ai
- **HuggingFace**: https://huggingface.co