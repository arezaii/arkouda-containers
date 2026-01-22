# Arkouda Container Production Guide

## Overview
This directory contains Arkouda containers and deployment scripts.

## Prerequisites
- Podman or Docker for building containers
- Apptainer/Singularity for running containers
- Git access to Bears-R-Us/arkouda repository

## Quick Start

### 1. Build Containers
```bash
# Build client container
cd containers && ../scripts/build-arkouda-client.sh

# Build server container
cd containers && ../scripts/build-chapel-arkouda.sh
```

### 2. Launch Server
```bash
# Set your workspace path
export WORKSPACE_ROOT=/path/to/your/workspace

# Start server
PMI_MAX_KVS_ENTRIES=20 PMI_NO_PREINITIALIZE=y HUGETLB_MORECORE=no srun --job-name=arkouda_server --quiet --nodes=2 --ntasks=2 --cpus-per-task=256 --exclusive --time=8:00:00 --kill-on-bad-exit  ./run-chapel-arkouda-apptainer.sh arkouda_server_real  '-nl' '2'
```

### 3. Connect Client
```bash
# Set server connection details (replace with actual server hostname)
export ARKOUDA_SERVER_HOST=your-server-hostname
export ARKOUDA_SERVER_PORT=5555

# Run client
./scripts/run-arkouda-client.sh python3 -c "import arkouda; arkouda.connect(); print('Connected')"
```

### 4. Run Tests
```bash
# Run specific test
./scripts/run-arkouda-client.sh pytest /opt/arkouda/tests/server_test.py

# Run all tests
./scripts/run-arkouda-client.sh pytest /opt/arkouda/tests/
```

## Configuration

### Environment Variables
- `WORKSPACE_ROOT`: Local workspace directory (default: current directory)
- `SIF_FILE`: Container image file (default: arkouda-client.sif or chapel-arkouda.sif)
- `CONTAINER_TYPE`: Container runtime (podman or apptainer, default: apptainer)
- `ARKOUDA_SERVER_HOST`: Server hostname (default: localhost)
- `ARKOUDA_SERVER_PORT`: Server port (default: 5555)
- `ARKOUDA_NUMLOCALES`: Number of Chapel locales (default: 2)

### System-Specific Modifications
Edit `scripts/run-chapel-arkouda-apptainer.sh` to add your system's bind mounts:
```bash
# Example bind mounts:
BIND_ARGS+=",/opt/cray:/opt/cray"
BIND_ARGS+=",/usr/lib64/slurm:/usr/lib64/slurm"
```

## File Structure
```
arkouda-production/
|-- containers/          # Container definitions
|   |-- Containerfile.arkouda-client
|   `-- Containerfile.chapel-arkouda
|-- scripts/            # Build and run scripts
|   |-- build-arkouda-client.sh
|   |-- build-chapel-arkouda.sh
|   |-- run-arkouda-client.sh
|   `-- run-chapel-arkouda-apptainer.sh
|-- patches/            # Code patches
|   |-- arkouda_index_test_temp_fix.patch
|   `-- conftest_modified.py
`-- docs/              # Documentation
    `-- README.md
```

## Troubleshooting

### Container Build Issues
- Ensure internet access for downloading dependencies
- Verify Podman/Docker has sufficient disk space
- Check that patch files are in the patches/ directory

### Runtime Issues
- Verify SIF files exist and are accessible
- Check workspace directory permissions
- Ensure server is running before connecting client
- Verify shared test directories are created

```internal error: comm-ofi-oob-pmi2.c:216: PMI2_KVS_Put(key, enc) == 14, expected 0```
- Check bind mount configuration, particularly SLURM libraries and executables.

### Connection Issues
- Check server host and port configuration
- Verify network connectivity between client and server
- Ensure firewall allows traffic on server port

## Using E4S-CL to Launch Arkouda Containers
If your system uses the e4s-cl module, you can launch Arkouda containers by binding the required libraries:
- libfabric, libcxi, libnl-3
- libpmi2, libpmi, liblz4, libpals

See the scripts in `scripts/` for automated library detection and e4s-cl profile setup.
