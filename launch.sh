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

# Color helpers (ANSI Escape Codes for fallback, 256-color for gum)
GUM_CYAN="63"
GUM_GREEN="42"
GUM_YELLOW="208"
GUM_RED="196"
GUM_BORDER_COLOR="63"

BOLD="\033[1m"
GREEN="\033[1;32m"
CYAN="\033[1;36m"
YELLOW="\033[1;33m"
RED="\033[1;31m"
RESET="\033[0m"

# ---------------------------------------------------------------------------
# Parse flags
# ---------------------------------------------------------------------------
EXTRA_MOUNTS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    -w)
      if [[ $# -lt 2 ]]; then
        echo -e "${RED}❌  -w requires a path${RESET}" >&2
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
      echo -e "${RED}❌  Unknown option: $1${RESET}" >&2
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
elif [ ${#EXTRA_MOUNTS[@]} -gt 0 ]; then
  # Non-interactive with only -w flags provided, use defaults
  UBUNTU_VERSION=""
else
  # Interactive mode
  if command -v gum >/dev/null 2>&1; then
    echo ""
    gum style \
      --border rounded \
      --padding "1 3" \
      --margin "0 1" \
      --border-foreground "$GUM_BORDER_COLOR" \
      --foreground "$GUM_CYAN" \
      "🐳  Embedded Linux Build Environment"

    echo ""
    CHOICE_PROFILE=$(gum choose \
      --header "Select environment profile:" \
      --cursor "→ " \
      --selected.foreground "$GUM_CYAN" \
      "base     (generic embedded Linux build host)" \
      "embedded (base image + RTOS/SDK host tools)")

    case "$CHOICE_PROFILE" in
    base*) PROFILE="base" ;;
    embedded*) PROFILE="embedded" ;;
    *)
      gum style --foreground "$GUM_YELLOW" "⚠️  No profile selected. Using default: $PROFILE"
      ;;
    esac

    echo ""
    CHOICE=$(gum choose \
      --header "Select Ubuntu base image:" \
      --cursor "→ " \
      --selected.foreground "$GUM_CYAN" \
      "18.04  (LTS — legacy projects)" \
      "22.04  (LTS — recommended)" \
      "25.04  (non-LTS — latest)")

    case "$CHOICE" in
    18.04*) UBUNTU_VERSION="18.04" ;;
    22.04*) UBUNTU_VERSION="22.04" ;;
    25.04*) UBUNTU_VERSION="25.04" ;;
    *)
      gum style --foreground "$GUM_YELLOW" "⚠️  No selection made. Using default: $DEFAULT_VERSION"
      UBUNTU_VERSION="$DEFAULT_VERSION"
      ;;
    esac

    echo ""
    while gum confirm --prompt.foreground "$GUM_CYAN" "📂  Mount extra host path into container?"; do
      MOUNT_PATH=$(gum input --placeholder "/opt" --prompt "Path: ")
      if [[ -n "$MOUNT_PATH" && -e "$MOUNT_PATH" ]]; then
        EXTRA_MOUNTS+=(-v "$MOUNT_PATH:$MOUNT_PATH")
        gum style --foreground "$GUM_GREEN" "   Added: $MOUNT_PATH"
      elif [[ -n "$MOUNT_PATH" ]]; then
        gum style --foreground "$GUM_YELLOW" "   ⚠️  Path does not exist: $MOUNT_PATH — skipping"
      fi
      echo ""
    done
  else
    # Fallback to standard CLI menu when gum is not installed
    echo -e "${CYAN}=============================================${RESET}"
    echo -e "${BOLD}🐳  Embedded Linux Build Environment${RESET}"
    echo -e "${CYAN}=============================================${RESET}"
    echo ""

    echo -e "${BOLD}Select environment profile:${RESET}"
    echo "1) base     (generic embedded Linux build host)"
    echo "2) embedded (base image + RTOS/SDK host tools)"
    read -p "Option [1-2]: " -r PROFILE_OPT
    case "$PROFILE_OPT" in
      2) PROFILE="embedded" ;;
      *) PROFILE="base" ;;
    esac
    echo -e "Selected profile: ${GREEN}$PROFILE${RESET}\n"

    echo -e "${BOLD}Select Ubuntu base image:${RESET}"
    echo "1) 18.04  (LTS — legacy projects)"
    echo "2) 22.04  (LTS — recommended)"
    echo "3) 25.04  (non-LTS — latest)"
    read -p "Option [1-3]: " -r VERSION_OPT
    case "$VERSION_OPT" in
      1) UBUNTU_VERSION="18.04" ;;
      3) UBUNTU_VERSION="25.04" ;;
      *) UBUNTU_VERSION="22.04" ;;
    esac
    echo -e "Selected Ubuntu version: ${GREEN}$UBUNTU_VERSION${RESET}\n"

    while true; do
      read -p "📂 Mount extra host path into container? (y/N): " -r yn
      case $yn in
        [Yy]* ) 
          read -p "Enter absolute path to mount: " -r MOUNT_PATH
          if [[ -n "$MOUNT_PATH" && -e "$MOUNT_PATH" ]]; then
            EXTRA_MOUNTS+=(-v "$MOUNT_PATH:$MOUNT_PATH")
            echo -e "   ${GREEN}Added: $MOUNT_PATH${RESET}"
          elif [[ -n "$MOUNT_PATH" ]]; then
            echo -e "   ${YELLOW}⚠️  Path does not exist: $MOUNT_PATH — skipping${RESET}"
          fi
          echo ""
          ;;
        * ) break;;
      esac
    done
  fi
