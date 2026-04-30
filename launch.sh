#!/bin/bash
set -euo pipefail

# =============================================================================
# launch.sh  —  Embedded Linux Build Environment Launcher
#
# Builds and runs a container with toolchains for Buildroot, Yocto, OpenWrt, etc.
# Usage:
#   ./launch.sh                       # interactive menu
#   ./launch.sh 22.04                 # base profile
#   ./launch.sh embedded 22.04        # embedded profile
#   ./launch.sh -w /opt -w /data 22.04 # base + extra mounts
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_WORKSPACE_DIR="$(dirname "$SCRIPT_DIR")"
WORKSPACE_DIR="${WORKSPACE_DIR:-$DEFAULT_WORKSPACE_DIR}"
PROFILE="${PROFILE:-base}"

SUPPORTED_VERSIONS=("18.04" "22.04" "25.04")
DEFAULT_VERSION="22.04"
SUPPORTED_PROFILES=("base" "embedded")

# Color helpers
CYAN="63"
GREEN="42"
YELLOW="208"
RED="196"
BORDER_COLOR="63"

# ---------------------------------------------------------------------------
# Parse flags
# ---------------------------------------------------------------------------
EXTRA_MOUNTS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    -w)
      if [[ $# -lt 2 ]]; then
        echo "❌  -w requires a path" >&2
        exit 1
      fi
      EXTRA_MOUNTS+=(-v "$2:$2")
      shift 2
      ;;
    --)
      shift
      break
      ;;
    -*)
      echo "❌  Unknown option: $1" >&2
      exit 1
      ;;
    *)
      break
      ;;
  esac
done

# ---------------------------------------------------------------------------
# Determine profile and Ubuntu version from remaining positional args
# ---------------------------------------------------------------------------
if [ $# -ge 1 ]; then
  case "$1" in
  base | embedded)
    PROFILE="$1"
    if [ $# -ge 2 ]; then
      UBUNTU_VERSION="$2"
    else
      UBUNTU_VERSION=""
    fi
    ;;
  *)
    UBUNTU_VERSION="$1"
    ;;
  esac
else
  echo ""
  gum style \
    --border rounded \
    --padding "1 3" \
    --margin "0 1" \
    --border-foreground "$BORDER_COLOR" \
    --foreground "$CYAN" \
    "🐳  Embedded Linux Build Environment"

  echo ""

  CHOICE_PROFILE=$(gum choose \
    --header "Select environment profile:" \
    --cursor "→ " \
    --selected.foreground "$CYAN" \
    "base     (generic embedded Linux build host)" \
    "embedded (base image + RTOS/SDK host tools)")

  case "$CHOICE_PROFILE" in
  base*) PROFILE="base" ;;
  embedded*) PROFILE="embedded" ;;
  *)
    gum style --foreground "$YELLOW" "⚠️  No profile selected. Using default: $PROFILE"
    ;;
  esac

  echo ""

  CHOICE=$(gum choose \
    --header "Select Ubuntu base image:" \
    --cursor "→ " \
    --selected.foreground "$CYAN" \
    "18.04  (LTS — legacy projects)" \
    "22.04  (LTS — recommended)" \
    "25.04  (non-LTS — latest)")

  case "$CHOICE" in
  18.04*) UBUNTU_VERSION="18.04" ;;
  22.04*) UBUNTU_VERSION="22.04" ;;
  25.04*) UBUNTU_VERSION="25.04" ;;
  *)
    gum style --foreground "$YELLOW" "⚠️  No selection made. Using default: $DEFAULT_VERSION"
    UBUNTU_VERSION="$DEFAULT_VERSION"
    ;;
  esac

  echo ""
  while gum confirm --prompt.foreground "$CYAN" "📂  Mount extra host path into container?"; do
    MOUNT_PATH=$(gum input --placeholder "/opt" --prompt "Path: ")
    if [[ -n "$MOUNT_PATH" && -e "$MOUNT_PATH" ]]; then
      EXTRA_MOUNTS+=(-v "$MOUNT_PATH:$MOUNT_PATH")
      gum style --foreground "$GREEN" "   Added: $MOUNT_PATH"
    elif [[ -n "$MOUNT_PATH" ]]; then
      gum style --foreground "$YELLOW" "   ⚠️  Path does not exist: $MOUNT_PATH — skipping"
    fi
    echo ""
  done
fi

# Validate profile
PROFILE_VALID=0
for P in "${SUPPORTED_PROFILES[@]}"; do
  [[ "$PROFILE" == "$P" ]] && PROFILE_VALID=1 && break
