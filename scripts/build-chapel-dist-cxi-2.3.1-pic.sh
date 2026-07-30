#!/bin/bash
# Build script for Chapel-Arkouda server container with CXI provider support

set -e
set -o pipefail

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONVERT_SCRIPT="${SCRIPT_DIR}/convert-to-sif.sh"

# Version configurations (can be overridden with environment variables)
LIBFABRIC_VERSION=${LIBFABRIC_VERSION:-2.3.1}
SLURM_VERSION=${SLURM_VERSION:-25.05.3}
LIBICONV_VERSION=${LIBICONV_VERSION:-1.17}
ARROW_VERSION=${ARROW_VERSION:-19.0.1}
CHAPEL_VERSION=${CHAPEL_VERSION:-2.8.0}
ARKOUDA_VERSION=${ARKOUDA_VERSION:-2025.12.16}
CXI_VERSION=${CXI_VERSION:-release/shs-13.1.0}
CXI_DRIVER_COMMIT=${CXI_DRIVER_COMMIT:-3233be5}
LIBCXI_COMMIT=${LIBCXI_COMMIT:-ebd57a9}

# Build mode: "development" (fast iteration) or "production" (optimized)
BUILD_MODE=${BUILD_MODE:-production}

# Configuration
# Append build mode to container name if in development mode
if [ "${BUILD_MODE}" = "development" ]; then
    CONTAINER_NAME="chapel-${CHAPEL_VERSION}-libfabric-${LIBFABRIC_VERSION}-cxi-pic-dev"
else
    CONTAINER_NAME="chapel-${CHAPEL_VERSION}-libfabric-${LIBFABRIC_VERSION}-cxi-pic"
fi
CONTAINERFILE="Containerfile.hpe-cray-ex-chapel-pic"
PODMAN_IMAGE="localhost/${CONTAINER_NAME}:latest"
OUTPUT_SIF="${CONTAINER_NAME}.sif"

# Build container
echo "Building Chapel-Arkouda server container with CXI provider support..."
echo ""

if [ ! -f "$CONTAINERFILE" ]; then
    echo "ERROR: $CONTAINERFILE not found"
    exit 1
fi

# Copy patches/ and configs/ to context
cp -r $SCRIPT_DIR/../patches .
cp -r $SCRIPT_DIR/../configs .
mkdir -p ./scripts/
cp $SCRIPT_DIR/../scripts/startup-slurm-for-container.sh ./scripts/.
cp $SCRIPT_DIR/../scripts/slurm-start.sh ./scripts/.

# Create build log directory
BUILD_LOG_DIR="${PWD}/build-logs"
mkdir -p "$BUILD_LOG_DIR"
BUILD_LOG="${BUILD_LOG_DIR}/cxi-build-$(date +%Y%m%d_%H%M%S).log"

echo "Build log: $BUILD_LOG"
echo ""

# Log the command line and environment for reproducibility
{
    echo "=========================================="
    echo "Build started at: $(date)"
    echo "=========================================="
    echo ""
    echo "Command: $0 $@"
    echo "Working directory: $(pwd)"
    echo ""
    echo "Build configuration:"
} | tee "$BUILD_LOG"

# Build with Podman
echo "Building with versions:" | tee -a "$BUILD_LOG"
echo "  Build Mode=${BUILD_MODE}" | tee -a "$BUILD_LOG"
echo "  CHPL_TARGET_CPU=none" | tee -a "$BUILD_LOG"
echo "  libfabric=${LIBFABRIC_VERSION}" | tee -a "$BUILD_LOG"
echo "  SLURM=${SLURM_VERSION}" | tee -a "$BUILD_LOG"
echo "  libiconv=${LIBICONV_VERSION}" | tee -a "$BUILD_LOG"
echo "  Arrow=${ARROW_VERSION}" | tee -a "$BUILD_LOG"
echo "  Chapel=${CHAPEL_VERSION}" | tee -a "$BUILD_LOG"
echo "  Arkouda=${ARKOUDA_VERSION}" | tee -a "$BUILD_LOG"
echo "  CXI Version=${CXI_VERSION}" | tee -a "$BUILD_LOG"
echo "  CXI Driver Commit=${CXI_DRIVER_COMMIT}" | tee -a "$BUILD_LOG"
echo "  CXI libcxi Commit=${LIBCXI_COMMIT}" | tee -a "$BUILD_LOG"
echo "" | tee -a "$BUILD_LOG"
if [ "${BUILD_MODE}" = "development" ]; then
    echo "==> DEVELOPMENT BUILD: Quick compile, single-dim arrays, CHPL_LLVM=system" | tee -a "$BUILD_LOG"
