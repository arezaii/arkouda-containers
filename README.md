# Arkouda on Chapel — Container Build Framework

Container build framework for running [Arkouda](https://github.com/Bears-R-Us/arkouda)
on [Chapel](https://chapel-lang.org/) with HPE Cray EX (Slingshot/CXI) support,
built as two composable images:

1. **`containers/Containerfile.hpe-cray-ex-chapel-pic`** — a Chapel base image
   with dual runtimes (`hpe-cray-ex`/OFI+CXI and `linux64`/`CHPL_COMM=none`).
2. **`containers/Containerfile.arkouda-on-chapel`** — builds Arkouda on top of
   that Chapel base image.

See **[docs/README.md](docs/README.md)** for the full build and usage guide.

## Quick start

```bash
# 1. Build the Chapel base image
./scripts/build-chapel-dist-cxi-2.3.1-pic.sh

# 2. Build Arkouda on top of it
./scripts/build-arkouda-on-chapel.sh

# 3. Run it
./scripts/run-arkouda-on-chapel.sh
```

## Repository layout

```
containers/
├── Containerfile.hpe-cray-ex-chapel-pic  # Chapel base image (target 1)
├── Containerfile.arkouda-on-chapel       # Arkouda on Chapel (target 2)
└── legacy/                               # superseded Containerfiles (reference only)
scripts/
├── build-chapel-dist-cxi-2.3.1-pic.sh    # builds the Chapel base image
├── build-arkouda-on-chapel.sh            # builds Arkouda on the Chapel base image
├── run-arkouda-on-chapel.sh              # runs the Arkouda-on-Chapel image
├── convert-to-sif.sh                     # OCI image -> Apptainer .sif
├── setup-e4s-cl-profile.sh               # HPC library-forwarding helper (e4s-cl)
├── generate-e4s-cl-profile.sh            # detects HPC libs for e4s-cl profiles
├── chapel-start / chapel-test-compile / chapel-validate-hpe-ex
├── slurm-start.sh / startup-slurm-for-container.sh
└── legacy/                               # scripts for the legacy containers
configs/                                  # slurm.conf / cgroup.conf used by arkouda-on-chapel
patches/                                  # patches applied during the Arkouda build
docs/                                     # full build/usage guide
```

Directories not part of this framework (benchmark `results/`, the
`slurm-docker-cluster/` reference project, and `legacy/` build assets) are
kept in place for reference but are out of scope for day-to-day use — see
[docs/README.md](docs/README.md#legacy--reference-material) for details.
