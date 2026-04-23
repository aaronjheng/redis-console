#!/usr/bin/env bash
set -euo pipefail

REDIS_VERSIONS=("6" "7" "8")
BASE_PORT_STANDALONE=6370
BASE_PORT_CLUSTER=16370
NETWORK_NAME="redis-test-net"

ensure_network() {
    if ! container network list 2>/dev/null | grep -q "$NETWORK_NAME"; then
        container network create "$NETWORK_NAME" >/dev/null 2>&1 || true
    fi
}

start_standalone() {
    local version="$1"
    local port="$2"
    local name="redis-${version}-standalone"
    local image="docker.io/library/redis:${version}"

    if container list --all 2>/dev/null | grep -q "$name"; then
        container delete "$name" 2>/dev/null || true
    fi

    container run \
        --detach \
        --name "$name" \
        --network "$NETWORK_NAME" \
        --publish "127.0.0.1:${port}:6379" \
        "$image" \
        redis-server --save "" --appendonly no
    echo "Started $name on 127.0.0.1:${port}"
}

start_cluster() {
    local version="$1"
    local base_port="$2"
    local name_prefix="redis-${version}-cluster"
    local image="docker.io/library/redis:${version}"
    local cluster_dir="/tmp/redis-cluster-${version}"
    local nodes=()

    rm -rf "$cluster_dir"
    mkdir -p "$cluster_dir"

    for i in $(seq 0 5); do
        local port=$((base_port + i))
        local name="${name_prefix}-node-${i}"
        local node_dir="${cluster_dir}/node-${i}"
        mkdir -p "$node_dir"

        cat > "${node_dir}/redis.conf" <<EOF
port 6379
cluster-enabled yes
cluster-config-file nodes.conf
cluster-node-timeout 5000
appendonly no
save ""
EOF

        if container list --all 2>/dev/null | grep -q "$name"; then
            container delete "$name" 2>/dev/null || true
        fi

        container run \
            --detach \
            --name "$name" \
            --network "$NETWORK_NAME" \
            --publish "127.0.0.1:${port}:6379" \
            --publish "127.0.0.1:$((port + 10000)):16379" \
            --mount "type=bind,source=${node_dir},target=/data" \
            "$image" \
            redis-server /data/redis.conf

        nodes+=("127.0.0.1:${port}")
    done

    sleep 3

    local join_ips=""
    for node in "${nodes[@]}"; do
        if [ -n "$join_ips" ]; then
            join_ips="${join_ips} "
        fi
        join_ips="${join_ips}${node}"
    done

    echo "Redis ${version} cluster nodes started on ports ${base_port}-$((base_port + 5))"
    echo "Run manually to init cluster:"
    echo "  container exec ${name_prefix}-node-0 redis-cli --cluster create ${join_ips} --cluster-replicas 1 --yes"
    echo "Started ${name_prefix} nodes on 127.0.0.1:${base_port}-$((base_port + 5))"
}

echo "Ensuring network '$NETWORK_NAME' exists..."
ensure_network

for v in "${REDIS_VERSIONS[@]}"; do
    standalone_port=$((BASE_PORT_STANDALONE + v))
    start_standalone "$v" "$standalone_port"

    cluster_base=$((BASE_PORT_CLUSTER + v * 10))
    start_cluster "$v" "$cluster_base"
done

echo ""
echo "=== Redis Test Containers ==="
echo ""
echo "Standalone:"
for v in "${REDIS_VERSIONS[@]}"; do
    port=$((BASE_PORT_STANDALONE + v))
    echo "  Redis $v: 127.0.0.1:${port}"
done
echo ""
echo "Cluster (after cluster init):"
for v in "${REDIS_VERSIONS[@]}"; do
    base=$((BASE_PORT_CLUSTER + v * 10))
    echo "  Redis $v: 127.0.0.1:${base}-$((base + 5))"
done
