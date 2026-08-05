#!/bin/bash
# Arkouda server container launcher

set -e

# Configuration - modify paths as needed
SIF_FILE="${SIF_FILE:-chapel-arkouda.sif}"
WORKSPACE_ROOT="${WORKSPACE_ROOT:-$(pwd)}"

# Check for library detection mode first
if [ "$1" = "--locate-libraries" ] || [ "$1" = "locate_host_libraries" ]; then
    # Function to locate host libraries for HPC systems
    locate_host_libraries() {
        echo "=== Host Library Detection ==="
        echo "Searching for common HPC libraries and tools..."
        echo ""

        # Define libraries to search for
        declare -A LIBRARIES=(
            ["libfabric"]="/opt/cray/libfabric/*/lib*/libfabric.so*"
            ["libcxi"]="/usr/lib*/libcxi.so*"
            ["libnl"]="/usr/lib*/libnl-3.so*"
            ["libpmi2"]="/opt/cray/pe/pmi/*/lib*/libpmi2.so*"
            ["libpmi"]="/opt/cray/pe/pmi/*/lib*/libpmi.so*"
            ["libpals"]="/opt/cray/pals/*/lib*/libpals.so*"
            ["liblz4"]="/usr/lib*/liblz4.so*"
            ["libslurm"]="/usr/lib*/libslurm.so*"
            ["libslurmfull"]="/usr/lib*/slurm/libslurmfull.so*"
            ["libslurm_pmi"]="/usr/lib*/slurm/libslurm_pmi.so*"
        )

        # Define directories to search for
        declare -A DIRECTORIES=(
            ["slurm_config"]="/etc/slurm"
            ["munge_run"]="/run/munge"
            ["slurm_spool"]="/var/spool/slurm"
            ["cray_pe"]="/opt/cray"
        )

        # Define executables to search for
        declare -A EXECUTABLES=(
            ["srun"]="/usr/bin/srun"
            ["sbatch"]="/usr/bin/sbatch"
            ["salloc"]="/usr/bin/salloc"
            ["squeue"]="/usr/bin/squeue"
            ["sinfo"]="/usr/bin/sinfo"
            ["scontrol"]="/usr/bin/scontrol"
        )

        echo "Libraries found:"
        for lib_name in "${!LIBRARIES[@]}"; do
            pattern="${LIBRARIES[$lib_name]}"
            found_libs=$(ls $pattern 2>/dev/null | head -1)
            if [ -n "$found_libs" ]; then
                echo "  $lib_name: $found_libs"
                echo "    # BIND_ARGS+=\",$found_libs:/opt/host-libs/$(basename $found_libs)\""
            else
                echo "  $lib_name: NOT FOUND"
            fi
        done

        echo ""
        echo "Directories found:"
        for dir_name in "${!DIRECTORIES[@]}"; do
            dir_path="${DIRECTORIES[$dir_name]}"
            if [ -d "$dir_path" ]; then
                echo "  $dir_name: $dir_path"
                echo "    # BIND_ARGS+=\",$dir_path:$dir_path\""
            else
                echo "  $dir_name: NOT FOUND"
            fi
        done

        # Special check for SLURM library directories with wildcards
        echo "  slurm_libs: $(ls -d /usr/lib*/slurm 2>/dev/null | head -1 || echo "NOT FOUND")"
        if ls -d /usr/lib*/slurm >/dev/null 2>&1; then
            slurm_lib_dir=$(ls -d /usr/lib*/slurm 2>/dev/null | head -1)
            echo "    # BIND_ARGS+=\",$slurm_lib_dir:$slurm_lib_dir\""
        fi

        echo ""
        echo "Executables found:"
        for exe_name in "${!EXECUTABLES[@]}"; do
            exe_path="${EXECUTABLES[$exe_name]}"
            if [ -x "$exe_path" ]; then
                echo "  $exe_name: $exe_path"
                echo "    # BIND_ARGS+=\",$exe_path:$exe_path\""
            else
                echo "  $exe_name: NOT FOUND"
            fi
        done

        echo ""
        echo "=== Usage Instructions ==="
        echo "Copy the bind mount lines for found items into this script's BIND_ARGS section."
        echo "Uncomment and modify paths as needed for your system."
        echo "=========================="
        exit 0
    }
    locate_host_libraries
fi

# Verify container exists
if [ ! -f "${SIF_FILE}" ]; then
    echo "Error: SIF file not found: ${SIF_FILE}"
    exit 1
fi

# Create single shared directory for all Arkouda test operations
ARKOUDA_SHARED_DIR="${WORKSPACE_ROOT}/arkouda-shared"
mkdir -p "${ARKOUDA_SHARED_DIR}/tmp"

