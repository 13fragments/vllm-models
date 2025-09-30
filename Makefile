.PHONY: help build-slim build-fat run-slim run-fat test clean

# Default values
MODEL ?= deepseek-ai/DeepSeek-R1-Distill-Qwen-1.5B
SHORT ?= deepseek-r1-distill-qwen-15b
VARIANT ?= slim
BASE_IMAGE ?= vllm/vllm-openai:v0.6.0
IMAGE_NAME ?= hf-$(SHORT)
TAG ?= local
HF_TOKEN ?=
PORT ?= 8000

help:
	@echo "vLLM Model Image Builder - Local Testing"
	@echo ""
	@echo "Usage:"
	@echo "  make build-slim MODEL=org/model-name SHORT=short-name"
	@echo "  make build-fat MODEL=org/model-name SHORT=short-name"
	@echo "  make run-slim MODEL=org/model-name SHORT=short-name HF_TOKEN=hf_xxx"
	@echo "  make run-fat MODEL=org/model-name SHORT=short-name"
	@echo ""
	@echo "Variables:"
	@echo "  MODEL      - HuggingFace model ID (default: $(MODEL))"
	@echo "  SHORT      - Short name for image (default: $(SHORT))"
	@echo "  VARIANT    - slim or fat (default: $(VARIANT))"
	@echo "  BASE_IMAGE - vLLM base image (default: $(BASE_IMAGE))"
	@echo "  TAG        - Image tag (default: $(TAG))"
	@echo "  HF_TOKEN   - HuggingFace token for gated models"
	@echo "  PORT       - Port to expose (default: $(PORT))"

build-slim:
	@echo "Building slim image for $(MODEL)..."
	docker build \
		--build-arg BASE_IMAGE=$(BASE_IMAGE) \
		--build-arg MODEL_ID=$(MODEL) \
		--build-arg MODEL_DIR=/models/$(SHORT) \
		--tag $(IMAGE_NAME):$(TAG)-slim \
		-f docker/Dockerfile.slim \
		.
	@echo "✓ Built: $(IMAGE_NAME):$(TAG)-slim"

build-fat: harvest-licenses
	@echo "Building fat image for $(MODEL)..."
	docker build \
		--build-arg BASE_IMAGE=$(BASE_IMAGE) \
		--build-arg MODEL_ID=$(MODEL) \
		--build-arg MODEL_DIR=/models/$(SHORT) \
		--tag $(IMAGE_NAME):$(TAG)-fat \
		-f docker/Dockerfile.fat \
		.
	@echo "✓ Built: $(IMAGE_NAME):$(TAG)-fat"

harvest-licenses:
	@echo "Harvesting licenses for $(MODEL)..."
	@mkdir -p licenses
	python3 .ci/harvest_licenses.py \
		--id $(MODEL) \
		--out licenses
	@echo "✓ Licenses harvested to licenses/"

run-slim:
	@echo "Running slim image: $(IMAGE_NAME):$(TAG)-slim"
	@echo "Model will be downloaded at first start (may take several minutes)"
	@if [ -z "$(HF_TOKEN)" ]; then \
		echo "Note: No HF_TOKEN provided. This may fail for gated models."; \
	fi
	docker run --rm -it \
		-p $(PORT):8000 \
		-v $(PWD)/models:/models \
		$(if $(HF_TOKEN),-e HUGGING_FACE_HUB_TOKEN=$(HF_TOKEN),) \
		-e MODEL_ID=$(MODEL) \
		-e MODEL_DIR=/models/$(SHORT) \
		$(IMAGE_NAME):$(TAG)-slim

run-fat:
	@echo "Running fat image: $(IMAGE_NAME):$(TAG)-fat"
	docker run --rm -it \
		-p $(PORT):8000 \
		$(IMAGE_NAME):$(TAG)-fat

test:
	@echo "Running smoke test..."
	@echo "Testing resolve_models.py..."
	python3 .ci/resolve_models.py models.yaml > /tmp/matrix.json
	@echo "✓ Matrix generated"
	@cat /tmp/matrix.json | python3 -m json.tool > /dev/null
	@echo "✓ Valid JSON"

clean:
	@echo "Cleaning up..."
	rm -rf licenses/
	rm -rf models/
	docker rmi -f $(IMAGE_NAME):$(TAG)-slim $(IMAGE_NAME):$(TAG)-fat 2>/dev/null || true
	@echo "✓ Cleaned"

.DEFAULT_GOAL := help