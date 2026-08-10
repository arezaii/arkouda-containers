#!/bin/bash
# LEGACY - only used by containers/legacy/Containerfile.chapel-arkouda's from-source
# build. Kept for reference only; not actively maintained.
#
# download-build-dependencies.sh
# ==============================
# Pre-download source tarballs for container build
# This avoids SSL certificate issues and speeds up repeated builds

set -e

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
DOWNLOADS_DIR="${SCRIPT_DIR}/build-dependencies"

# Versions must match Containerfile
CHAPEL_VERSION=${CHAPEL_VERSION:-2.6.0}
ARKOUDA_VERSION=${ARKOUDA_VERSION:-2025.12.16}
LIBICONV_VERSION=${LIBICONV_VERSION:-1.17}
ARROW_VERSION=${ARROW_VERSION:-19.0.1}
LIBFABRIC_VERSION=${LIBFABRIC_VERSION:-2.3.1}
SLURM_VERSION=${SLURM_VERSION:-25.05.3}

echo -e "${BLUE}=== Downloading Build Dependencies ===${NC}"
echo "Download directory: ${DOWNLOADS_DIR}"
echo ""

# Create downloads directory
mkdir -p "${DOWNLOADS_DIR}"
cd "${DOWNLOADS_DIR}"

# Download Chapel
CHAPEL_URL="https://github.com/chapel-lang/chapel/archive/refs/tags/${CHAPEL_VERSION}.tar.gz"
CHAPEL_FILE="chapel-${CHAPEL_VERSION}.tar.gz"

if [ -f "${CHAPEL_FILE}" ]; then
    echo -e "${GREEN}✓ ${CHAPEL_FILE} already downloaded${NC}"
else
    echo -e "${YELLOW}Downloading ${CHAPEL_FILE}...${NC}"
    wget --no-check-certificate "${CHAPEL_URL}" -O "${CHAPEL_FILE}"
    echo -e "${GREEN}✓ Downloaded ${CHAPEL_FILE}${NC}"
fi

# Download Arkouda
ARKOUDA_URL="https://github.com/Bears-R-Us/arkouda/archive/refs/tags/v${ARKOUDA_VERSION}.tar.gz"
ARKOUDA_FILE="arkouda-${ARKOUDA_VERSION}.tar.gz"

if [ -f "${ARKOUDA_FILE}" ]; then
    echo -e "${GREEN}✓ ${ARKOUDA_FILE} already downloaded${NC}"
else
    echo -e "${YELLOW}Downloading ${ARKOUDA_FILE}...${NC}"
    wget --no-check-certificate "${ARKOUDA_URL}" -O "${ARKOUDA_FILE}"
    echo -e "${GREEN}✓ Downloaded ${ARKOUDA_FILE}${NC}"
fi

# Download libiconv
LIBICONV_URL="https://ftp.gnu.org/pub/gnu/libiconv/libiconv-${LIBICONV_VERSION}.tar.gz"
LIBICONV_FILE="libiconv-${LIBICONV_VERSION}.tar.gz"

if [ -f "${LIBICONV_FILE}" ]; then
    echo -e "${GREEN}✓ ${LIBICONV_FILE} already downloaded${NC}"
else
    echo -e "${YELLOW}Downloading ${LIBICONV_FILE}...${NC}"
    wget --no-check-certificate "${LIBICONV_URL}" -O "${LIBICONV_FILE}"
    echo -e "${GREEN}✓ Downloaded ${LIBICONV_FILE}${NC}"
fi

# Download Apache Arrow
ARROW_URL="https://github.com/apache/arrow/archive/refs/tags/apache-arrow-${ARROW_VERSION}.tar.gz"
ARROW_FILE="apache-arrow-${ARROW_VERSION}.tar.gz"

if [ -f "${ARROW_FILE}" ]; then
    echo -e "${GREEN}✓ ${ARROW_FILE} already downloaded${NC}"
