# Embedded Linux Build Environment

Docker-based build environment for embedded Linux projects. The workspace is organized around reusable Ubuntu base images plus profile overlays for **Zephyr** and **ESP-IDF**.

## Prerequisites

- Docker
- [gum](https://github.com/charmbracelet/gum) (for interactive menu)

## Quick Start

```bash
./launch.sh
```

Select your Ubuntu version from the interactive menu. The container builds and launches automatically with your workspace mounted.

## Usage

### Interactive mode

```bash
./launch.sh
```

### Non-interactive mode

```bash
./launch.sh 22.04
./launch.sh 18.04
./launch.sh 25.04
./launch.sh zephyr 22.04
./launch.sh esp-idf 25.04
```

The old form `./launch.sh 22.04` still launches the generic `base` profile. Use `./launch.sh zephyr 22.04` or `./launch.sh esp-idf 25.04` for profile overlays.

`zephyr` and `esp-idf` require Ubuntu `22.04` or newer. `18.04` remains available only for the generic `base` profile.

### Environment variables

| Variable | Values | Default | Description |
|---|---|---|---|
| `PROXY_MODE` | `auto`, `on`, `off` | `auto` | Proxy handling for build and run |
| `BUILD_NETWORK` | `host`, `default` | `host` | Docker network mode during build |
| `WORKSPACE_DIR` | host path | parent of this repo | Host directory mounted into `/workspace` |
| `PROFILE` | `base`, `zephyr`, `esp-idf` | `base` | Default launch profile when not passed as an argument |

```bash
PROXY_MODE=on ./launch.sh 22.04
WORKSPACE_DIR=$HOME/work/zephyr ./launch.sh zephyr 22.04
WORKSPACE_DIR=$HOME/work/esp ./launch.sh esp-idf 25.04
```

## Supported Ubuntu versions

| Version | Use case |
|---|---|
| 18.04 | Legacy projects requiring older toolchains |
| 22.04 | Recommended — best balance of stability and tool versions |
| 25.04 | Latest — newest compilers and libraries |

## Included tools

- **Base profile**: generic embedded Linux host tools for Buildroot, Yocto, OpenWrt, and related projects
- **Python tooling**: `uv` is preinstalled in Ubuntu `22.04` and `25.04` images
- **Zephyr profile**: base image plus Zephyr host dependencies such as `cmake`, `ninja`, `gperf`, `ccache`, `west`, Python venv support, SDL2, and `libmagic`
- **ESP-IDF profile**: base image plus Espressif host dependencies such as `cmake`, `ninja`, `gperf`, `ccache`, `dfu-util`, `libffi-dev`, `libssl-dev`, `libusb-1.0-0`, and Python venv support
- **Networking**: libnl, socat, iproute2, iputils
- **Editors**: vim, neovim, nano
- **Terminal**: tmux, screen, xterm

## Zephyr usage

Launch a Zephyr image against a Zephyr-specific workspace:

```bash
WORKSPACE_DIR=$HOME/work/zephyr ./launch.sh zephyr 22.04
```

The Zephyr image includes the common Linux host dependencies needed to initialize and build a Zephyr workspace. After launching a container:

```bash
python3 -m venv .venv
source .venv/bin/activate
west init zephyrproject
cd zephyrproject
west update
west zephyr-export
pip install -r zephyr/scripts/requirements.txt
```

For board builds, install the Zephyr SDK separately inside the container or mount an existing SDK and set `ZEPHYR_SDK_INSTALL_DIR`.

## ESP-IDF usage

Launch an ESP-IDF image against an ESP-IDF workspace:

```bash
WORKSPACE_DIR=$HOME/work/esp ./launch.sh esp-idf 25.04
```

The ESP-IDF image includes the current Linux host prerequisites documented by Espressif. After launching a container:

```bash
python3 -m venv .venv
source .venv/bin/activate
git clone --recursive https://github.com/espressif/esp-idf.git
cd esp-idf
./install.sh esp32
. ./export.sh
```

If you already have an `esp-idf` checkout in your mounted workspace, run `./install.sh` and `. ./export.sh` there instead.

## Structure

```
.
├── launch.sh
├── docker/
│   ├── base/
│   │   ├── Dockerfile.ubuntu-18.04
│   │   ├── Dockerfile.ubuntu-22.04
│   │   └── Dockerfile.ubuntu-25.04
│   └── profiles/
│       ├── zephyr/
│       │   ├── Dockerfile.ubuntu-22.04
│       │   └── Dockerfile.ubuntu-25.04
│       └── esp-idf/
│           ├── Dockerfile.ubuntu-22.04
│           └── Dockerfile.ubuntu-25.04
```

## Inside the container

- Workspace mounted at `/workspace`
- `/opt` mounted from host
- Non-root user `builder` matching your host UID/GID