fi

# Validate profile
PROFILE_VALID=0
for P in "${SUPPORTED_PROFILES[@]}"; do
  [[ "$PROFILE" == "$P" ]] && PROFILE_VALID=1 && break
done
if [ "$PROFILE_VALID" -eq 0 ]; then
  echo -e "\n${RED}❌  Unsupported profile: '$PROFILE'${RESET}"
  echo -e "${YELLOW}   Supported: ${SUPPORTED_PROFILES[*]}${RESET}"
  exit 1
fi

# Default version if omitted in non-interactive profile mode
if [[ -z "${UBUNTU_VERSION:-}" ]]; then
  UBUNTU_VERSION="$DEFAULT_VERSION"
fi

# Validate Ubuntu version
VALID=0
for V in "${SUPPORTED_VERSIONS[@]}"; do
  [[ "$UBUNTU_VERSION" == "$V" ]] && VALID=1 && break
done
if [ "$VALID" -eq 0 ]; then
  echo -e "\n${RED}❌  Unsupported Ubuntu version: '$UBUNTU_VERSION'${RESET}"
  echo -e "${YELLOW}   Supported: ${SUPPORTED_VERSIONS[*]}${RESET}"
  exit 1
fi

DOCKERFILE="$SCRIPT_DIR/docker/Dockerfile.ubuntu-${UBUNTU_VERSION}"

# Profile checks
if [[ "$PROFILE" == "embedded" && "$UBUNTU_VERSION" == "18.04" ]]; then
  echo -e "\n${RED}❌  Profile '$PROFILE' requires Ubuntu 22.04 or newer.${RESET}"
  exit 1
fi

IMAGE_TAG="zbuilder:${PROFILE}-${UBUNTU_VERSION}"
WORKSPACE_DIR="$(cd "$WORKSPACE_DIR" && pwd)"
BUILD_CONTEXT="$SCRIPT_DIR"

# ---------------------------------------------------------------------------
# Display configuration
# ---------------------------------------------------------------------------
if command -v gum >/dev/null 2>&1; then
  echo ""
  gum style \
    --border normal \
    --padding "1 2" \
    --margin "0 1" \
    --border-foreground "$GUM_BORDER_COLOR" \
    "$(
      gum format <<EOF