else
    echo -e "${YELLOW}Downloading ${ARROW_FILE}...${NC}"
    wget --no-check-certificate "${ARROW_URL}" -O "${ARROW_FILE}"
    echo -e "${GREEN}✓ Downloaded ${ARROW_FILE}${NC}"
fi

# Download libfabric (needed for CXI builds)
LIBFABRIC_URL="https://github.com/ofiwg/libfabric/releases/download/v${LIBFABRIC_VERSION}/libfabric-${LIBFABRIC_VERSION}.tar.bz2"
LIBFABRIC_FILE="libfabric-${LIBFABRIC_VERSION}.tar.bz2"

if [ -f "${LIBFABRIC_FILE}" ]; then
    echo -e "${GREEN}✓ ${LIBFABRIC_FILE} already downloaded${NC}"
else
    echo -e "${YELLOW}Downloading ${LIBFABRIC_FILE}...${NC}"
    wget --no-check-certificate "${LIBFABRIC_URL}" -O "${LIBFABRIC_FILE}"
    echo -e "${GREEN}✓ Downloaded ${LIBFABRIC_FILE}${NC}"
fi

# Download SLURM (needed for CXI builds with PMI2 support)
SLURM_URL="https://download.schedmd.com/slurm/slurm-${SLURM_VERSION}.tar.bz2"
SLURM_FILE="slurm-${SLURM_VERSION}.tar.bz2"

if [ -f "${SLURM_FILE}" ]; then
    echo -e "${GREEN}✓ ${SLURM_FILE} already downloaded${NC}"
else
    echo -e "${YELLOW}Downloading ${SLURM_FILE}...${NC}"
    wget --no-check-certificate "${SLURM_URL}" -O "${SLURM_FILE}"
    echo -e "${GREEN}✓ Downloaded ${SLURM_FILE}${NC}"
fi

# Download Arrow bundled dependencies
ARROW_DEPS_DIR="${SCRIPT_DIR}/arrow-deps"
if [ -d "${ARROW_DEPS_DIR}" ] && [ -n "$(ls -A ${ARROW_DEPS_DIR} 2>/dev/null)" ]; then
    echo -e "${GREEN}✓ Arrow dependencies already downloaded${NC}"
else
    echo -e "${YELLOW}Downloading Arrow bundled dependencies...${NC}"

    # Create temporary directory for extraction
    TEMP_ARROW_DIR="/tmp/arrow-deps-download-$$"
    mkdir -p "${TEMP_ARROW_DIR}"

    # Extract Arrow source to get download_dependencies.sh script
    cd "${TEMP_ARROW_DIR}"
    tar -xzf "${DOWNLOADS_DIR}/${ARROW_FILE}"

    # Create arrow-deps directory in containers/
    mkdir -p "${ARROW_DEPS_DIR}"

    # Run Arrow's download script to fetch all bundled dependencies
    cd "arrow-apache-arrow-${ARROW_VERSION}/cpp"
    echo -e "${YELLOW}Running Arrow download_dependencies.sh...${NC}"
    ./thirdparty/download_dependencies.sh "${ARROW_DEPS_DIR}"

    # Clean up temporary directory
    cd /
    rm -rf "${TEMP_ARROW_DIR}"

    echo -e "${GREEN}✓ Downloaded Arrow dependencies to ${ARROW_DEPS_DIR}${NC}"
    echo "Dependencies downloaded:"
    ls -lh "${ARROW_DEPS_DIR}" | head -20
fi

echo ""
echo -e "${GREEN}=== Download Complete ===${NC}"
echo "Files in ${DOWNLOADS_DIR}:"
ls -lh "${DOWNLOADS_DIR}"
echo ""
echo "Arrow dependencies in ${ARROW_DEPS_DIR}:"
ls -1 "${ARROW_DEPS_DIR}" | wc -l | xargs echo "Total files:"
echo ""
echo "These files will be copied into the container during build."
