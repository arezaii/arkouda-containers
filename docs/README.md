# Build & Usage Guide: Chapel + Arkouda Containers

This guide covers the two supported container images and the scripts that
build, run, and package them.

## Table of contents

- [Architecture](#architecture)
- [Prerequisites](#prerequisites)
- [Quick start](#quick-start)
- [1. Building the Chapel base image](#1-building-the-chapel-base-image)
- [2. Building Arkouda](#2-building-arkouda)
- [3. Running the Arkouda container](#3-running-the-arkouda-container)
- [Converting to an Apptainer/Singularity SIF](#converting-to-an-apptainersingularity-sif)
- [Corporate CA / TLS-inspecting proxy support](#corporate-ca--tls-inspecting-proxy-support)
- [HPC library forwarding with e4s-cl](#hpc-library-forwarding-with-e4s-cl)
- [Chapel runtime environment reference](#chapel-runtime-environment-reference)
- [Troubleshooting](#troubleshooting)
- [Legacy / reference material](#legacy--reference-material)

## Architecture

```mermaid
flowchart TD
    A[debian:bookworm-slim] --> B[chapel-runtime-base<br/>apt deps + LLVM 22]
    B --> C[cxi-dev<br/>HPE Slingshot CXI headers + libcxi]
    C --> D[libfabric-build<br/>libfabric 2.3.1 + CXI provider]
    D --> E[chapel-hpe-cray-ex-build<br/>Chapel 2.9.0, dual runtimes]
    E --> F[chapel-multi-rt-base<br/>= Containerfile.hpe-cray-ex-chapel-pic]
    F --> G[arkouda-builder<br/>Containerfile.arkouda]
    G --> H[runtime<br/>final Arkouda image]
```

- **`Containerfile.hpe-cray-ex-chapel-pic`** produces a Chapel image with
  *both* the `hpe-cray-ex` platform (OFI comm layer over libfabric, with the
  CXI provider for HPE Slingshot) and the `linux64` platform
  (`CHPL_COMM=none`) built and available under `$CHPL_HOME`, selectable via
  the `chapel-start` wrapper. The `linux64` build step also runs
  `make chapel-py-venv` and `make mason`, so the image ships the Chapel
  Python bindings (importable via `python3 -c "import chapel"`, on
  `$PYTHONPATH`) and the `mason` package manager on `$PATH`.
- **`Containerfile.arkouda`** takes that image as its
  `CHAPEL_BASE_IMAGE` build argument and builds Arkouda against whichever
  runtime is active in the base image's environment (`hpe-cray-ex`/OFI by
  default), producing a single `arkouda_server` binary. The Arkouda Python
  client package is installed editable (`pip install -e .[dev]`) into the
  same `/opt/arkouda-venv` virtual environment that's copied into the final
  runtime image, so `arkouda` is importable there too — it is not published
  as a separate wheel/artifact for use outside the container.

## Prerequisites

- Docker or Podman for building images
- (optional) [Apptainer/Singularity](https://apptainer.org/) to convert the
  built image to a `.sif` for HPC systems
- (optional) [e4s-cl](https://e4s-cl.readthedocs.io/) for forwarding host HPC
  libraries (libfabric, PMI2, SLURM) into the container on Cray systems
- (optional) a corporate/internal root CA file if you build from behind a
  TLS-inspecting proxy

## Quick start

```bash
# 1. Build the Chapel base image (containers/Containerfile.hpe-cray-ex-chapel-pic)
./scripts/build-chapel-dist-cxi-2.3.1-pic.sh

# 2. Build Arkouda on top of it (containers/Containerfile.arkouda)
./scripts/build-arkouda.sh

# 3. Run it on a single workstation (starts a standalone single-node SLURM
#    in-container, then arkouda_server -nl 1) - see "Running the
#    Arkouda container" below for the full command
docker run --rm -it -e FI_PROVIDER=tcp \
  arkouda-2026.07.15-cxi:latest \
  /bin/bash -lc 'slurm-start >/tmp/slurm-start.log 2>&1; arkouda_server -nl 1'
```

All scripts can be run from any directory — they resolve the repository root
relative to their own location, and both Containerfiles use the repository
root as their build context.

## 1. Building the Chapel base image

```bash
./scripts/build-chapel-dist-cxi-2.3.1-pic.sh
```

Configuration via environment variables (all optional):

| Variable | Default | Description |
|---|---|---|
| `CHAPEL_VERSION` | `2.9.0` | Chapel release tag to build |
| `LIBFABRIC_VERSION` | `2.3.1` | libfabric release to build with CXI support |
| `CXI_VERSION` | `release/shs-13.1.0` | HPE `shs-cassini-headers` tag |
| `CXI_DRIVER_COMMIT` | `3233be5` | `shs-cxi-driver` commit |
| `LIBCXI_COMMIT` | `ebd57a9` | `shs-libcxi` commit |
| `CORP_CA_FILE` | unset | Path to a PEM root CA, passed as a build-time secret (see below) |

The build produces `localhost/chapel-${CHAPEL_VERSION}-libfabric-${LIBFABRIC_VERSION}-cxi-pic:latest`
and writes a timestamped log to `build-logs/`.

## 2. Building Arkouda

```bash
./scripts/build-arkouda.sh [OPTIONS]
```

| Option | Default | Description |
|---|---|---|
| `-b, --base-image` | `localhost/chapel-2.9.0-libfabric-2.3.1-cxi-pic:latest` | Chapel base image from step 1 |
| `-v, --arkouda-version` | `2026.07.15` | Arkouda git tag/release to build |
| `--libiconv-version` | `1.17` | GNU libiconv version |
| `--arrow-version` | `19.0.1-1` | Apache Arrow/Parquet package version |
| `-t, --tag` | `arkouda-<version>-cxi:latest` | Output image tag |
| `-a, --build-arg` | — | Extra `--build-arg`, repeatable |
| `-d, --docker-cmd` | `docker` | Use `podman` instead if preferred |
| `-V, --verbose` | `false` | Stream full build output, useful for docker builds |

The script verifies the Chapel base image exists and exposes the Python
`chapel` module before building, and writes a timestamped log to
`build-logs/`. Like the Chapel base image build, it also honors the
`CORP_CA_FILE` environment variable (see
[Corporate CA / TLS-inspecting proxy support](#corporate-ca--tls-inspecting-proxy-support)).

Patches under `patches/` are applied conditionally based on
`ARKOUDA_VERSION` (currently only `versioneer_update.patch`, applied for
`2025.09.30`).

## 3. Running the Arkouda container

There is no wrapper script for this — the two ways you'll actually run the
image are different enough (plain `docker`/`podman` on a workstation vs.
`apptainer`+`e4s-cl` on real HPE Cray EX hardware) that a single script
can't paper over the difference without lying about what it's doing. Use
the `docker`/`podman` commands below directly, substituting `podman` for
`docker` if that's your container CLI.

> **Why `-e FI_PROVIDER=tcp` is required:** the image bakes in
> `FI_PROVIDER=cxi` because that's what `arkouda_server` needs on real HPE
> Slingshot hardware. A plain Linux workstation has no CXI NIC, so without
> this override `arkouda_server` fails to initialize the OFI comm layer at
> startup. `tcp` works anywhere (including over loopback for a single-node
> run) at the cost of Slingshot's performance. On a real Cray node this
> override should be omitted so the baked-in `cxi` provider is used.

### Interactive shell

```bash
docker run --rm -it arkouda-2026.07.15-cxi:latest /bin/bash
```

### Single-node run (1 locale)

`CHPL_LAUNCHER=slurm-srun` means `arkouda_server` needs a SLURM controller
to talk to even for a single locale, so the image ships a `slurm-start`
helper that stands up a throwaway single-node SLURM controller/daemon
inside the container before launching `arkouda_server`:

```bash
docker run --rm -it -e FI_PROVIDER=tcp \
  arkouda-2026.07.15-cxi:latest \
  /bin/bash -lc 'slurm-start >/tmp/slurm-start.log 2>&1; arkouda_server -nl 1'
```

### Multiple locales on one workstation

Multiple locales can still be scheduled on a single machine (all `srun`
tasks land on the same node, communicating over loopback `tcp`):

```bash
docker run --rm -it -e FI_PROVIDER=tcp \
  arkouda-2026.07.15-cxi:latest \
  /bin/bash -lc 'slurm-start >/tmp/slurm-start.log 2>&1; arkouda_server -nl 2 --logLevel=DEBUG'
```

### Background, with a bind mount and published port

```bash
docker run --rm -d -e FI_PROVIDER=tcp \
  -v "$(pwd)/data:/data" -p 5555:5555 \
  arkouda-2026.07.15-cxi:latest \
  /bin/bash -lc 'slurm-start >/tmp/slurm-start.log 2>&1; arkouda_server -nl 1 --port=5555'
```

### Distributed multi-node runs on real HPE Cray EX hardware

This is a fundamentally different launch path, not a flag on the commands
above: it forwards the *host's* SLURM, libfabric, and CXI libraries into an
Apptainer container instead of starting anything inside the container, and
it runs `arkouda_server` directly via `e4s-cl launch`/`srun` rather than
`docker run`/`podman run`. There is no `docker`/`podman` invocation in this
path at all. See
[HPC library forwarding with e4s-cl](#hpc-library-forwarding-with-e4s-cl)
for the full walkthrough.

## Converting to an Apptainer/Singularity SIF

```bash
./scripts/convert-to-sif.sh localhost/arkouda-2026.07.15-cxi:latest --output-dir .
```

Exports the image to an OCI archive and converts it with `apptainer build`.
See `./scripts/convert-to-sif.sh --help` for all options.

## Corporate CA / TLS-inspecting proxy support

If your network intercepts TLS with an internal root CA, `git clone`/`curl`/
`wget`/`pip` calls in either build can fail with a certificate verification
error. Both `build-chapel-dist-cxi-2.3.1-pic.sh` and
`build-arkouda.sh` accept `CORP_CA_FILE` pointing at a PEM file and
pass it to the corresponding Containerfile as a BuildKit/Buildah secret:

```bash
export CORP_CA_FILE=~/.config/corp-ca/my-root-ca.pem
./scripts/build-chapel-dist-cxi-2.3.1-pic.sh
./scripts/build-arkouda.sh
```

Every network-touching `RUN` step in both `Containerfile.hpe-cray-ex-chapel-pic`
and `Containerfile.arkouda` (`git clone`, `curl`, `wget`, `pip
install`) mounts the secret and builds a temporary combined CA bundle for
just that step:

- `git`/`curl` are pointed at it via `GIT_SSL_CAINFO`/`CURL_CA_BUNDLE`.
- `wget` (which doesn't honor those variables) gets an explicit
  `--ca-certificate=` flag.
- `pip` (which validates against its own bundled `certifi` store, not the
  system trust store) gets `PIP_CERT`.

The CA is never `COPY`'d into the image, never written to a committed layer,
and each `RUN` removes its own temporary combined bundle before the layer is
committed. Builds without `CORP_CA_FILE` set work unmodified.

## HPC library forwarding with e4s-cl

On real HPE Cray EX systems you'll typically want the container to use the
host's libfabric/CXI/PMI2/SLURM stack rather than the versions baked into 
the image. This is a separate launch path from the `docker run`/`podman run`
commands above: there's no in-container `slurm-start`, no
`FI_PROVIDER=tcp` override (the forwarded host libfabric provides the real
`cxi` provider), and no docker/podman involved at all — `e4s-cl` invokes
`srun` on the host, which launches `apptainer` directly against the `.sif`.

```bash
./scripts/setup-e4s-cl-profile.sh
e4s-cl profile edit --image /path/to/arkouda.sif
e4s-cl profile edit --backend apptainer
e4s-cl launch srun --job-name=arkouda_server --nodes=2 --ntasks=2 \
  --cpus-per-task=256 --exclusive --time=8:00:00 --kill-on-bad-exit \
  -- arkouda_server -nl 2
```

`generate-e4s-cl-profile.sh` detects Cray libfabric, CXI, PMI2, and SLURM
paths on the host and prints the `e4s-cl profile edit` commands needed;
`setup-e4s-cl-profile.sh` runs it interactively against a chosen profile.

## Chapel runtime environment reference

The `hpe-cray-ex` runtime (default, used to build Arkouda):

```
CHPL_HOST_PLATFORM=linux64
CHPL_TARGET_PLATFORM=hpe-cray-ex
CHPL_COMM=ofi
CHPL_LIBFABRIC=system
CHPL_COMM_OFI_OOB=pmi2
CHPL_LAUNCHER=slurm-srun
CHPL_LOCALE_MODEL=flat
CHPL_TARGET_COMPILER=llvm
CHPL_LLVM=system
LIBFABRIC_DIR=/opt/libfabric
FI_PROVIDER=cxi
```

The `linux64` runtime (available in the Chapel base image for local/single-
node Chapel compilation, e.g. via `chapel-start linux64`):

```
CHPL_HOST_PLATFORM=linux64
CHPL_TARGET_PLATFORM=linux64
CHPL_COMM=none
CHPL_LIBFABRIC=none
CHPL_LAUNCHER=none
```

> **Potential enhancement:** `Containerfile.arkouda` currently
> builds Arkouda once, against the `hpe-cray-ex`/OFI runtime only. Building a
> second `arkouda_server` targeting `linux64`/`CHPL_COMM=none` (mirroring
> what the Chapel base image already supports for the `chpl` compiler) would
> let a single image serve both multi-node and single-node use without
> SLURM. Not implemented here — noted for future work.

## Troubleshooting

**Chapel base image not found**
```
Error: Chapel base image 'localhost/chapel-2.9.0-libfabric-2.3.1-cxi-pic:latest' not found!
```
Build it first: `./scripts/build-chapel-dist-cxi-2.3.1-pic.sh`.

**Chapel base image doesn't expose the Python `chapel` module**

Rebuild the Chapel base image — the `arkouda-builder` stage of
`Containerfile.arkouda` needs `make chapel-py-venv` to have run in
the base image.

**Validate the Chapel base image directly**
```bash
docker run --rm localhost/chapel-2.9.0-libfabric-2.3.1-cxi-pic:latest chapel-validate-hpe-ex
```
Checks that `chpl`, libfabric, PMI2, and (if present) the CXI dev headers are
all in place, then runs a Chapel compile smoke test.

## Legacy / reference material

These are kept for historical reference but are **not** part of the
maintained build framework:

| Path | What it is |
|---|---|
| `containers/legacy/`, `scripts/legacy/`, `patches/legacy/` | The original monolithic `Containerfile.chapel-arkouda` (builds Chapel/libfabric/SLURM from source) and the standalone `Containerfile.arkouda-client` image, with their build/run scripts and patches |
| `docs/driver-container-design.md` | Design notes exploring a SLURM-controller "driver" container for nested Apptainer execution — not implemented |
| `slurm-docker-cluster/` | A vendored copy of [giovtorres/slurm-docker-cluster](https://github.com/giovtorres/slurm-docker-cluster), kept as a reference for future driver-container work |
| `results/`, `hotlum-ak-results.tar.gz` | Benchmark data from prior performance investigations, unrelated to building these containers |