# Basic bind mounts - extend for your system
BIND_ARGS="${WORKSPACE_ROOT}:${WORKSPACE_ROOT}"
BIND_ARGS+=",${ARKOUDA_SHARED_DIR}:/opt/arkouda-shared"

# Bind user workspace for test file I/O
BIND_ARGS+=",/lus/bnchlu1/rezaii:/lus/bnchlu1/rezaii"

# Add system-specific bind mounts here
# Auto-detect and bind critical libraries
echo "Auto-detecting and binding system libraries..."

# Bind Cray libfabric (critical for OFI) - use version that works
LIBFABRIC_PATH=$(ls /opt/cray/libfabric/*/lib*/libfabric.so.1 2>/dev/null | head -1)
if [ -n "$LIBFABRIC_PATH" ]; then
    BIND_ARGS+=",${LIBFABRIC_PATH}:/opt/host-libs/libfabric.so.1"
    echo "  Found libfabric: $LIBFABRIC_PATH"
fi

# Bind CXI library - find correct version
CXI_PATH=$(ls /usr/lib*/libcxi.so.1 2>/dev/null | head -1)
if [ -z "$CXI_PATH" ]; then
    CXI_PATH=$(ls /usr/lib*/libcxi.so 2>/dev/null | head -1)
fi
if [ -n "$CXI_PATH" ]; then
    BIND_ARGS+=",${CXI_PATH}:/opt/host-libs/libcxi.so.1"
    echo "  Found CXI: $CXI_PATH"
fi

# Bind netlink library - match working script version
NETLINK_PATH=$(ls /usr/lib*/libnl-3.so.200 2>/dev/null | head -1)
if [ -z "$NETLINK_PATH" ]; then
    NETLINK_PATH=$(ls /usr/lib*/libnl-3.so 2>/dev/null | head -1)
fi
if [ -n "$NETLINK_PATH" ]; then
    BIND_ARGS+=",${NETLINK_PATH}:/opt/host-libs/libnl-3.so.200"
    echo "  Found netlink: $NETLINK_PATH"
fi

# Bind PMI libraries - match working explicit script versions
# First try to find the exact version used in working script (6.1.16)
PMI_DIR="/opt/cray/pe/pmi/6.1.16/lib"
if [ -d "$PMI_DIR" ] && [ -f "$PMI_DIR/libpmi2.so.0.6.0" ]; then
    BIND_ARGS+=",${PMI_DIR}/libpmi2.so.0.6.0:/opt/host-libs/libpmi2.so.0.6.0"
    BIND_ARGS+=",${PMI_DIR}/libpmi.so.0.6.0:/opt/host-libs/libpmi.so.0.6.0"
    BIND_ARGS+=",${PMI_DIR}/libpmi2.so.0:/opt/host-libs/libpmi2.so.0"
    BIND_ARGS+=",${PMI_DIR}/libpmi.so.0:/opt/host-libs/libpmi.so.0"
    echo "  Found PMI 6.1.16: $PMI_DIR"
else
    # Fallback to auto-detection for other versions
    PMI2_PATH=$(ls /opt/cray/pe/pmi/*/lib/libpmi2.so.0.6.0 2>/dev/null | head -1)
    if [ -n "$PMI2_PATH" ]; then
        PMI_DIR=$(dirname "$PMI2_PATH")
        BIND_ARGS+=",${PMI_DIR}/libpmi2.so.0.6.0:/opt/host-libs/libpmi2.so.0.6.0"
        BIND_ARGS+=",${PMI_DIR}/libpmi.so.0.6.0:/opt/host-libs/libpmi.so.0.6.0"
        BIND_ARGS+=",${PMI_DIR}/libpmi2.so.0:/opt/host-libs/libpmi2.so.0"
        BIND_ARGS+=",${PMI_DIR}/libpmi.so.0:/opt/host-libs/libpmi.so.0"
        echo "  Found PMI: $PMI_DIR"
    else
        # Last resort - find any PMI and bind with generic names
        PMI2_PATH=$(ls /opt/cray/pe/pmi/*/lib/libpmi2.so 2>/dev/null | head -1)
        if [ -n "$PMI2_PATH" ]; then
            PMI_DIR=$(dirname "$PMI2_PATH")
            BIND_ARGS+=",${PMI_DIR}/libpmi2.so:/opt/host-libs/libpmi2.so.0.6.0"
            BIND_ARGS+=",${PMI_DIR}/libpmi.so:/opt/host-libs/libpmi.so.0.6.0"
            BIND_ARGS+=",${PMI_DIR}/libpmi2.so:/opt/host-libs/libpmi2.so.0"
            BIND_ARGS+=",${PMI_DIR}/libpmi.so:/opt/host-libs/libpmi.so.0"
            echo "  Found PMI (generic): $PMI_DIR"
        fi
    fi
fi

