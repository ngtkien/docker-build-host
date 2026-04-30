# Embedded Linux Build Environment

Docker-based build environment for embedded Linux projects. The workspace is organized around a reusable Ubuntu base image plus an `embedded` overlay for RTOS/SDK development (e.g., Zephyr, ESP-IDF).

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
./launch.sh embedded 22.04
./launch.sh -w /opt -w /data 22.04
```

The old form `./launch.sh 22.04` still launches the generic `base` profile. Use `./launch.sh embedded 22.04` for the embedded overlay.

`embedded` requires Ubuntu `22.04` or newer. `18.04` remains available only for the generic `base` profile.

### Extra mounts

In interactive mode you will be asked whether to mount extra host paths. In non-interactive mode use `-w` (repeatable):

```bash
./launch.sh -w /opt -w /data 22.04
./launch.sh -w /opt/homebrew embedded 22.04
```

### Environment variables

| Variable | Values | Default | Description |
|---|---|---|---|
| `PROXY_MODE` | `auto`, `on`, `off` | `off` | Proxy handling for build and run |
| `BUILD_NETWORK` | `host`, `default` | `host` | Docker network mode during build |
| `UBUNTU_MIRROR` | apt mirror URL | unset | Override Ubuntu apt mirror for faster first-time package downloads |
| `AUTO_UBUNTU_MIRROR` | `on`, `off` | `on` | Auto-select a faster mirror when `UBUNTU_MIRROR` is unset |
| `WORKSPACE_DIR` | host path | parent of this repo | Host directory mounted into `/workspace` |
| `PROFILE` | `base`, `embedded` | `base` | Default launch profile when not passed as an argument |

```bash
PROXY_MODE=on ./launch.sh 22.04
UBUNTU_MIRROR=http://mirrors.edge.kernel.org/ubuntu ./launch.sh 22.04
AUTO_UBUNTU_MIRROR=off ./launch.sh 22.04
WORKSPACE_DIR=$HOME/work/embedded ./launch.sh embedded 22.04
./launch.sh -w /opt -w /data 22.04
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
- **Embedded profile**: base image plus RTOS/SDK host dependencies such as `cmake`, `ninja`, `gperf`, `ccache`, `west`, Python venv support, SDL2, and `libmagic`
- **Networking**: libnl, socat, iproute2, iputils
- **Editors**: vim, neovim, nano
- **Terminal**: tmux, screen, xterm

## Embedded profile usage

Launch the embedded profile against an RTOS/SDK workspace:

```bash
WORKSPACE_DIR=$HOME/work/embedded ./launch.sh embedded 22.04
```

The embedded image includes common Linux host dependencies for Zephyr, ESP-IDF, and similar RTOS projects. After launching a container you can set up your SDK of choice:

### Zephyr

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

### ESP-IDF

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
│   └── embedded/
│       ├── Dockerfile.ubuntu-22.04
│       └── Dockerfile.ubuntu-25.04
```

## Inside the container

- Workspace mounted at `/workspace`
- Extra host paths mounted with `-w <path>` (same path inside container)
- Non-root user `builder` matching your host UID/GID
