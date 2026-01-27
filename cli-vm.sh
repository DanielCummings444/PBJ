#!/usr/bin/env bash
# ──────────────────────────────────────────────
# cli-vm.sh — Build, run, and manage the CLI-VM
# ──────────────────────────────────────────────
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE_NAME="pbj-cli-vm:latest"
CONTAINER_NAME="pbj-cli-vm"

usage() {
    cat <<EOF
Usage: $(basename "$0") <command> [args...]

Commands:
  build         Build the Docker image
  start         Start the CLI-VM container (detached)
  stop          Stop the running container
  shell         Open an interactive bash shell in the VM
  exec <cmd>    Run a one-off command inside the VM
  status        Show container status
  logs          Show container logs
  destroy       Stop and remove container + volumes
  rebuild       Destroy, rebuild image, and start fresh
  help          Show this help message

Examples:
  $(basename "$0") build            # Build the image
  $(basename "$0") start            # Start in background
  $(basename "$0") shell            # Drop into a bash session
  $(basename "$0") exec jq --help   # Run a command
  $(basename "$0") exec python3 -c "print('hello')"
EOF
}

cmd_build() {
    echo "Building CLI-VM image..."
    docker build -t "$IMAGE_NAME" "$SCRIPT_DIR"
    echo "Done. Image: $IMAGE_NAME"
}

cmd_start() {
    if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        echo "CLI-VM is already running."
        return 0
    fi

    # Remove stopped container with the same name if it exists
    if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        docker rm "$CONTAINER_NAME" >/dev/null 2>&1 || true
    fi

    echo "Starting CLI-VM..."
    docker compose -f "$SCRIPT_DIR/docker-compose.yml" up -d
    echo "CLI-VM is running. Use '$(basename "$0") shell' to connect."
}

cmd_stop() {
    echo "Stopping CLI-VM..."
    docker compose -f "$SCRIPT_DIR/docker-compose.yml" stop
}

cmd_shell() {
    if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        echo "CLI-VM is not running. Starting it first..."
        cmd_start
    fi
    docker exec -it "$CONTAINER_NAME" bash
}

cmd_exec() {
    if [ $# -eq 0 ]; then
        echo "Error: No command specified."
        echo "Usage: $(basename "$0") exec <command> [args...]"
        exit 1
    fi

    if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        echo "CLI-VM is not running. Starting it first..."
        cmd_start
    fi
    docker exec -it "$CONTAINER_NAME" "$@"
}

cmd_status() {
    if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        echo "CLI-VM is running."
        docker ps --filter "name=${CONTAINER_NAME}" --format "table {{.ID}}\t{{.Status}}\t{{.Ports}}"
    elif docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        echo "CLI-VM exists but is stopped."
        docker ps -a --filter "name=${CONTAINER_NAME}" --format "table {{.ID}}\t{{.Status}}"
    else
        echo "CLI-VM container does not exist. Run '$(basename "$0") build && $(basename "$0") start'."
    fi
}

cmd_logs() {
    docker compose -f "$SCRIPT_DIR/docker-compose.yml" logs --tail=100 -f
}

cmd_destroy() {
    echo "Destroying CLI-VM (container + volumes)..."
    docker compose -f "$SCRIPT_DIR/docker-compose.yml" down -v
    echo "Done."
}

cmd_rebuild() {
    cmd_destroy || true
    cmd_build
    cmd_start
}

# ── Main ──────────────────────────────────────
if [ $# -eq 0 ]; then
    usage
    exit 1
fi

case "$1" in
    build)   cmd_build ;;
    start)   cmd_start ;;
    stop)    cmd_stop ;;
    shell)   cmd_shell ;;
    exec)    shift; cmd_exec "$@" ;;
    status)  cmd_status ;;
    logs)    cmd_logs ;;
    destroy) cmd_destroy ;;
    rebuild) cmd_rebuild ;;
    help|-h|--help) usage ;;
    *)
        echo "Unknown command: $1"
        usage
        exit 1
        ;;
esac
