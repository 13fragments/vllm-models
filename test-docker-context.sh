#!/bin/bash

# Quick test to see what files Docker would include in build context
# This doesn't require Docker to be running

echo "========================================================================"
echo "Docker Build Context Test"
echo "========================================================================"
echo ""

echo "[1/2] Checking if licenses/ directory exists..."
if [ -d "licenses" ]; then
    echo "✓ licenses/ directory exists in filesystem"
    ls -la licenses/
else
    echo "✗ licenses/ directory NOT found"
    exit 1
fi
echo ""

echo "[2/2] Checking .dockerignore for licenses exclusion..."
if grep -q "^licenses/" .dockerignore; then
    echo "✗ ERROR: licenses/ is still in .dockerignore!"
    echo "  This will prevent Docker from seeing the directory"
    exit 1
elif grep -q "licenses" .dockerignore; then
    echo "✓ .dockerignore mentions licenses but doesn't exclude it:"
    grep licenses .dockerignore
else
    echo "✓ licenses/ is NOT excluded by .dockerignore"
fi

echo ""
echo "========================================================================"
echo "✓ Build context should be correct"
echo "========================================================================"
echo ""
echo "The licenses/ directory will be available to Docker builds."
echo "Commit and push .dockerignore to fix the CI build."
echo ""
