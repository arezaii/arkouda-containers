#!/bin/bash
# Arkouda client container launcher

set -e

# Configuration - modify as needed
CONTAINER_TYPE="${CONTAINER_TYPE:-apptainer}"
SIF_FILE="${SIF_FILE:-arkouda-client.sif}"
# PODMAN_IMAGE="${PODMAN_IMAGE:-localhost/arkouda-client:latest}"

# Arkouda server connection
ARKOUDA_SERVER_HOST="${ARKOUDA_SERVER_HOST:-localhost}"
ARKOUDA_SERVER_PORT="${ARKOUDA_SERVER_PORT:-5555}"
ARKOUDA_NUMLOCALES="${ARKOUDA_NUMLOCALES:-2}"

# Workspace setup
WORKSPACE_ROOT="${WORKSPACE_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"

# Single shared directory for all Arkouda test operations
ARKOUDA_SHARED_DIR="${WORKSPACE_ROOT}/arkouda-shared"
mkdir -p "${ARKOUDA_SHARED_DIR}"

# Bind mounts for workspace access
BIND_WORKSPACE="$(dirname "${WORKSPACE_ROOT}"):$(dirname "${WORKSPACE_ROOT}")"
BIND_ARKOUDA_SHARED="${ARKOUDA_SHARED_DIR}:/opt/arkouda-shared:rw"

# Create shared test directories
mkdir -p "${ARKOUDA_SHARED_DIR}/tmp"

# Environment variables for container runtime
export ARKOUDA_RUNNING_MODE=CLIENT
export ARKOUDA_NUMLOCALES="${ARKOUDA_NUMLOCALES}"
export ARKOUDA_SERVER_HOST="${ARKOUDA_SERVER_HOST}"
export ARKOUDA_SERVER_PORT="${ARKOUDA_SERVER_PORT}"
export ARKOUDA_DEFAULT_TEMP_DIRECTORY="/opt/arkouda-shared"

# Launch container
if [ "${CONTAINER_TYPE}" = "podman" ]; then
    if [ $# -gt 0 ]; then
        exec podman run --rm -it \
            --volume "${BIND_WORKSPACE}" \
            --volume "${BIND_ARKOUDA_SHARED}" \
            --env "ARKOUDA_RUNNING_MODE=CLIENT" \
            --env "ARKOUDA_NUMLOCALES=${ARKOUDA_NUMLOCALES}" \
            --env "ARKOUDA_SERVER_HOST=${ARKOUDA_SERVER_HOST}" \
            --env "ARKOUDA_SERVER_PORT=${ARKOUDA_SERVER_PORT}" \
            --env "ARKOUDA_DEFAULT_TEMP_DIRECTORY=/opt/arkouda-shared" \
            --env "TMPDIR=/opt/arkouda-shared/tmp" \
            --env "TEMP=/opt/arkouda-shared/tmp" \
            --env "TMP=/opt/arkouda-shared/tmp" \
            "${PODMAN_IMAGE}" "$@"
    else
        exec podman run --rm -it \
            --volume "${BIND_WORKSPACE}" \
            --volume "${BIND_ARKOUDA_SHARED}" \
            --env "ARKOUDA_RUNNING_MODE=CLIENT" \
            --env "ARKOUDA_NUMLOCALES=${ARKOUDA_NUMLOCALES}" \
            --env "ARKOUDA_SERVER_HOST=${ARKOUDA_SERVER_HOST}" \
            --env "ARKOUDA_SERVER_PORT=${ARKOUDA_SERVER_PORT}" \
            --env "ARKOUDA_DEFAULT_TEMP_DIRECTORY=/opt/arkouda-shared" \
            --env "TMPDIR=/opt/arkouda-shared/tmp" \
            --env "TEMP=/opt/arkouda-shared/tmp" \
            --env "TMP=/opt/arkouda-shared/tmp" \
            "${PODMAN_IMAGE}" /bin/bash
    fi
elif [ "${CONTAINER_TYPE}" = "apptainer" ]; then
    if [ ! -f "${SIF_FILE}" ]; then
        echo "Error: SIF file not found: ${SIF_FILE}"
        exit 1
    fi


    export APPTAINERENV_ARKOUDA_RUNNING_MODE="${ARKOUDA_RUNNING_MODE}"
    export APPTAINERENV_ARKOUDA_NUMLOCALES="${ARKOUDA_NUMLOCALES}"
    export APPTAINERENV_ARKOUDA_SERVER_HOST="${ARKOUDA_SERVER_HOST}"
    export APPTAINERENV_ARKOUDA_SERVER_PORT="${ARKOUDA_SERVER_PORT}"
    export APPTAINERENV_ARKOUDA_DEFAULT_TEMP_DIRECTORY="${ARKOUDA_DEFAULT_TEMP_DIRECTORY}"
    export APPTAINERENV_TMPDIR="/opt/arkouda-shared/tmp"
    export APPTAINERENV_TEMP="/opt/arkouda-shared/tmp"
    export APPTAINERENV_TMP="/opt/arkouda-shared/tmp"

    if [ $# -gt 0 ]; then
        exec apptainer exec \
            --bind "${BIND_WORKSPACE}" \
            --bind "${BIND_ARKOUDA_SHARED}" \
            --pwd "${WORKSPACE_ROOT}" \
            "${SIF_FILE}" "$@"
    else
        exec apptainer shell \
            --bind "${BIND_WORKSPACE}" \
            --bind "${BIND_ARKOUDA_SHARED}" \
            --pwd "${WORKSPACE_ROOT}" \
            "${SIF_FILE}"
    fi
else
    echo "Error: CONTAINER_TYPE must be 'podman' or 'apptainer'"
    exit 1
fi
