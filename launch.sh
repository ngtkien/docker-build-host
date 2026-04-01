#!/bin/bash
set -euo pipefail

# =============================================================================
# docker/launch.sh  —  Airoha SDK Docker Launcher
#
# Builds and runs the Airoha build-environment container.
# Usage:
#   ./docker/launch.sh              # interactive menu
#   ./docker/launch.sh 18.04        # non-interactive
#   ./docker/launch.sh 22.04
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_DIR="$(dirname "$SCRIPT_DIR")"   # one level up from docker/

SUPPORTED_VERSIONS=("18.04" "22.04")
DEFAULT_VERSION="22.04"

# ---------------------------------------------------------------------------
# Determine Ubuntu version
# ---------------------------------------------------------------------------
if [ $# -ge 1 ]; then
  UBUNTU_VERSION="$1"
else
  echo ""
  echo "════════════════════════════════════════════════════════════════"
  echo "  Airoha SDK — Docker Launcher"
  echo "════════════════════════════════════════════════════════════════"
  echo ""
  echo "  Select Ubuntu base image:"
  echo ""
  echo "    1) Ubuntu 18.04  (LTS — original SDK requirement)"
  echo "    2) Ubuntu 22.04  (LTS — recommended)"
  echo "    3) Ubuntu 25.04  (non-LTS — latest)"
  echo ""
  read -rp "  Enter choice [1-3] (default: 2): " CHOICE
  case "${CHOICE:-2}" in
    1) UBUNTU_VERSION="18.04" ;;
    2) UBUNTU_VERSION="22.04" ;;
    *) echo "  ⚠️  Invalid choice. Using default: $DEFAULT_VERSION"; UBUNTU_VERSION="$DEFAULT_VERSION" ;;
  esac
fi

# Validate
VALID=0
for V in "${SUPPORTED_VERSIONS[@]}"; do
  [[ "$UBUNTU_VERSION" == "$V" ]] && VALID=1 && break
done
if [ "$VALID" -eq 0 ]; then
  echo ""
  echo "  ❌  Unsupported Ubuntu version: '$UBUNTU_VERSION'"
  echo "      Supported: ${SUPPORTED_VERSIONS[*]}"
  exit 1
fi

DOCKERFILE="$SCRIPT_DIR/Dockerfile.ubuntu-${UBUNTU_VERSION}"
IMAGE_TAG="buidroot-builder:ubuntu-${UBUNTU_VERSION}"

echo ""
echo "════════════════════════════════════════════════════════════════"
echo "  Ubuntu version : $UBUNTU_VERSION"
echo "  Dockerfile     : docker/Dockerfile.ubuntu-${UBUNTU_VERSION}"
echo "  Image tag      : $IMAGE_TAG"
echo "  Workspace      : $WORKSPACE_DIR"
echo "════════════════════════════════════════════════════════════════"
echo ""

# ---------------------------------------------------------------------------
# Detect docker vs sudo docker
# ---------------------------------------------------------------------------
DOCKER_CMD="docker"
if ! docker info > /dev/null 2>&1; then
  echo "  ℹ️  Docker not accessible without sudo — switching to 'sudo -E docker'."
  DOCKER_CMD="sudo -E docker"
fi

# ---------------------------------------------------------------------------
# Optional proxy args (works with and without proxy env)
# PROXY_MODE: auto | on | off (default: auto)
# BUILD_NETWORK: host | default (default: host)
# ---------------------------------------------------------------------------
PROXY_MODE="${PROXY_MODE:-auto}"
BUILD_NETWORK="${BUILD_NETWORK:-host}"

case "$PROXY_MODE" in
  auto|on|off) ;;
  *)
    echo "  ⚠️  Invalid PROXY_MODE='$PROXY_MODE'. Using 'auto'."
    PROXY_MODE="auto"
    ;;
esac

PROXY_BUILD_ARGS=()
PROXY_RUN_ARGS=()

add_proxy_var() {
  local key="$1"
  local val="${!key-}"   # safe with 'set -u' even when unset
  if [[ -n "$val" ]]; then
    PROXY_BUILD_ARGS+=(--build-arg "${key}=${val}")
    PROXY_RUN_ARGS+=(-e "${key}=${val}")
  fi
}

if [[ "$PROXY_MODE" != "off" ]]; then
  for key in HTTP_PROXY HTTPS_PROXY http_proxy https_proxy NO_PROXY no_proxy; do
    add_proxy_var "$key"
  done
fi

if [[ "$PROXY_MODE" == "on" && ${#PROXY_BUILD_ARGS[@]} -eq 0 ]]; then
  echo "  ⚠️  PROXY_MODE=on but no proxy variables are set in the environment."
fi

# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------
echo "  → Building image: $IMAGE_TAG"
DOCKER_BUILDKIT=1 $DOCKER_CMD build \
  --network="$BUILD_NETWORK" \
  "${PROXY_BUILD_ARGS[@]}" \
  --build-arg USER_ID="$(id -u)" \
  --build-arg GROUP_ID="$(id -g)" \
  -t "$IMAGE_TAG" \
  -f "$DOCKERFILE" \
  "$WORKSPACE_DIR"

echo ""
echo "  ✅  Image built: $IMAGE_TAG"
echo ""


# ---------------------------------------------------------------------------
# Run
# ---------------------------------------------------------------------------
echo "  → Launching container (workspace mounted at /workspace) ..."
echo ""

$DOCKER_CMD run \
  --rm -it \
  --network host \
  "${PROXY_RUN_ARGS[@]}" \
  -v "${WORKSPACE_DIR}:/workspace" \
  -v /opt:/opt \
  "$IMAGE_TAG"