done
if [ "$PROFILE_VALID" -eq 0 ]; then
  echo ""
  gum style --foreground "$RED" "❌  Unsupported profile: '$PROFILE'"
  gum style --foreground "$YELLOW" "   Supported: ${SUPPORTED_PROFILES[*]}"
  exit 1
fi

# Default version if omitted in non-interactive profile mode
if [[ -z "${UBUNTU_VERSION:-}" ]]; then
  UBUNTU_VERSION="$DEFAULT_VERSION"
fi

# Validate
VALID=0
for V in "${SUPPORTED_VERSIONS[@]}"; do
  [[ "$UBUNTU_VERSION" == "$V" ]] && VALID=1 && break
done
if [ "$VALID" -eq 0 ]; then
  echo ""
  gum style --foreground "$RED" "❌  Unsupported Ubuntu version: '$UBUNTU_VERSION'"
  gum style --foreground "$YELLOW" "   Supported: ${SUPPORTED_VERSIONS[*]}"
  exit 1
fi

BASE_IMAGE_TAG="zbuilder:ubuntu-${UBUNTU_VERSION}"
BASE_DOCKERFILE="$SCRIPT_DIR/docker/base/Dockerfile.ubuntu-${UBUNTU_VERSION}"
DOCKERFILE="$BASE_DOCKERFILE"
IMAGE_TAG="$BASE_IMAGE_TAG"

case "$PROFILE" in
base) ;;
embedded)
  if [[ "$UBUNTU_VERSION" == "18.04" ]]; then
    echo ""
    gum style --foreground "$RED" "❌  Profile '$PROFILE' requires Ubuntu 22.04 or newer."
    exit 1
  fi
  DOCKERFILE="$SCRIPT_DIR/docker/embedded/Dockerfile.ubuntu-${UBUNTU_VERSION}"
  IMAGE_TAG="zbuilder:${PROFILE}-${UBUNTU_VERSION}"
  ;;
esac

WORKSPACE_DIR="$(cd "$WORKSPACE_DIR" && pwd)"
BUILD_CONTEXT="$SCRIPT_DIR"

# ---------------------------------------------------------------------------
# Display configuration
# ---------------------------------------------------------------------------
echo ""
gum style \
  --border normal \
  --padding "1 2" \
  --margin "0 1" \
  --border-foreground "$BORDER_COLOR" \
  "$(
    gum format <<EOF
