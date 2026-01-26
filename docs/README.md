# Arkouda Container Guide

## Required Software
- Podman/Docker (container building)
- Apptainer/Singularity (container runtime)
- e4s-cl module (for HPC environments)

## Build and Convert Containers
```bash
# Build client container (process automatically converts to .sif)
cd containers && ../scripts/build-arkouda-client.sh

# Build server container (process automatically converts to .sif)
cd containers && ../scripts/build-chapel-arkouda.sh
```

## Setup e4s-cl Profile
```bash

# Setup profile with required libraries
cd scripts
./setup-e4s-cl-profile.sh

# Configure container image and backend
e4s-cl profile edit --image /path/to/chapel-arkouda.sif
e4s-cl profile edit --backend apptainer
```

## Launch Container
```bash
# Run arkouda server (distributed)
e4s-cl launch srun --job-name=arkouda_server --nodes=2 --ntasks=2 --cpus-per-task=256 --exclusive --time=8:00:00 --kill-on-bad-exit -- arkouda_server_real -nl 2
```

## File Structure
```
arkouda-containers/
├── containers/          # Container definitions
├── scripts/            # Build and conversion scripts
│   ├── build-arkouda-client.sh
│   ├── build-chapel-arkouda.sh
│   ├── convert-to-sif.sh
│   ├── setup-e4s-cl-profile.sh
│   └── generate-e4s-cl-profile.sh
└── docs/              # Documentation
```

## Troubleshooting
- **Build fails**: Check internet access and disk space
- **Profile setup fails**: Ensure e4s-cl module is loaded and profile is selected, verify bindings
- **Container won't launch**: Verify SIF file exists and profile is configured