# Bind PALS libraries (match working script)
PALS_PATH=$(ls /opt/cray/pals/*/lib/libpals.so.0 2>/dev/null | head -1)
if [ -n "$PALS_PATH" ]; then
    BIND_ARGS+=",${PALS_PATH}:/opt/host-libs/libpals.so.0"
    echo "  Found PALS: $PALS_PATH"
fi
# Also bind PE libpals fallback
PALS_PE_PATH=$(ls /opt/cray/pe/lib64/libpals.so.0 2>/dev/null | head -1)
if [ -n "$PALS_PE_PATH" ]; then
    BIND_ARGS+=",${PALS_PE_PATH}:/opt/host-libs/libpals.so.0.fallback"
    echo "  Found PALS PE: $PALS_PE_PATH"
fi

# Bind LZ4 compression library
LZ4_PATH=$(ls /usr/lib*/liblz4.so.1 2>/dev/null | head -1)
if [ -n "$LZ4_PATH" ]; then
    BIND_ARGS+=",${LZ4_PATH}:/opt/host-libs/liblz4.so.1"
    echo "  Found LZ4: $LZ4_PATH"
fi

# # Bind essential directories
# [ -d "/etc/slurm" ] && BIND_ARGS+=",/etc/slurm:/etc/slurm" && echo "  Found SLURM config: /etc/slurm"
# [ -d "/run/munge" ] && BIND_ARGS+=",/run/munge:/run/munge" && echo "  Found munge: /run/munge"
# [ -d "/usr/lib64/slurm" ] && BIND_ARGS+=",/usr/lib64/slurm:/usr/lib64/slurm" && echo "  Found SLURM libs: /usr/lib64/slurm"
# [ -d "/var/spool/slurm" ] && BIND_ARGS+=",/var/spool/slurm:/var/spool/slurm" && echo "  Found SLURM spool: /var/spool/slurm"

# # Bind SLURM executables
# for exe in srun sbatch salloc squeue sinfo scontrol; do
#     if [ -x "/usr/bin/$exe" ]; then
#         BIND_ARGS+=",/usr/bin/$exe:/usr/bin/$exe"
#     fi
# done

# =============================================================================
# Environment variables for Chapel/Arkouda
# =============================================================================
export APPTAINERENV_CHPL_HOME=/opt/chapel
export APPTAINERENV_ARKOUDA_HOME=/opt/arkouda
export APPTAINERENV_ARKOUDA_DEFAULT_TEMP_DIRECTORY=/opt/arkouda-shared
export APPTAINERENV_ARKOUDA_WORKING_DIR=/opt/arkouda-shared
export APPTAINERENV_CHPL_COMM=ofi
export APPTAINERENV_CHPL_LIBFABRIC=system
export APPTAINERENV_CHPL_LAUNCHER=slurm-srun
export APPTAINERENV_CHPL_LAUNCHER_MEM=none
export APPTAINERENV_CHPL_LLVM=system
export APPTAINERENV_LIBFABRIC_DIR=/opt/libfabric

# Use PMI for out-of-band communication (required for multi-locale)
export APPTAINERENV_CHPL_COMM_OFI_OOB=pmi2
export APPTAINERENV_FI_CXI_DISABLE_HOST_REGISTER=1
export APPTAINERENV_FI_CXI_DEFAULT_VNI=$(id -u)

# Additional libfabric/PMI debugging and configuration
export APPTAINERENV_FI_LOG_LEVEL=warn
export APPTAINERENV_FI_PROVIDER=cxi
export APPTAINERENV_PMI_NO_FORK=1

# Prepend host libs to library path (include /usr/local/lib for GNU libiconv)
export APPTAINERENV_LD_LIBRARY_PATH="/opt/host-libs:/opt/libfabric/lib:/opt/mpich/lib:/usr/local/lib"
export APPTAINERENV_PATH="/opt/arkouda-venv/bin:/opt/chapel/bin/linux64-x86_64:/opt/chapel/util:/opt/mpich/bin:/opt/arkouda:/usr/local/bin:/usr/bin:/bin"

# Also set the base LD_LIBRARY_PATH so Apptainer inherits it (helps libfabric discovery)
LD_LIBRARY_PATH="/opt/host-libs:/opt/libfabric/lib:/opt/mpich/lib:/usr/local/lib:${LD_LIBRARY_PATH:-}"
export LD_LIBRARY_PATH

# Launch container
if [ $# -gt 0 ]; then
    exec apptainer exec \
        --bind "${BIND_ARGS}" \
        --pwd "${WORKSPACE_ROOT}" \
        "${SIF_FILE}" \
        "$@"
else
    exec apptainer shell \
        --bind "${BIND_ARGS}" \
        --pwd "${WORKSPACE_ROOT}" \
        "${SIF_FILE}"
fi
