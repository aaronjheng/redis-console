#!/usr/bin/env bash
set -euo pipefail

REDIS_VERSIONS=("6" "7" "8")

for v in "${REDIS_VERSIONS[@]}"; do
    name="redis-${v}-standalone"
    container stop "$name" 2>/dev/null || true
    container delete "$name" 2>/dev/null || true

    for i in $(seq 0 5); do
        cname="redis-${v}-cluster-node-${i}"
        container stop "$cname" 2>/dev/null || true
        container delete "$cname" 2>/dev/null || true
    done
    rm -rf "/tmp/redis-cluster-${v}"
done

container network delete redis-test-net 2>/dev/null || true
echo "All Redis test containers stopped and removed"
