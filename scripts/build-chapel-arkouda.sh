#!/bin/bash
# Build script for Chapel-Arkouda server container

set -e

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
OCI_ARCHIVE="${CONTAINER_NAME}-oci.tar"
OUTPUT_SIF="${CONTAINER_NAME}.sif"

# Build container
echo "Building Chapel-Arkouda server container..."

if [ ! -f "$CONTAINERFILE" ]; then
    echo "ERROR: $CONTAINERFILE not found"
    exit 1
fi

# Clean previous builds
podman rmi "$PODMAN_IMAGE" 2>/dev/null || true
rm -f "$OUTPUT_SIF" "$OCI_ARCHIVE"

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

# Save to OCI archive
podman save --format oci-archive -o "$OCI_ARCHIVE" "$PODMAN_IMAGE"
if [ $? -ne 0 ]; then
    echo "Podman save failed"
    exit 1
fi

# Convert to SIF format
apptainer build "$OUTPUT_SIF" "oci-archive:$OCI_ARCHIVE"

if [ $? -eq 0 ]; then
    echo "Build successful: $OUTPUT_SIF"
    rm -f "$OCI_ARCHIVE"

    # Quick test
    echo "=== Quick Test ==="
    apptainer exec "$OUTPUT_SIF" chpl --version
    echo "Testing Arkouda server executable..."
    apptainer exec "$OUTPUT_SIF" ls -la /opt/arkouda/arkouda_server_real || echo "Arkouda server not found"

    echo "Container ready for use"
    echo "Usage: apptainer exec --bind <workspace_path> $OUTPUT_SIF /opt/arkouda/arkouda-server"
else
    echo "SIF conversion failed"
    rm -f "$OCI_ARCHIVE"
    exit 1
fi
