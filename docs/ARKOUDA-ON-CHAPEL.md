# Building Arkouda on Pre-built Chapel Container

> **Superseded:** this document has been folded into the unified
> [docs/README.md](README.md) guide, which reflects the current
> `Containerfile.hpe-cray-ex-chapel-pic` / `Containerfile.arkouda`
> pair and its documented `docker`/`podman run` and `e4s-cl` launch
> commands. Some details below (image names, dual
> `arkouda_server-ofi`/`arkouda_server-none` binaries,
> `arkouda-select-runtime`) describe an earlier, aspirational design and do
> not match the current Containerfiles — kept for historical context only.

This approach builds Arkouda on top of a pre-built Chapel container (`chapel:hpe-cray-ex-main`) that already contains Chapel runtimes for both HPE Cray EX (multi-node with OFI) and Linux64 (single-node with comm=none) platforms.


## Benefits

- **Faster builds**: Skip Chapel compilation (saves ~30-45 minutes)
- **Smaller build context**: No need to build libfabric, SLURM, or Chapel from source
- **Reusable base**: Use the same Chapel container for multiple Arkouda builds
- **Dual runtime**: Single container supports both multi-node and single-node execution

## Prerequisites

1. **Build Dependencies**: Pre-download the source tarballs used by the Chapel base image:
    ```bash
    ./containers/download_build_dependencies.sh
    ```

2. **Chapel Base Container**: Build the `chapel:hpe-cray-ex-main` container first:
   ```bash
   docker build -f containers/Containerfile.hpe-cray-ex -t chapel:hpe-cray-ex-main .
   ```

## Why This Base Image Matters

- The HPE Cray EX Chapel base now follows the proven CXI-enabled path from the fast March 6 lineage.
- It vendors the public HPE CXI headers, builds `libcxi`, and builds `/opt/libfabric` with `--enable-cxi`.
- The benchmark investigation showed that runtime provider selection alone is not sufficient. The neutral-CXI builds still selected the host `cxi` provider at runtime, but remained in the old slow band because Chapel had been built against the wrong libfabric capabilities.
- The Arkouda-on-Chapel flow therefore expects the base image to provide `/opt/libfabric`, `/opt/cxi-dev`, and `/opt/slurm-pmi`, and keeps that same stack in the final runtime image.

## Building Arkouda

### Quick Build
```bash
# Build with default settings (Arkouda 2025.12.16)
./scripts/build-arkouda-on-chapel.sh
```

### Custom Build Options
```bash
# Build specific Arkouda version
./scripts/build-arkouda-on-chapel.sh --arkouda-version 2025.09.30

# Use custom Chapel base image
./scripts/build-arkouda-on-chapel.sh --base-image chapel:hpe-cray-ex-2.6.0

# Custom output tag
./scripts/build-arkouda-on-chapel.sh --tag my-arkouda:latest

# Use podman instead of docker
./scripts/build-arkouda-on-chapel.sh --docker-cmd podman
```

## Running Arkouda

### Interactive Shell
```bash
# Start interactive shell to explore the container
./scripts/run-arkouda-on-chapel.sh --interactive
```

### Multi-node Runtime (OFI)
```bash
# Default - starts Arkouda with OFI communication for multi-node execution
./scripts/run-arkouda-on-chapel.sh

# Explicit multi-node runtime
./scripts/run-arkouda-on-chapel.sh --runtime ofi

# With custom arguments
./scripts/run-arkouda-on-chapel.sh --runtime ofi -- --verbose --port=5555
```

### Single-node Runtime (comm=none)
```bash
# Single-node execution (no SLURM/PMI2 required)
./scripts/run-arkouda-on-chapel.sh --runtime none

# With custom arguments
./scripts/run-arkouda-on-chapel.sh --runtime none -- --port=5555
```

### Background Execution
```bash
# Run in background (detached mode)
./scripts/run-arkouda-on-chapel.sh --runtime none --background -- --port=5555

# With volume mounts
./scripts/run-arkouda-on-chapel.sh \
    --container-args "-v /data:/data -p 5555:5555" \
    --runtime none --background -- --port=5555
```

## Runtime Selection

The container includes both Arkouda runtimes:

- **`arkouda_server-ofi`**: Built with `CHPL_COMM=ofi` for multi-node execution
- **`arkouda_server-none`**: Built with `CHPL_COMM=none` for single-node execution

### Manual Runtime Selection
Inside the container, you can manually select the runtime:

```bash
# Multi-node (requires SLURM environment)
arkouda-select-runtime ofi --verbose

# Single-node (standalone)
arkouda-select-runtime none --verbose
```

## Environment Variables

The container sets different Chapel environment variables depending on the selected runtime:

### Multi-node (OFI) Configuration
```bash
CHPL_HOST_PLATFORM=hpe-cray-ex
CHPL_TARGET_PLATFORM=hpe-cray-ex
CHPL_COMM=ofi
CHPL_LIBFABRIC=system
CHPL_COMM_OFI_OOB=pmi2
CHPL_LAUNCHER=slurm-srun
CHPL_LAUNCHER_MEM=unset
CHPL_TARGET_COMPILER=llvm
CHPL_LLVM=system
LIBFABRIC_DIR=/opt/libfabric
```

### Single-node (none) Configuration
```bash
CHPL_HOST_PLATFORM=linux64
CHPL_TARGET_PLATFORM=linux64
CHPL_COMM=none
CHPL_LIBFABRIC=none
CHPL_LAUNCHER=none
```

## Files Structure

```
containers/
├── Containerfile.arkouda-on-chapel    # New Arkouda-on-Chapel containerfile
├── Containerfile.hpe-cray-ex          # Chapel base container (prerequisite)
└── Containerfile.chapel-arkouda       # Original monolithic containerfile

scripts/
├── build-arkouda-on-chapel.sh         # Build script for new approach
├── run-arkouda-on-chapel.sh           # Runtime script for new approach
├── build-chapel-arkouda.sh            # Original build script
└── run-chapel-arkouda-*.sh            # Original runtime scripts
```

## Comparison with Original Approach

| Aspect | Original (`Containerfile.chapel-arkouda`) | New (`Containerfile.arkouda-on-chapel`) |
|--------|-------------------------------------------|------------------------------------------|
| Build time | ~45-60 minutes | ~15-20 minutes |
| Base image | Ubuntu 24.04 | Pre-built Chapel container |
| Chapel build | From source | Pre-built |
| Libfabric | Built from source | From Chapel container |
| SLURM | Built from source | From Chapel container |
| Runtimes | Both in single build | Both in single build |
| Container size | Larger (includes build tools) | Smaller (runtime only) |

## Troubleshooting

### Chapel Base Container Not Found
```
Error: Chapel base image 'chapel:hpe-cray-ex-main' not found!
```
**Solution**: Build the Chapel container first:
```bash
./containers/download_build_dependencies.sh
docker build -f containers/Containerfile.hpe-cray-ex -t chapel:hpe-cray-ex-main .
```

### Runtime Selection Issues
If the automatic runtime selection doesn't work, manually set environment variables:
```bash
# For multi-node
export CHPL_COMM=ofi CHPL_TARGET_PLATFORM=hpe-cray-ex
./arkouda_server-ofi

# For single-node
export CHPL_COMM=none CHPL_TARGET_PLATFORM=linux64
./arkouda_server-none
```

### Library Path Issues
If you encounter library loading errors, check:
```bash
echo $LD_LIBRARY_PATH
ldd arkouda_server-ofi
ldd arkouda_server-none
```