![Docker](https://img.shields.io/badge/Docker-Compose-2496ED?logo=docker&logoColor=white)
![Platform](https://img.shields.io/badge/Platform-Linux%20|%20macOS%20|%20Jetson%20|%20RPi%20|%20Windows-orange)
![Architecture](https://img.shields.io/badge/Arch-amd64%20|%20arm64-lightgrey)
![ROS2](https://img.shields.io/badge/ROS2-Humble-blue)
![micro-ROS](https://img.shields.io/badge/micro--ROS-Humble-blue)
![DDS](https://img.shields.io/badge/DDS-FastDDS-blueviolet)
![License](https://img.shields.io/badge/License-Open%20Source-brightgreen)
![GitHub Stars](https://img.shields.io/github/stars/DevanshB99/DOC_template)

# Multi-Architecture Docker for Edge AI, Robotics & Cross-Platform Development

A production-ready, architecture-agnostic Docker template for building robotics and Edge AI applications with **ROS2 Humble** and **micro-ROS Humble** as the middleware layer. Clone it, rename the folder to your project name, run `./install.sh`, and you have a fully working development environment — no manual Docker setup, no "works on my machine" problems.

The template ships with a **pre-built micro-ROS agent**, eliminating one of the most tedious and error-prone steps in ROS2 + microcontroller development. Setting up micro-ROS from scratch involves cloning the right branches, resolving platform-specific build failures, and getting the agent compiled — this template handles all of that automatically during `./install.sh`, so you can go straight to writing firmware and ROS2 nodes.

**Arduino CLI firmware flashing is built in.** If any ROS2 package in your `src/` directory contains a `firmware/` folder with a `sketch.yaml` and a `firmware.yaml`, `./install.sh` automatically installs the correct Arduino core and libraries, compiles the sketch, and flashes it to the connected microcontroller — just plug in the board before running install. The active `ROS_DOMAIN_ID` from your `.env` is injected directly into the firmware at compile time, so micro-ROS on the device and your ROS2 stack are on the same domain with zero manual configuration.

---

## Who Is This For?

- **Robotics teams** building with ROS2 who need a reproducible environment across different hardware (Jetson, Raspberry Pi, x86 desktops)
- **Full-stack developers** who want ROS2 for robot communication alongside a Python API backend (FastAPI) and optional web frontend
- **Embedded / micro-ROS developers** who want to skip the painful micro-ROS agent setup and jump straight to firmware development on microcontrollers (ESP32, Arduino, etc.)
- **Research labs and student teams** where members use different machines but need identical development environments
- **Solo developers** who work across a laptop (macOS / Windows) and deploy to embedded hardware (Jetson, RPi)

---

## Supported Platforms

| Platform | Architecture | Base Image | Auto-detected |
|---|---|---|---|
| Linux (x86_64) | `amd64` | `osrf/ros:humble-desktop-full` | Yes |
| Linux + NVIDIA GPU | `amd64` | `osrf/ros:humble-desktop-full` | Yes (`nvidia-smi`) |
| NVIDIA Jetson (Orin / AGX) | `arm64` | Isaac ROS Humble | Yes (`/proc/device-tree`) |
| macOS Apple Silicon (M1–M4) | `arm64` | `osrf/ros:humble-desktop` | Yes (`uname`) |
| Raspberry Pi 4/5 | `arm64` | `arm64v8/ros:humble-perception` | Yes (`/proc/device-tree`) |
| Windows 10/11 (WSL2) | `amd64` | `osrf/ros:humble-desktop-full` | Yes (`/proc/version`) |

Override auto-detection: `./install.sh --platform=jetson`

---

## Prerequisites

### All platforms
- **Docker** with **Compose v2** (`docker compose version` — must show v2.x, not `docker-compose`)
- **Git**

### macOS
- **Docker Desktop** — allocate at least **6 GB RAM** in Settings → Resources (micro-ROS build is memory-intensive)
- **XQuartz** — required for GUI tools (rqt, rviz2): `brew install --cask xquartz`, then **log out and back in once** before running `./launch_container.sh`
- **socat** — required for XQuartz TCP relay: `brew install socat`
- System bash (3.2) is sufficient — `install.sh` does not require bash 4+

### Linux / Linux-GPU
- Docker post-install steps so Docker runs without `sudo`: [docs.docker.com/engine/install/linux-postinstall](https://docs.docker.com/engine/install/linux-postinstall/)
- **linux-gpu only**: NVIDIA Container Toolkit — `nvidia-smi` must work from the host shell (used for auto-detection)
- **linux-gpu only**: `nvidia-container-toolkit` set as the Docker default runtime

### Jetson (Orin / AGX)
- **JetPack 6.x** (tested on JetPack 6.1 / L4T r36.4)
- Docker and NVIDIA Container Runtime are included with JetPack — verify with `docker info`

### Raspberry Pi
- **64-bit OS** (Raspberry Pi OS Lite 64-bit or Ubuntu 22.04 arm64) — the arm64 base image will not run on a 32-bit OS
- Docker CE: `curl -fsSL https://get.docker.com | sh`, then add yourself to the docker group

### Windows (WSL2)
- **Windows 10 (21H2+) or Windows 11** with WSL2 enabled
- **WSL2 Ubuntu distro** — install via: `wsl --install -d Ubuntu`
- **Docker Desktop for Windows** with WSL2 backend enabled — allocate at least **6 GB RAM**
- Run everything from inside the **WSL2 terminal**, not PowerShell or Git Bash
- Clone the repository **inside WSL2 filesystem** (e.g. `~/`) — not on a Windows NTFS path (`/mnt/c/...`)
- **Windows 11**: GUI tools (rqt, rviz2) work automatically via **WSLg** — no extra setup

---

## Quick Start

**Step 1 — Create your own repo from this template**

Click **"Use this template" → "Create a new repository"** on the GitHub page.

**Step 2 — Clone your new repo and set up**

```bash
# Clone your new repo (replace with your repo URL)
git clone https://github.com/YOUR_USERNAME/your_repo_name my_robot
cd my_robot

# Install — detects your platform automatically
./install.sh

# Launch
./launch_container.sh

# Open additional shells without rebuilding
./connect.sh
```

### How the naming works

The **folder name** drives everything automatically:
- Rename the folder to `my_robot` → the container becomes `my-robot`, the systemd service becomes `my-robot`, the desktop shortcut directory becomes `my_robot`
- Nothing is hardcoded. `install.sh` derives the container name from the folder name at install time and writes it to `.env`

---

## Setup Checklist

Review and configure these files before running `./install.sh`:

**`src/src.repos`** — add your ROS2 package repositories
```yaml
repositories:
    my_package:
        type: git
        url: https://github.com/your-org/my_package.git
        version: main
```

**`docker/requirements.txt`** — uncomment or add Python dependencies you need

**`docker/overlay_packages.txt`** — add ROS2 apt packages your project needs

**`docker/overlay_packages_jetson.txt`** — add Jetson-only Isaac ROS packages (uncomment what you need)

**`docker/bringup_entrypoint.sh`** — set your production bringup launch command

**`.env`** — generated from `.env.example` on first run; set `ROS_DOMAIN_ID` if you need network isolation

**`docker-compose.yaml` → `mac` / `windows` service** — expose additional ports your app needs (default: 8000, 8888)

---

## What `./install.sh` Does

1. Detects your platform (or uses `--platform=` override)
2. Writes `.env` with container name and platform
3. Installs host tools: `vcstool`, `git-lfs`, Arduino CLI
4. Imports ROS2 repos from `src/src.repos` into `src/`
5. Imports data/model repos from `data/data.repos` and `models/models.repos`
6. Scans `src/` for firmware sketches — compiles and flashes any found
7. Builds the Docker image
8. **Linux / Jetson / RPi only**: sets socket buffer limits, enables loopback multicast, creates a systemd auto-start service and desktop shortcuts

Re-running `./install.sh` is safe — Docker uses layer caching, vcstool updates existing repos.

> **After `./install.sh` rebuilds the image**, always stop the old container before relaunching:
> ```bash
> docker rm -f <container_name>
> ./launch_container.sh
> ```
> `./launch_container.sh` attaches to an existing running container if one is found. It warns if the running container's image doesn't match the current build.

---

## Project Structure

```
my_project/
├── install.sh                  # One-shot setup
├── launch_container.sh         # Start or attach to the container
├── connect.sh                  # Attach an extra shell (no rebuild)
├── test.sh                     # Verify the container is working
├── docker-compose.yaml
├── .env / .env.example
│
├── docker/
│   ├── Dockerfile
│   ├── entrypoint.sh           # Sources ROS2 workspaces, sets DDS/Qt env
│   ├── bringup_entrypoint.sh   # TODO: set your production launch command
│   ├── packages.txt            # System apt packages
│   ├── overlay_packages.txt    # ROS2 apt packages
│   ├── overlay_packages_jetson.txt  # Isaac ROS packages (Jetson only)
│   └── requirements.txt        # Python pip packages
│
├── src/                        # Your ROS2 packages (cloned by vcs)
│   └── src.repos               # TODO: add your package repos here
│
├── data/                       # Datasets (git-lfs)
│   └── data.repos
│
├── models/                     # Model weights (git-lfs)
│   └── models.repos
│
├── agents/                     # Ollama-backed agent modules
│   └── __init__.py
│
├── config/
│   ├── fastdds.xml             # FastDDS profile (default, micro-ROS compatible)
│   └── cyclonedds.xml          # CycloneDDS profile (switch via RMW_IMPLEMENTATION)
│
├── arduino/                    # Arduino CLI (installed by install.sh)
│   └── arduino-cli.yaml
│
└── docs/                       # Documents 
```

---

## Team Collaboration
### The Core Idea - 
Everyone on the team clones the same repo. Each person runs `./install.sh` on their own machine. The script detects their platform and builds the correct image. The **source workspace** (`src/`) and **data directory** (`data/`) are identical across all machines because they're defined by `.repos` manifest files checked into git.

```
Developer A (macOS M2 laptop)     Developer B (Linux + GPU desktop)     Jetson Orin Nano (deployment)
         │                                  │                                    │
         └──── same git repo ───────────────┴────────────────────────────────────┘
                     │
              ./install.sh
              (auto-detects platform, builds correct image)
                     │
              ./launch_container.sh
              (identical ROS2 environment inside)
```

- **Same ROS2 packages** — defined in `src/src.repos`, everyone clones the same versions
- **Same Python stack** — defined in `docker/requirements.txt`
- **Same DDS config** — `config/fastdds.xml` ensures consistent FastDDS behaviour across machines
- **Same ROS_DOMAIN_ID** — set in `.env`, isolates your team's ROS2 traffic on shared networks
- **Platform differences handled transparently** — NVIDIA PyTorch wheel on Jetson, CPU wheel on desktop; GPU passthrough enabled only where available; gscam2 built from source on Jetson only

### Adding a new ROS2 package

1. Add the repo to `src/src.repos`
2. Run `vcs import src < src/src.repos` to clone it
3. Build inside the container: `./launch_container.sh colcon build --symlink-install`
4. Commit `src.repos` — teammates repeat steps 2–3

### Adding a Python dependency

1. Add it to `docker/requirements.txt`
2. Rebuild the image: `./install.sh`
3. Commit `requirements.txt` — teammates rebuild

---

## Daily Workflow

```bash
# Launch (builds workspace on first start)
./launch_container.sh

# Open a second terminal into the same container
./connect.sh

# Run the test suite to verify everything works
./test.sh

# Build your ROS2 workspace inside the container
colcon build --symlink-install

# Rebuild the Docker image after changing Dockerfile / packages
docker rm -f <container_name>
./install.sh
```

---

## Firmware Auto-Flash

`./install.sh` scans `src/` for any Arduino sketch that has both a `sketch.yaml` and a `firmware.yaml` alongside it. When found, it installs the required Arduino core and libraries, compiles the sketch, and flashes it to the connected board — all on the host, before the Docker image starts.

### Folder structure

Place the firmware inside your ROS2 package. The sketch folder name **must match** the `.ino` filename.

```
src/
└── my_robot_drivers/
    ├── package.xml
    ├── setup.py
    ├── my_robot_drivers/
    │   └── __init__.py
    └── firmware/
        └── my_robot_firmware/           ← folder name = .ino filename
            ├── my_robot_firmware.ino    ← Arduino sketch
            ├── sketch.yaml              ← Arduino IDE 2 board/library profile
            ├── firmware.yaml            ← flash config (read by install.sh)
            └── domain_id.h              ← AUTO-GENERATED by install.sh (do not edit)
```

### `sketch.yaml` — Arduino IDE 2 profile

Defines the board (FQBN), the Arduino platform to install, and any standard library dependencies.

**ESP32 example:**
```yaml
default_profile: esp32_ros
profiles:
  esp32_ros:
    fqbn: esp32:esp32:esp32
    platforms:
      - platform: esp32:esp32 (3.0.7)
        platform_index_url: https://espressif.github.io/arduino-esp32/package_esp32_index.json
```

**Raspberry Pi Pico (RP2040) example:**
```yaml
default_profile: pico_ros
profiles:
  pico_ros:
    fqbn: rp2040:rp2040:rpipico
    platforms:
      - platform: rp2040:rp2040 (4.4.0)
        platform_index_url: https://github.com/earlephilhower/arduino-pico/releases/download/global/package_rp2040_index.json
```

### `firmware.yaml` — flash configuration

Defines how to flash the board and which git-hosted libraries to install (e.g. `micro_ros_arduino`, which is not on the standard Arduino registry).

**Serial flash (ESP32, Arduino Nano, etc.):**
```yaml
flash_method: serial
serial_glob: /dev/ttyACM*       # adjust to /dev/ttyUSB* if needed
extra_libraries:
  - git_url: https://github.com/micro-ROS/micro_ros_arduino.git
    version: humble
```

**UF2 flash (Raspberry Pi Pico, RP2040):**
```yaml
flash_method: uf2
bootloader_label: RPI-RP2       # drive label when the board is in bootloader mode
serial_glob: /dev/ttyACM*       # used to trigger 1200-baud reset into bootloader
extra_libraries:
  - git_url: https://github.com/micro-ROS/micro_ros_arduino.git
    version: humble
```

### Using `domain_id.h` in your sketch

`install.sh` generates `domain_id.h` automatically from the `ROS_DOMAIN_ID` in your `.env`. Include it in your sketch so the board uses the same domain as your ROS2 stack:

```cpp
#include <micro_ros_arduino.h>
#include "domain_id.h"  // provides: #define MICROROS_DOMAIN_ID <value>

void setup() {
    set_microros_transports();
    // pass MICROROS_DOMAIN_ID to your micro-ROS init if required
}
```

> Connect the microcontroller to the host **before** running `./install.sh`. On macOS, flashing runs on the host directly. On Linux/WSL2, the device must be accessible at the path matching `serial_glob` (WSL2 users need `usbipd-win`).

---

## Ollama (LLM Sidecar)

Ollama sidecars start automatically with each profile (except macOS — see below).

| Platform | Ollama behaviour |
|---|---|
| `linux` / `rpi` / `windows` | CPU sidecar starts with the profile |
| `linux-gpu` | GPU sidecar starts with the profile |
| `jetson` | GPU sidecar starts (NVIDIA runtime) |
| `mac` | **Run Ollama natively**: `brew install ollama && brew services start ollama` |

To use a remote Ollama instance (e.g. a LAN GPU server), set in `.env`:
```
OLLAMA_HOST=http://192.168.1.x:11434
```

Add your agent modules to `agents/` — this directory is mounted at `/workspaces/agents` inside the container and is already on `PYTHONPATH`.

---

## DDS Middleware

**FastDDS** (`rmw_fastrtps_cpp`) is the default — required for reliable micro-ROS agent discovery (the agent uses embedded Fast-DDS internally).

To switch to CycloneDDS (e.g. if you are not using micro-ROS):
```bash
# in .env:
RMW_IMPLEMENTATION=rmw_cyclonedds_cpp
```

Both `config/fastdds.xml` and `config/cyclonedds.xml` are tuned for localhost-only operation (`ROS_LOCALHOST_ONLY=1`). For cross-machine ROS2, remove `ROS_LOCALHOST_ONLY` from `docker-compose.yaml` and update the DDS config to use your network interface.

---

## Platform Notes

**macOS**
- XQuartz and socat must be installed **before** running `./launch_container.sh`. Log out and back in after installing XQuartz.
- Built-in and USB cameras are **not accessible** inside Docker Desktop (VM limitation). Firmware flashing happens on the host via `./install.sh`.
- Audio routing uses a PulseAudio TCP proxy — set `PULSE_SERVER=tcp:host.docker.internal:4713` if you need audio

**Windows (WSL2)**
- Run all commands from the **WSL2 terminal** (not PowerShell or Git Bash)
- Clone the repo inside the WSL2 filesystem (`~/`), not on a Windows drive (`/mnt/c/...`) — file I/O on NTFS mounts is significantly slower
- `install.sh` detects WSL2 automatically. Systemd, sysctl tuning, and desktop shortcuts are skipped
- **GUI tools**: work automatically on Windows 11 via WSLg. On Windows 10, install VcXsrv and run `export DISPLAY=:0.0` in WSL2
- **USB serial devices**: require [`usbipd-win`](https://github.com/dorssel/usbipd-win) to attach devices to WSL2
- **NVIDIA GPU on Windows**: override with `./install.sh --platform=linux-gpu` and install the [NVIDIA CUDA on WSL2 driver](https://developer.nvidia.com/cuda/wsl)

**Jetson**
- Tested on Jetson Orin Nano (JetPack 6.1). Other Orin variants (AGX, NX) should work
- NGC login is required to pull the Isaac ROS base image (see Prerequisites)
- CSI cameras use `nvarguscamerasrc` (GStreamer) via the Argus socket mounted at `/tmp/argus_socket`. Configure `Jetson-io.py` for the compatible camera modules for them to be detected. 
- `ROS_LOCALHOST_ONLY=1` is set by default; remove it for cross-machine ROS2

**Linux / Linux-GPU**
- `network_mode: host` — ROS2 nodes are directly visible on the LAN
- GPU passthrough requires `nvidia-container-toolkit` configured as the Docker default runtime

**Raspberry Pi**
- Must use a 64-bit OS image
- If your host I2C group is not GID 997, set `RPI_I2C_GID` in `.env`: run `getent group i2c` on the host to find the correct GID

---

## Verifying Your Setup

```bash
./test.sh
```

Runs from the host (container must be running). Checks ROS2, DDS, micro-ROS, Python packages, hardware groups, device access, display, audio, compute backend, and Ollama connectivity. All required checks should pass; warnings are hardware-dependent and safe to ignore.

---

## License

This template is open source. Use it freely for your projects.
