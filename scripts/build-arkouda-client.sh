#!/bin/bash
# Build script for Arkouda client container

set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONVERT_SCRIPT="${SCRIPT_DIR}/convert-to-sif.sh"

# Version configurations (can be overridden with environment variables)
ARROW_VERSION=${ARROW_VERSION:-19.0.1}
ARKOUDA_VERSION=${ARKOUDA_VERSION:-2025.12.16}

# Configuration
CONTAINER_NAME="arkouda-${ARKOUDA_VERSION}-client"
CONTAINERFILE="Containerfile.arkouda-client"
PODMAN_IMAGE="localhost/${CONTAINER_NAME}:latest"
OUTPUT_SIF="${CONTAINER_NAME}.sif"



# Build container
echo "Building Arkouda client container..."

if [ ! -f "$CONTAINERFILE" ]; then
    echo "ERROR: $CONTAINERFILE not found"
    exit 1
fi

# Copy patch files from patches directory to build context
cp ../patches/conftest.patch .
cp ../patches/arkouda_index_test_temp_fix.patch .

# Clean previous builds
podman rmi "$PODMAN_IMAGE" 2>/dev/null || true
rm -f "$OUTPUT_SIF"

# Build with Podman
echo "Building with Arrow version: ${ARROW_VERSION}, Arkouda version: ${ARKOUDA_VERSION}"
podman build -t "$PODMAN_IMAGE" -f "$CONTAINERFILE" \
    --build-arg ARROW_VERSION="$ARROW_VERSION" \
    --build-arg ARKOUDA_VERSION="$ARKOUDA_VERSION" \
    .
if [ $? -ne 0 ]; then
    echo "Podman build failed"
    exit 1
fi

# Convert to SIF using shared conversion script
echo "Converting to SIF format using convert-to-sif.sh..."
"$CONVERT_SCRIPT" "$PODMAN_IMAGE" --filename "$CONTAINER_NAME" --output-dir "$(pwd)"
CONVERT_EXIT_CODE=$?

if [ $CONVERT_EXIT_CODE -eq 0 ]; then
    echo "Build successful: $OUTPUT_SIF"

    # Clean up copied patch files
    rm -f *.patch

    # Verify build
    apptainer exec "$OUTPUT_SIF" python3 -c "import arkouda; print('Arkouda client ready')"

    echo "Container ready for use"
    echo "Usage: apptainer exec --bind <workspace_path> $OUTPUT_SIF python3 <arkouda_script>"
else
    echo "SIF conversion failed"
    exit 1
fi