else
    echo "==> PRODUCTION BUILD: Optimized compile, 3D arrays, CHPL_LLVM=system" | tee -a "$BUILD_LOG"
fi
echo "" | tee -a "$BUILD_LOG"

docker build --progress plain -t "$PODMAN_IMAGE" -f "$CONTAINERFILE" \
    --build-arg NCPUS=$(nproc) \
    --build-arg BUILD_MODE="$BUILD_MODE" \
    --build-arg LIBFABRIC_VERSION="$LIBFABRIC_VERSION" \
    --build-arg SLURM_VERSION="$SLURM_VERSION" \
    --build-arg LIBICONV_VERSION="$LIBICONV_VERSION" \
    --build-arg ARROW_VERSION="$ARROW_VERSION" \
    --build-arg CHAPEL_VERSION="$CHAPEL_VERSION" \
    --build-arg ARKOUDA_VERSION="$ARKOUDA_VERSION" \
    --build-arg CXI_VERSION="$CXI_VERSION" \
    --build-arg CXI_DRIVER_COMMIT="$CXI_DRIVER_COMMIT" \
    --build-arg LIBCXI_COMMIT="$LIBCXI_COMMIT" \
    . 2>&1 | tee -a "$BUILD_LOG"

BUILD_EXIT_CODE=$?
echo "Build completed at: $(date)" | tee -a "$BUILD_LOG"
echo "Final disk space: $(df -h . | tail -1 | awk '{print $4}')" | tee -a "$BUILD_LOG"
if [ $BUILD_EXIT_CODE -ne 0 ]; then
    echo "Podman build failed with exit code: $BUILD_EXIT_CODE" | tee -a "$BUILD_LOG"
    exit 1
fi

rm -rf $SCRIPT_DIR/../containers/patches $SCRIPT_DIR/../containers/configs

# Convert to SIF using shared conversion script
echo "Converting to SIF format using convert-to-sif.sh..." | tee -a "$BUILD_LOG"
"$CONVERT_SCRIPT" "$PODMAN_IMAGE" --filename "$CONTAINER_NAME" --output-dir "$(pwd)" --force 2>&1 | tee -a "$BUILD_LOG"
CONVERT_EXIT_CODE=$?

if [ $CONVERT_EXIT_CODE -eq 0 ]; then
    echo "Build successful: $OUTPUT_SIF" | tee -a "$BUILD_LOG"

    # Quick test
    echo "=== Quick Test ===" | tee -a "$BUILD_LOG"
    echo "Testing if Arkouda server executable exists..." | tee -a "$BUILD_LOG"
    apptainer exec "$OUTPUT_SIF" ls -la /opt/arkouda/arkouda_server_real 2>&1 | tee -a "$BUILD_LOG" || echo "Arkouda server not found" | tee -a "$BUILD_LOG"

    echo "" | tee -a "$BUILD_LOG"
    echo "Checking if libfabric has CXI provider compiled..." | tee -a "$BUILD_LOG"
    apptainer exec "$OUTPUT_SIF" strings /opt/libfabric/lib/libfabric.so.1 | grep -i cxi | head -10 2>&1 | tee -a "$BUILD_LOG" || echo "CXI strings not found in libfabric" | tee -a "$BUILD_LOG"

else
    echo "SIF conversion failed" | tee -a "$BUILD_LOG"
    exit 1
fi
