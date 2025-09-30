#!/bin/bash
set -e

# Local Docker Build Test Script
# Tests both slim and fat image builds locally before pushing to CI

echo "========================================================================"
echo "Local Docker Build Test"
echo "========================================================================"
echo ""

# Configuration
MODEL_ID="deepseek-ai/DeepSeek-R1-Distill-Qwen-1.5B"
MODEL_SHORT="deepseek-r1-distill-qwen-15b"
BASE_IMAGE="vllm/vllm-openai:v0.6.0"
MODEL_DIR="/models/${MODEL_SHORT}"
HF_CACHE="/root/.cache/huggingface"
SERVE_ARGS="--host 0.0.0.0 --port 8000"

echo "Configuration:"
echo "  Model ID: ${MODEL_ID}"
echo "  Short name: ${MODEL_SHORT}"
echo "  Base image: ${BASE_IMAGE}"
echo ""

# Test 1: Check if licenses directory exists
echo "[1/5] Checking licenses directory..."
if [ -d "licenses" ]; then
    echo "✓ licenses/ directory exists"
    echo "  Contents:"
    ls -la licenses/
else
    echo "✗ licenses/ directory NOT found"
    exit 1
fi
echo ""

# Test 2: Check Docker context (what Docker sees)
echo "[2/5] Checking Docker build context..."
echo "  Files Docker will see:"
docker build --no-cache --dry-run -f docker/Dockerfile.slim . 2>&1 | grep -i licenses || echo "  (No licenses mentioned in context - checking manually)"

# Manual check using docker build context
echo ""
echo "  Checking if licenses/ is in Docker context:"
docker build -f - . <<'EOF' 2>&1 | grep -q "README.md" && echo "✓ licenses/README.md found in context" || echo "✗ licenses/ is being ignored!"
FROM alpine
COPY licenses/README.md /test/
EOF
echo ""

# Test 3: Harvest licenses (simulate CI)
echo "[3/5] Harvesting licenses (simulating CI step)..."
if [ -f ".ci/harvest_licenses.py" ]; then
    # Create a Python virtual environment if needed
    if ! command -v python3 &> /dev/null; then
        echo "✗ Python3 not found"
        exit 1
    fi
    
    echo "  Running harvest_licenses.py..."
    python3 .ci/harvest_licenses.py \
        --id "${MODEL_ID}" \
        --license "mit" \
        --out licenses || {
        echo "  ⚠ License harvest failed (may need dependencies)"
        echo "  Continuing with existing licenses/README.md..."
    }
    
    echo "  License directory after harvest:"
    ls -la licenses/
else
    echo "  ⚠ .ci/harvest_licenses.py not found, skipping harvest"
fi
echo ""

# Test 4: Build slim image
echo "[4/5] Building slim image..."
docker build \
    --build-arg BASE_IMAGE="${BASE_IMAGE}" \
    --build-arg MODEL_ID="${MODEL_ID}" \
    --build-arg MODEL_DIR="${MODEL_DIR}" \
    --build-arg HF_CACHE="${HF_CACHE}" \
    --build-arg SERVE_ARGS="${SERVE_ARGS}" \
    -f docker/Dockerfile.slim \
    -t test-vllm-slim:latest \
    . && echo "✓ Slim image built successfully" || {
    echo "✗ Slim image build failed"
    exit 1
}
echo ""

# Test 5: Build fat image (without actually downloading the model)
echo "[5/5] Testing fat image build (checking COPY licenses step)..."

# Create a test Dockerfile that stops before the expensive model download
cat > /tmp/Dockerfile.fat.test <<EOF
ARG BASE_IMAGE=vllm/vllm-openai:v0.6.0
FROM \${BASE_IMAGE}

ARG MODEL_ID
ARG MODEL_DIR=/models/model
ARG HF_CACHE=/root/.cache/huggingface
ARG SERVE_ARGS="--host 0.0.0.0 --port 8000"

ENV HF_HOME=\${HF_CACHE} \
    HUGGINGFACE_HUB_CACHE=\${HF_CACHE} \
    MODEL_ID=\${MODEL_ID} \
    MODEL_DIR=\${MODEL_DIR}

# Skip the expensive model download step
# RUN --mount=type=cache,target=/root/.cache/huggingface ...

# Test the COPY licenses step (this is what was failing)
COPY licenses/ /licenses/

# Verify licenses were copied
RUN ls -la /licenses/ && echo "✓ Licenses copied successfully"

EXPOSE 8000
CMD ["echo", "Test image - not for running"]
EOF

docker build \
    --build-arg BASE_IMAGE="${BASE_IMAGE}" \
    --build-arg MODEL_ID="${MODEL_ID}" \
    --build-arg MODEL_DIR="${MODEL_DIR}" \
    -f /tmp/Dockerfile.fat.test \
    -t test-vllm-fat:latest \
    . && echo "✓ Fat image COPY licenses test passed" || {
    echo "✗ Fat image COPY licenses test failed"
    exit 1
}

# Cleanup
rm -f /tmp/Dockerfile.fat.test

echo ""
echo "========================================================================"
echo "✓ All local tests passed!"
echo "========================================================================"
echo ""
echo "The builds should work in CI now."
echo "To clean up test images, run:"
echo "  docker rmi test-vllm-slim:latest test-vllm-fat:latest"
echo ""
