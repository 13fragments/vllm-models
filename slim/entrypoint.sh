#!/bin/bash
set -euo pipefail

# Entrypoint script for slim vLLM images
# Downloads model at runtime if not already present

MODEL_ID="${MODEL_ID:-}"
MODEL_DIR="${MODEL_DIR:-/models/model}"
SERVE_ARGS="${SERVE_ARGS:---host 0.0.0.0 --port 8000}"

if [ -z "$MODEL_ID" ]; then
    echo "ERROR: MODEL_ID environment variable is required" >&2
    exit 1
fi

echo "=== vLLM Slim Image Bootstrap ==="
echo "Model ID: $MODEL_ID"
echo "Model directory: $MODEL_DIR"
echo "Serve args: $SERVE_ARGS"

# Check if model directory exists and has content
if [ -d "$MODEL_DIR" ] && [ "$(ls -A "$MODEL_DIR" 2>/dev/null)" ]; then
    echo "✓ Model already present in $MODEL_DIR"
else
    echo "→ Downloading model to $MODEL_DIR..."
    mkdir -p "$MODEL_DIR"

    # Download model using huggingface-cli
    # This will use HUGGING_FACE_HUB_TOKEN env var if set (required for gated models)
    if ! huggingface-cli download "$MODEL_ID" --local-dir "$MODEL_DIR" --local-dir-use-symlinks False; then
        echo "ERROR: Failed to download model" >&2
        echo "Hint: For gated models, set HUGGING_FACE_HUB_TOKEN environment variable" >&2
        exit 1
    fi

    echo "✓ Model downloaded successfully"
fi

echo "=== Starting vLLM server ==="
echo "Command: vllm serve $MODEL_DIR $SERVE_ARGS"

# Start vLLM server with the downloaded model
exec vllm serve "$MODEL_DIR" $SERVE_ARGS