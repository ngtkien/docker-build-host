# Embedded Linux Build Environment

Docker-based build environment for embedded Linux projects — **Buildroot**, **Yocto**, **OpenWrt**, and more. Pre-configured with all common toolchain dependencies across Ubuntu 18.04, 22.04, and 25.04 base images.

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
```

### Environment variables

| Variable | Values | Default | Description |
|---|---|---|---|
| `PROXY_MODE` | `auto`, `on`, `off` | `auto` | Proxy handling for build and run |
| `BUILD_NETWORK` | `host`, `default` | `host` | Docker network mode during build |

```bash
PROXY_MODE=on ./launch.sh 22.04
```

## Supported Ubuntu versions

| Version | Use case |
|---|---|
| 18.04 | Legacy projects requiring older toolchains |
| 22.04 | Recommended — best balance of stability and tool versions |
| 25.04 | Latest — newest compilers and libraries |

## Included tools

- **Core**: gcc, g++, make, binutils, cpio, rsync, wget, curl, git
- **Build systems**: autoconf, automake, bison, flex, cmake-ready, texinfo
- **Python**: python3, pip3, jsonschema, Mako, PyYAML, pyelftools, yamllint
- **Embedded**: device-tree-compiler, u-boot-tools, qemu-user-static, dfu-util
- **Networking**: libnl, socat, iproute2, iputils
- **Editors**: vim, neovim, nano
- **Terminal**: tmux, screen, xterm

## Structure

```
.
├── launch.sh                 # Launcher script (gum UI)
├── Dockerfile.ubuntu-18.04   # Ubuntu 18.04 build environment
├── Dockerfile.ubuntu-22.04   # Ubuntu 22.04 build environment (recommended)
└── Dockerfile.ubuntu-25.04   # Ubuntu 25.04 build environment
```

## Inside the container

- Workspace mounted at `/workspace`
- `/opt` mounted from host
- Non-root user `builder` matching your host UID/GID
