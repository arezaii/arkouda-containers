#!/bin/bash
# Start SLURM services in container mode
# Set SLURM_CONTAINER_MODE=true to enable container SLURM

# Ensure Slurm binaries are in PATH
export PATH=/usr/sbin:/usr/bin:${PATH}

if [ "${SLURM_CONTAINER_MODE}" = "true" ]; then
    echo "Starting container SLURM services..."

    # Create required directories
    mkdir -p /var/spool/slurm/ctld /var/spool/slurm/d /var/run/slurm /var/log/slurm
    chmod 755 /var/spool/slurm /var/spool/slurm/ctld /var/spool/slurm/d /var/run/slurm /var/log/slurm
    chown -R root:root /var/spool/slurm /var/run/slurm /var/log/slurm

    # Create empty state files
    touch /var/spool/slurm/ctld/{node,job,resv,trigger}_state
    chmod 644 /var/spool/slurm/ctld/*_state

    # Create dbus directory and start dbus daemon (needed for cgroup management)
    mkdir -p /run/dbus
    dbus-daemon --system --print-address > /dev/null 2>&1 &
    sleep 1

    # Start munge
    service munge start 2>/dev/null || munged -f -D

    sleep 2

    # Clean up old processes
    pkill -9 slurmctld slurmd 2>/dev/null || true
    sleep 1

    # Auto-detect or use environment variables for CPU topology
    DETECTED_CPUS=$(nproc 2>/dev/null || echo "16")
    DETECTED_SOCKETS=$(lscpu -p=Socket 2>/dev/null | grep -v '^#' | sort -u | wc -l || echo "1")
    DETECTED_CORES=$(lscpu -p=Core 2>/dev/null | grep -v '^#' | sort -u | wc -l || echo "8")
    DETECTED_THREADS=$((DETECTED_CPUS / DETECTED_CORES))

    # Allow override via environment variables
    SLURM_CPUS=${SLURM_CPUS:-$DETECTED_CPUS}
    SLURM_SOCKETS=${SLURM_SOCKETS:-$DETECTED_SOCKETS}
    SLURM_CORES_PER_SOCKET=${SLURM_CORES_PER_SOCKET:-$DETECTED_CORES}
    SLURM_THREADS_PER_CORE=${SLURM_THREADS_PER_CORE:-$DETECTED_THREADS}

    echo "Configuring SLURM with: CPUs=${SLURM_CPUS} Sockets=${SLURM_SOCKETS} CoresPerSocket=${SLURM_CORES_PER_SOCKET} ThreadsPerCore=${SLURM_THREADS_PER_CORE}"

    # Update slurm.conf with actual CPU topology
    sed -i "s/^NodeName=localhost.*/NodeName=localhost CPUs=${SLURM_CPUS} Sockets=${SLURM_SOCKETS} CoresPerSocket=${SLURM_CORES_PER_SOCKET} ThreadsPerCore=${SLURM_THREADS_PER_CORE}/" /etc/slurm/slurm.conf

    # Start SLURM services
    export SLURM_CONF=/etc/slurm/slurm.conf

    # Start slurmctld - redirect errors to suppress noise
    (slurmctld -D -f /etc/slurm/slurm.conf 2>&1 | grep -v "mpi\|pmix\|dbus\|cgroup") > /tmp/slurmctld.log 2>&1 &
    sleep 3

    # Start slurmd - it will fail on cgroup initialization but we can work around that
    # by forcing the node to idle state manually
    (slurmd -D -f /etc/slurm/slurm.conf 2>&1 | grep -v "mpi\|pmix\|dbus\|cgroup") > /tmp/slurmd.log 2>&1 &
    sleep 4

    # Try to manually register the node with slurmctld since slurmd may have failed
    # Use reconfigure to bring node online
    slurmctld -C 2>/dev/null  # Show configuration
    scontrol reconfigure 2>/dev/null || true
    sleep 1

    # Force node to idle state multiple ways to ensure it works
    scontrol update NodeName=localhost State=IDLE 2>/dev/null || true
    sleep 1

    # If that didn't work, try adding the node
    NODE_COUNT=$(sinfo -h 2>/dev/null | wc -l)
    if [ "$NODE_COUNT" -lt 1 ]; then
        scontrol create NodeName=localhost CPUs=16 State=IDLE 2>/dev/null || true
        sleep 1
    fi

    # Verify status
    echo "SLURM Status:"
    sinfo 2>/dev/null | head -3 || echo "(SLURM initialization in progress)"
else
    echo "SLURM_CONTAINER_MODE not set - using host SLURM"
fi