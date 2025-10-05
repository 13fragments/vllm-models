#!/bin/bash
set -e

# Local Build and Push Script
# Build Docker images locally and push to GHCR
# Use this when GitHub Actions runners run out of disk space

MODEL_ID="${1:-deepseek-ai/DeepSeek-R1-Distill-Qwen-1.5B}"
MODEL_SHORT="${2:-deepseek-r1-distill-qwen-15b}"
BASE_IMAGE="${3:-vllm/vllm-openai:v0.6.0}"
REGISTRY="${4:-ghcr.io/13fragments}"

# Extract version from base image
VERSION=$(echo "$BASE_IMAGE" | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' || echo "latest")

IMAGE_NAME="hf-${MODEL_SHORT}"
MODEL_DIR="/models/${MODEL_SHORT}"
HF_CACHE="/root/.cache/huggingface"
SERVE_ARGS="--host 0.0.0.0 --port 8000"

echo "========================================================================"
echo "Local Build and Push for vLLM Model Images"
echo "========================================================================"
echo ""
echo "Configuration:"
echo "  Model ID: ${MODEL_ID}"
echo "  Short name: ${MODEL_SHORT}"
echo "  Base image: ${BASE_IMAGE}"
echo "  Registry: ${REGISTRY}"
echo "  Image name: ${IMAGE_NAME}"
echo "  Version: ${VERSION}"
echo ""

# Check Docker is running
if ! docker info > /dev/null 2>&1; then
    echo "✗ Docker is not running. Please start Docker Desktop."
    exit 1
fi

# Check GHCR login
echo "[1/5] Checking authentication..."
if ! docker pull "${REGISTRY}/${IMAGE_NAME}:${VERSION}-slim" 2>/dev/null | grep -q "Image is up to date" 2>/dev/null; then
    echo "  You need to login to GHCR first:"
    echo "  export GITHUB_TOKEN=your_github_pat"
    echo "  echo \$GITHUB_TOKEN | docker login ghcr.io -u YOUR_USERNAME --password-stdin"
    read -p "  Press Enter after logging in, or Ctrl+C to exit..."
fi

# Harvest licenses (for fat image)
echo ""
echo "[2/5] Harvesting licenses..."
if [ -f ".ci/harvest_licenses.py" ]; then
    python3 .ci/harvest_licenses.py \
        --id "${MODEL_ID}" \
        --license "mit" \
        --out licenses 2>&1 || {
        echo "  ⚠ License harvest requires Python dependencies:"
        echo "    pip install -r requirements.txt"
        echo "  Continuing with placeholder licenses..."
    }
else
    echo "  ⚠ Harvest script not found, using placeholder"
fi

# Build slim image
echo ""
echo "[3/5] Building slim image..."
docker build \
    --build-arg BASE_IMAGE="${BASE_IMAGE}" \
    --build-arg MODEL_ID="${MODEL_ID}" \
    --build-arg MODEL_DIR="${MODEL_DIR}" \
    --build-arg HF_CACHE="${HF_CACHE}" \
    --build-arg SERVE_ARGS="${SERVE_ARGS}" \
    --tag "${REGISTRY}/${IMAGE_NAME}:${VERSION}-slim" \
    --tag "${REGISTRY}/${IMAGE_NAME}:latest-slim" \
    --file docker/Dockerfile.slim \
    --label "org.opencontainers.image.title=vLLM + ${MODEL_ID} (Slim)" \
    --label "org.opencontainers.image.source=https://github.com/13fragments/vllm-models" \
    --label "org.opencontainers.image.version=${VERSION}" \
    . && echo "✓ Slim image built" || {
    echo "✗ Slim build failed"
    exit 1
}

# Ask about fat image
echo ""
read -p "[4/5] Build fat image? (will download ${MODEL_ID}, ~3GB) [y/N]: " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "  Building fat image (this may take 10-30 minutes)..."
    docker build \
        --build-arg BASE_IMAGE="${BASE_IMAGE}" \
        --build-arg MODEL_ID="${MODEL_ID}" \
        --build-arg MODEL_DIR="${MODEL_DIR}" \
        --build-arg HF_CACHE="${HF_CACHE}" \
        --build-arg SERVE_ARGS="${SERVE_ARGS}" \
        --tag "${REGISTRY}/${IMAGE_NAME}:${VERSION}-fat" \
        --tag "${REGISTRY}/${IMAGE_NAME}:latest-fat" \
        --file docker/Dockerfile.fat \
        --label "org.opencontainers.image.title=vLLM + ${MODEL_ID} (Fat)" \
        --label "org.opencontainers.image.source=https://github.com/13fragments/vllm-models" \
        --label "org.opencontainers.image.version=${VERSION}" \
        . && echo "✓ Fat image built" || {
        echo "✗ Fat build failed"
        exit 1
    }
    BUILD_FAT=true
else
    echo "  Skipping fat image build"
    BUILD_FAT=false
fi

# Push images
echo ""
echo "[5/5] Pushing images to ${REGISTRY}..."
echo "  Pushing slim image..."
docker push "${REGISTRY}/${IMAGE_NAME}:${VERSION}-slim" && \
docker push "${REGISTRY}/${IMAGE_NAME}:latest-slim" && \
echo "✓ Slim image pushed" || {
    echo "✗ Slim push failed"
    exit 1
}

if [ "$BUILD_FAT" = true ]; then
    echo "  Pushing fat image (this may take 20-60 minutes for large images)..."
    docker push "${REGISTRY}/${IMAGE_NAME}:${VERSION}-fat" && \
    docker push "${REGISTRY}/${IMAGE_NAME}:latest-fat" && \
    echo "✓ Fat image pushed" || {
        echo "✗ Fat push failed"
        exit 1
    }
fi

echo ""
echo "========================================================================"
echo "✓ Build and Push Complete!"
echo "========================================================================"
echo ""
echo "Images published:"
echo "  Slim: ${REGISTRY}/${IMAGE_NAME}:${VERSION}-slim"
if [ "$BUILD_FAT" = true ]; then
    echo "  Fat:  ${REGISTRY}/${IMAGE_NAME}:${VERSION}-fat"
fi
echo ""
echo "To use:"
echo "  docker run -p 8000:8000 -v \$(pwd)/models:/models \\"
echo "    ${REGISTRY}/${IMAGE_NAME}:${VERSION}-slim"
echo ""