### Build Configuration
- **Profile:** \`$PROFILE\`
- **Ubuntu version:** \`$UBUNTU_VERSION\`
- **Dockerfile:** \`$(basename "$DOCKERFILE")\`
- **Image tag:** \`$IMAGE_TAG\`
- **Workspace:** \`$WORKSPACE_DIR\`
EOF
  )"

echo ""

# ---------------------------------------------------------------------------
# Detect docker vs sudo docker
# ---------------------------------------------------------------------------
DOCKER_CMD="docker"
if ! docker info >/dev/null 2>&1; then
  gum style --foreground "$YELLOW" "ℹ️  Docker not accessible without sudo — switching to 'sudo -E docker'."
  DOCKER_CMD="sudo -E docker"
fi

# ---------------------------------------------------------------------------
# Optional proxy args (works with and without proxy env)
# PROXY_MODE: auto | on | off (default: off)
# BUILD_NETWORK: host | default (default: host)
# UBUNTU_MIRROR: optional apt mirror URL for faster first-time apt downloads
# AUTO_UBUNTU_MIRROR: on | off (default: on when UBUNTU_MIRROR is unset)
# ---------------------------------------------------------------------------
PROXY_MODE="${PROXY_MODE:-off}"
BUILD_NETWORK="${BUILD_NETWORK:-host}"
UBUNTU_MIRROR="${UBUNTU_MIRROR:-}"
AUTO_UBUNTU_MIRROR="${AUTO_UBUNTU_MIRROR:-on}"

case "$PROXY_MODE" in
auto | on | off) ;;
*)
  gum style --foreground "$YELLOW" "⚠️  Invalid PROXY_MODE='$PROXY_MODE'. Using 'off'."
  PROXY_MODE="off"
  ;;
esac

case "$AUTO_UBUNTU_MIRROR" in
on | off) ;;
*)
  gum style --foreground "$YELLOW" "⚠️  Invalid AUTO_UBUNTU_MIRROR='$AUTO_UBUNTU_MIRROR'. Using 'on'."
  AUTO_UBUNTU_MIRROR="on"
  ;;
esac

ubuntu_codename_for_version() {
  case "$1" in
  18.04) echo "bionic" ;;
  22.04) echo "jammy" ;;
  25.04) echo "plucky" ;;
  *) echo "" ;;
  esac
}

select_fast_ubuntu_mirror() {
  local codename="$1"
  local best_mirror=""
  local best_ttfb="999999"
  local mirror

  [[ -n "$codename" ]] || return 0
  command -v curl >/dev/null 2>&1 || return 0

  for mirror in \
    "http://archive.ubuntu.com/ubuntu" \
    "http://mirrors.edge.kernel.org/ubuntu" \
    "http://ftp.fau.de/ubuntu"; do
    local inrelease_url="${mirror}/dists/${codename}/InRelease"
    local curl_result
    local http_code
    local ttfb
    curl_result="$(curl -4 --max-time 6 -L -o /dev/null -s -w '%{http_code} %{time_starttransfer}' "$inrelease_url" || true)"
    http_code="${curl_result%% *}"
    ttfb="${curl_result##* }"
    if [[ "$http_code" == "200" ]] && awk "BEGIN { exit !($ttfb > 0 && $ttfb < $best_ttfb) }"; then
      best_ttfb="$ttfb"
      best_mirror="$mirror"
    fi
  done

  echo "$best_mirror"
}

PROXY_BUILD_ARGS=()
PROXY_RUN_ARGS=()
PROXY_ENV_COUNT=0

if [[ -z "$UBUNTU_MIRROR" && "$AUTO_UBUNTU_MIRROR" == "on" ]]; then
  UBUNTU_CODENAME="$(ubuntu_codename_for_version "$UBUNTU_VERSION")"
  AUTO_SELECTED_MIRROR="$(select_fast_ubuntu_mirror "$UBUNTU_CODENAME")"
  if [[ -n "$AUTO_SELECTED_MIRROR" ]]; then
    UBUNTU_MIRROR="$AUTO_SELECTED_MIRROR"
    gum style --foreground "$CYAN" "ℹ️  Using Ubuntu mirror: $UBUNTU_MIRROR"
  fi
fi

if [[ -n "$UBUNTU_MIRROR" ]]; then
  PROXY_BUILD_ARGS+=(--build-arg "UBUNTU_MIRROR=${UBUNTU_MIRROR}")
fi

add_proxy_var() {
  local key="$1"
  local val="${!key-}" # safe with 'set -u' even when unset
  if [[ -n "$val" ]]; then
    PROXY_ENV_COUNT=$((PROXY_ENV_COUNT + 1))
    PROXY_BUILD_ARGS+=(--build-arg "${key}=${val}")
    PROXY_RUN_ARGS+=(-e "${key}=${val}")
  fi
}

if [[ "$PROXY_MODE" != "off" ]]; then
  for key in HTTP_PROXY HTTPS_PROXY http_proxy https_proxy NO_PROXY no_proxy; do
    add_proxy_var "$key"
  done
fi

if [[ "$PROXY_MODE" == "on" && "$PROXY_ENV_COUNT" -eq 0 ]]; then
  gum style --foreground "$YELLOW" "⚠️  PROXY_MODE=on but no proxy variables are set in the environment."
fi

build_image() {
  local dockerfile="$1"
  local image_tag="$2"

  echo ""
  gum style \
    --border rounded \
    --padding "0 2" \
    --margin "0 1" \
    --border-foreground "$CYAN" \
    --foreground "$CYAN" \
    "🔨  Building image: $image_tag"
  echo ""

  DOCKER_BUILDKIT=1 $DOCKER_CMD build \
    --platform linux/amd64 \
    --network="$BUILD_NETWORK" \
    ${PROXY_BUILD_ARGS[@]+"${PROXY_BUILD_ARGS[@]}"} \
    --build-arg USER_ID="$(id -u)" \
    --build-arg GROUP_ID="$(id -g)" \
    -t "$image_tag" \
    -f "$dockerfile" \
    "$BUILD_CONTEXT"

  echo ""
  gum style --foreground "$GREEN" "✅  Image built: $image_tag"
}

# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------
build_image "$BASE_DOCKERFILE" "$BASE_IMAGE_TAG"

if [[ "$PROFILE" == "embedded" ]]; then
  build_image "$DOCKERFILE" "$IMAGE_TAG"
fi
echo ""

# ---------------------------------------------------------------------------
# Run
# ---------------------------------------------------------------------------
gum style --foreground "$CYAN" "🚀  Launching container (workspace mounted at /workspace) ..."
echo ""

$DOCKER_CMD run \
  --rm -it \
  --network host \
  ${PROXY_RUN_ARGS[@]+"${PROXY_RUN_ARGS[@]}"} \
  -v "${WORKSPACE_DIR}:/workspace" \
  ${EXTRA_MOUNTS[@]+"${EXTRA_MOUNTS[@]}"} \
  "$IMAGE_TAG"