### Build Configuration
- **Profile:** \`$PROFILE\`
- **Ubuntu version:** \`$UBUNTU_VERSION\`
- **Dockerfile:** \`$(basename "$DOCKERFILE")\`
- **Image tag:** \`$IMAGE_TAG\`
- **Workspace:** \`$WORKSPACE_DIR\`
- **Extra mounts:** \`${#EXTRA_MOUNTS[@]} path(s)\`
EOF
    )"
  echo ""
else
  echo -e "\n${BOLD}--- Build Configuration ---${RESET}"
  echo -e "  Profile:        ${GREEN}$PROFILE${RESET}"
  echo -e "  Ubuntu version: ${GREEN}$UBUNTU_VERSION${RESET}"
  echo -e "  Dockerfile:     ${GREEN}$(basename "$DOCKERFILE")${RESET}"
  echo -e "  Image tag:      ${GREEN}$IMAGE_TAG${RESET}"
  echo -e "  Workspace:      ${GREEN}$WORKSPACE_DIR${RESET}"
  echo -e "  Extra mounts:   ${GREEN}${#EXTRA_MOUNTS[@]} path(s)${RESET}\n"
fi

# ---------------------------------------------------------------------------
# Detect docker vs sudo docker
# ---------------------------------------------------------------------------
DOCKER_CMD="docker"
if ! docker info >/dev/null 2>&1; then
  if command -v gum >/dev/null 2>&1; then
    gum style --foreground "$GUM_YELLOW" "ℹ️  Docker not accessible without sudo — switching to 'sudo -E docker'."
  else
    echo -e "${YELLOW}ℹ️  Docker not accessible without sudo — switching to 'sudo -E docker'.${RESET}"
  fi
  DOCKER_CMD="sudo -E docker"
fi

# ---------------------------------------------------------------------------
# Optional proxy args (works with and without proxy env)
# ---------------------------------------------------------------------------
PROXY_MODE="${PROXY_MODE:-off}"
BUILD_NETWORK="${BUILD_NETWORK:-host}"

case "$PROXY_MODE" in
  auto | on | off) ;;
  *)
    echo -e "${YELLOW}⚠️  Invalid PROXY_MODE='$PROXY_MODE'. Using 'off'.${RESET}"
    PROXY_MODE="off"
    ;;
esac

PROXY_BUILD_ARGS=()
PROXY_RUN_ARGS=()
PROXY_ENV_COUNT=0

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
  echo -e "${YELLOW}⚠️  PROXY_MODE=on but no proxy variables are set in the environment.${RESET}"
fi

# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------
if command -v gum >/dev/null 2>&1; then
  echo ""
  gum style \
    --border rounded \
    --padding "0 2" \
    --margin "0 1" \
    --border-foreground "$GUM_CYAN" \
    --foreground "$GUM_CYAN" \
    "🔨  Building image: $IMAGE_TAG"
  echo ""
else
  echo -e "${CYAN}🔨  Building image: $IMAGE_TAG ...${RESET}"
fi

# Determine target stage for multi-stage Dockerfiles
TARGET_STAGE=""
if [[ "$UBUNTU_VERSION" != "18.04" ]]; then
  TARGET_STAGE="--target $PROFILE"
fi

DOCKER_BUILDKIT=1 $DOCKER_CMD build \
  --platform linux/amd64 \
  --network="$BUILD_NETWORK" \
  ${PROXY_BUILD_ARGS[@]+"${PROXY_BUILD_ARGS[@]}"} \
  $TARGET_STAGE \
  -t "$IMAGE_TAG" \
  -f "$DOCKERFILE" \
  "$BUILD_CONTEXT"

if command -v gum >/dev/null 2>&1; then
  echo ""
  gum style --foreground "$GUM_GREEN" "✅  Image built: $IMAGE_TAG"
  echo ""
else
  echo -e "${GREEN}✅  Image built: $IMAGE_TAG${RESET}\n"
fi

# ---------------------------------------------------------------------------
# Run
# ---------------------------------------------------------------------------
if command -v gum >/dev/null 2>&1; then
  gum style --foreground "$GUM_CYAN" "🚀  Launching container (workspace mounted at /workspace) ..."
  echo ""
else
  echo -e "${CYAN}🚀  Launching container (workspace mounted at /workspace) ...${RESET}\n"
fi

# Run Docker container with HOST_UID & HOST_GID set to align builder user permissions
$DOCKER_CMD run \
  --rm -it \
  --network host \
  -e HOST_UID="$(id -u)" \
  -e HOST_GID="$(id -g)" \
  ${PROXY_RUN_ARGS[@]+"${PROXY_RUN_ARGS[@]}"} \
  -v "${WORKSPACE_DIR}:/workspace" \
  ${EXTRA_MOUNTS[@]+"${EXTRA_MOUNTS[@]}"} \
  "$IMAGE_TAG"