#!/bin/bash
# Build script for Chapel-Arkouda server container

set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONVERT_SCRIPT="${SCRIPT_DIR}/convert-to-sif.sh"

# Version configurations (can be overridden with environment variables)
LIBFABRIC_VERSION=${LIBFABRIC_VERSION:-1.19.0}
SLURM_VERSION=${SLURM_VERSION:-23.02.7}
MPICH_VERSION=${MPICH_VERSION:-4.1.2}
LIBICONV_VERSION=${LIBICONV_VERSION:-1.17}
ARROW_VERSION=${ARROW_VERSION:-19.0.1-1}
CHAPEL_VERSION=${CHAPEL_VERSION:-2.6.0}
ARKOUDA_VERSION=${ARKOUDA_VERSION:-2025.12.16}

# Configuration
CONTAINER_NAME="chapel-${CHAPEL_VERSION}-arkouda-${ARKOUDA_VERSION}"
CONTAINERFILE="Containerfile.chapel-arkouda"
PODMAN_IMAGE="localhost/${CONTAINER_NAME}:latest"
OUTPUT_SIF="${CONTAINER_NAME}.sif"

# Build container
echo "Building Chapel-Arkouda server container..."

if [ ! -f "$CONTAINERFILE" ]; then
    echo "ERROR: $CONTAINERFILE not found"
    exit 1
fi

# Copy patches/ to context
cp -r $SCRIPT_DIR/../patches .

# Build with Podman
echo "Building with versions: libfabric=${LIBFABRIC_VERSION}, SLURM=${SLURM_VERSION}, MPICH=${MPICH_VERSION}, libiconv=${LIBICONV_VERSION}, Arrow=${ARROW_VERSION}, Chapel=${CHAPEL_VERSION}, Arkouda=${ARKOUDA_VERSION}"

podman build -t "$PODMAN_IMAGE" -f "$CONTAINERFILE" \
    --build-arg NCPUS=$(nproc) \
    --build-arg LIBFABRIC_VERSION="$LIBFABRIC_VERSION" \
    --build-arg SLURM_VERSION="$SLURM_VERSION" \
    --build-arg MPICH_VERSION="$MPICH_VERSION" \
    --build-arg LIBICONV_VERSION="$LIBICONV_VERSION" \
    --build-arg ARROW_VERSION="$ARROW_VERSION" \
    --build-arg CHAPEL_VERSION="$CHAPEL_VERSION" \
    --build-arg ARKOUDA_VERSION="$ARKOUDA_VERSION" \
    .
BUILD_EXIT_CODE=$?
echo "Build completed at: $(date)"
echo "Final disk space: $(df -h . | tail -1 | awk '{print $4}')"
if [ $BUILD_EXIT_CODE -ne 0 ]; then
    echo "Podman build failed with exit code: $BUILD_EXIT_CODE"
    exit 1
fi

rm -rf $SCRIPT_DIR/../containers/patches

# Convert to SIF using shared conversion script
echo "Converting to SIF format using convert-to-sif.sh..."
"$CONVERT_SCRIPT" "$PODMAN_IMAGE" --filename "$CONTAINER_NAME" --output-dir "$(pwd)"
CONVERT_EXIT_CODE=$?

if [ $CONVERT_EXIT_CODE -eq 0 ]; then
    echo "Build successful: $OUTPUT_SIF"

    # Quick test
    echo "=== Quick Test ==="
    apptainer exec "$OUTPUT_SIF" chpl --version
    echo "Testing Arkouda server executable..."
    apptainer exec "$OUTPUT_SIF" ls -la /opt/arkouda/arkouda_server_real || echo "Arkouda server not found"

    echo "Container ready for use"
    echo "Usage: apptainer exec --bind <workspace_path> $OUTPUT_SIF /opt/arkouda/arkouda-server"
else
    echo "SIF conversion failed"
    exit 1
fi
