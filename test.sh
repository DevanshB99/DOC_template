#!/usr/bin/env bash
# Container test suite.
# From the host (container must be running): ./test.sh
# From inside the container:                bash test.sh

# Self-execute inside the container when called from the host
if [ ! -f /opt/ros/humble/setup.bash ]; then
    SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
    [ -f "$SCRIPT_DIR/.env" ] && source "$SCRIPT_DIR/.env"
    CONTAINER_NAME="${CONTAINER_NAME:-doc_template}"
    COMPOSE_PROJECT=$(echo "${CONTAINER_NAME}" | tr '-' '_')
    RUNNING=$(docker ps --format '{{.Names}}' | \
        grep -E "^(${CONTAINER_NAME}|${COMPOSE_PROJECT})" | head -1)
    if [ -z "$RUNNING" ]; then
        echo "No running container found. Start one first: ./launch_container.sh"
        exit 1
    fi
    echo "Running tests inside '$RUNNING'..."
    # Source the entrypoint so ROS2, PATH, and env vars are set before the test runs
    docker exec -i "$RUNNING" bash -c 'source /entrypoint.sh 2>/dev/null; bash' < "$0"
    exit $?
fi

# Helpers
PASS=0; FAIL=0; WARN=0
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

section()  { echo -e "\n${BOLD}${CYAN}── $1 ──────────────────────────────────────────────${NC}"; }
pass()     { echo -e "  ${GREEN}✓${NC}  $1"; PASS=$((PASS+1)); }
fail()     { echo -e "  ${RED}✗${NC}  $1"; FAIL=$((FAIL+1)); }
warn()     { echo -e "  ${YELLOW}⚠${NC}  $1"; WARN=$((WARN+1)); }

check_cmd()  { command -v "$1" &>/dev/null && pass "$1 available" || fail "$1 not found"; }
check_file() { [ -f "$1" ] && pass "$1 exists" || fail "$1 missing"; }
check_dir()  { [ -d "$1" ] && pass "$1 exists" || fail "$1 missing"; }
check_rw()   { [ -w "$1" ] && pass "$1 writable" || fail "$1 not writable"; }
check_env()  {
    local val="${!1:-}"
    [ -n "$val" ] && pass "$1=$val" || fail "$1 not set"
}
# check_group <name> <gid>
# Checks by name first; falls back to GID (macOS Docker Desktop resolves group names
# from the host NSS, so container group names may differ from their GIDs).
check_group() {
    local name="$1" gid="${2:-}"
    if id -Gn 2>/dev/null | tr ' ' '\n' | grep -qw "$name"; then
        pass "group: $name"
    elif [ -n "$gid" ] && id -G 2>/dev/null | tr ' ' '\n' | grep -qw "$gid"; then
        pass "group: $name (GID $gid present — name resolved differently on this host)"
    else
        fail "group: $name (GID $gid) missing from process groups"
    fi
}
check_import() {
    python3 -c "import $1" 2>/dev/null && \
        pass "python: $1" || fail "python: $1 (import failed)"
}
check_import_opt() {
    if python3 -c "import $1" 2>/dev/null; then
        VER=$(python3 -c "import $1; print(getattr($1,'__version__','?'))" 2>/dev/null || echo "?")
        pass "python: $1 $VER (optional)"
    else
        warn "python: $1 not installed — add to requirements.txt if needed"
    fi
}

section "Container Identity"
[ "${ROS_DISTRO:-}" = "humble" ] && pass "ROS_DISTRO=humble" || fail "ROS_DISTRO='${ROS_DISTRO:-unset}' expected humble"
check_env PLATFORM_TYPE
check_env RMW_IMPLEMENTATION
[ "${RMW_IMPLEMENTATION:-}" = "rmw_fastrtps_cpp" ] && \
    pass "RMW=rmw_fastrtps_cpp" || \
    warn "RMW=${RMW_IMPLEMENTATION:-unset} — expected rmw_fastrtps_cpp for micro-ROS"
check_env ROS_DOMAIN_ID
check_env ROS_LOCALHOST_ONLY
echo "  user: $(id)"

section "Hardware Groups"
check_group video   44
check_group dialout 20
check_group audio   29
check_group input   105
check_group plugdev 46
if [ "${PLATFORM_TYPE:-}" = "jetson" ]; then
    check_group i2c  121
    check_group gpio 999
fi

section "ROS2 Core"
check_file /opt/ros/humble/setup.bash
check_cmd  ros2
check_cmd  colcon
check_cmd  rosdep

PKG_COUNT=$(ros2 pkg list 2>/dev/null | wc -l | tr -d ' ')
[ "${PKG_COUNT:-0}" -gt 0 ] && pass "ros2 pkg list — $PKG_COUNT packages" || fail "ros2 pkg list failed"

# topic list needs a running daemon — warn only
ros2 topic list &>/dev/null 2>&1 && pass "ros2 topic list OK" || \
    warn "ros2 topic list failed — no daemon running (acceptable on fresh start)"

check_cmd rviz2
check_cmd rqt

section "DDS / FastDDS"
check_env  FASTRTPS_DEFAULT_PROFILES_FILE
[ -n "${FASTRTPS_DEFAULT_PROFILES_FILE:-}" ] && check_file "$FASTRTPS_DEFAULT_PROFILES_FILE"
check_file /config/cyclonedds.xml
ros2 pkg list 2>/dev/null | grep -q "rmw_cyclonedds" && \
    pass "rmw_cyclonedds package present" || warn "rmw_cyclonedds not found"

section "micro-ROS"
check_file /workspaces/base_ws/install/setup.bash
ros2 pkg list 2>/dev/null | grep -q "micro_ros_agent" && \
    pass "micro_ros_agent package found" || fail "micro_ros_agent not found"
AGENT_BIN=$(find /workspaces/base_ws -name "micro_ros_agent" -type f 2>/dev/null | head -1)
[ -n "$AGENT_BIN" ] && pass "micro_ros_agent binary: $AGENT_BIN" || fail "micro_ros_agent binary not found"

section "Python — Required Packages"
check_import serial
check_import numpy
check_import scipy
check_import matplotlib
check_import PIL
check_import sounddevice
check_import fastapi
check_import pydantic
check_import yaml
check_import requests
check_import tqdm

section "Python — Optional Packages"
check_import_opt torch
check_import_opt onnxruntime
check_import_opt cv2
check_import_opt PySide6

section "Compute Backend"
if python3 -c "import torch" 2>/dev/null; then
    TORCH_INFO=$(python3 - 2>/dev/null <<'PY'
import torch
cuda = torch.cuda.is_available()
dev = torch.cuda.get_device_name(0) if cuda else "CPU"
print(f"torch {torch.__version__} | {'CUDA: ' + dev if cuda else dev}")
PY
)
    pass "$TORCH_INFO"
    if [ "${PLATFORM_TYPE:-}" = "gpu" ] || [ "${PLATFORM_TYPE:-}" = "jetson" ]; then
        python3 -c "import torch; assert torch.cuda.is_available()" 2>/dev/null && \
            pass "CUDA available on ${PLATFORM_TYPE}" || fail "CUDA not available on ${PLATFORM_TYPE}"
    fi
else
    warn "torch not installed — skipping compute check"
fi

section "Display / GUI"
[ -n "${DISPLAY:-}" ] && pass "DISPLAY=${DISPLAY}" || warn "DISPLAY not set — GUI tools will not open windows"
[ "${QT_QPA_PLATFORM:-}" = "xcb" ] && pass "QT_QPA_PLATFORM=xcb" || warn "QT_QPA_PLATFORM=${QT_QPA_PLATFORM:-unset}"
ldconfig -p 2>/dev/null | grep -q "libxcb.so" && pass "libxcb.so present" || warn "libxcb.so not found"

if [ -n "${DISPLAY:-}" ]; then
    # Probe the X11 display: TCP for macOS bridge (host.docker.internal:N), Unix socket for Linux
    X11_OK=$(python3 - <<'PY'
import os, socket, sys
d = os.environ.get("DISPLAY", "")
try:
    if d.startswith("host.docker.internal:") or d.startswith("localhost:"):
        # TCP display — port = 6000 + display number
        num = int(d.split(":")[1].split(".")[0])
        host = d.split(":")[0]
        s = socket.create_connection((host, 6000 + num), timeout=2)
        s.close()
    else:
        # Unix socket display
        num = d.lstrip(":").split(".")[0]
        path = f"/tmp/.X11-unix/X{num}"
        s = socket.socket(socket.AF_UNIX)
        s.settimeout(2)
        s.connect(path)
        s.close()
    print("ok")
except Exception as e:
    print(f"fail:{e}")
PY
)
    echo "$X11_OK" | grep -q "^ok" && pass "X11 display reachable (${DISPLAY})" || \
        warn "X11 not reachable — rqt/rviz2 windows will not open (${X11_OK#fail:})"
fi

section "Audio"
check_file /etc/asound.conf
ldconfig -p 2>/dev/null | grep -q "libportaudio" && \
    pass "libportaudio present" || fail "libportaudio not found"

SD_RESULT=$(python3 - 2>/dev/null <<'PY'
import sounddevice as sd
try:
    devs = sd.query_devices()
    n = len(devs) if hasattr(devs, '__len__') else 0
    print(f"sounddevice: {n} device(s) visible")
except Exception as e:
    print(f"sounddevice: {e}")
PY
)
echo "  $SD_RESULT"

section "Workspace & Mounts"
check_dir /workspaces/shared_ws/src
check_rw  /workspaces/shared_ws/src
check_dir /data;   check_rw /data
check_dir /models; check_rw /models
check_dir /config
check_dir /workspaces/agents

check_file /workspaces/base_ws/install/setup.bash
[ -f /workspaces/gscam2_ws/install/setup.bash ] && \
    pass "gscam2_ws sourced" || \
    { [ "${PLATFORM_TYPE:-}" = "jetson" ] && fail "gscam2_ws missing on Jetson" || true; }

section "Device Access"
[ -d /dev ] && pass "/dev accessible" || fail "/dev missing"

VIDEO_COUNT=$(ls /dev/video* 2>/dev/null | wc -l | tr -d ' ')
[ "${VIDEO_COUNT:-0}" -gt 0 ] && pass "$VIDEO_COUNT camera device(s): $(ls /dev/video* 2>/dev/null | tr '\n' ' ')" || \
    warn "No /dev/video* — plug in a camera to verify"

SERIAL_COUNT=$(ls /dev/ttyUSB* /dev/ttyACM* 2>/dev/null | wc -l | tr -d ' ')
[ "${SERIAL_COUNT:-0}" -gt 0 ] && pass "$SERIAL_COUNT serial device(s): $(ls /dev/ttyUSB* /dev/ttyACM* 2>/dev/null | tr '\n' ' ')" || \
    warn "No /dev/ttyUSB* or /dev/ttyACM* — plug in a microcontroller to verify"

SND_COUNT=$(ls /dev/snd/* 2>/dev/null | wc -l | tr -d ' ')
[ "${SND_COUNT:-0}" -gt 0 ] && pass "$SND_COUNT ALSA device(s) found" || warn "No /dev/snd/* devices"

section "Platform-Specific (${PLATFORM_TYPE:-unknown})"
case "${PLATFORM_TYPE:-desktop}" in
    jetson)
        check_cmd nvidia-smi
        nvidia-smi &>/dev/null && pass "nvidia-smi OK" || fail "nvidia-smi failed"
        check_import_opt "Jetson.GPIO"
        ;;
    gpu)
        check_cmd nvidia-smi
        nvidia-smi &>/dev/null && pass "nvidia-smi OK" || fail "nvidia-smi failed"
        if python3 -c "import onnxruntime" 2>/dev/null; then
            PROVIDERS=$(python3 -c "import onnxruntime as ort; print(' '.join(ort.get_available_providers()))" 2>/dev/null)
            echo "$PROVIDERS" | grep -q "CUDAExecutionProvider" && \
                pass "onnxruntime CUDAExecutionProvider available" || \
                warn "CUDAExecutionProvider not in: $PROVIDERS"
        fi
        ;;
    desktop)
        [ "${LIBGL_ALWAYS_SOFTWARE:-}" = "1" ] && pass "LIBGL_ALWAYS_SOFTWARE=1" || warn "LIBGL_ALWAYS_SOFTWARE not set (may cause GL errors in headless mode)"
        check_cmd v4l2-ctl
        ;;
esac

section "Ollama (optional)"
[ -n "${OLLAMA_HOST:-}" ] && pass "OLLAMA_HOST=${OLLAMA_HOST}" || warn "OLLAMA_HOST not set"
if [ -n "${OLLAMA_HOST:-}" ]; then
    if curl -sf --max-time 3 "${OLLAMA_HOST}/api/tags" &>/dev/null; then
        MODEL_INFO=$(curl -sf "${OLLAMA_HOST}/api/tags" | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    names = [m['name'] for m in d.get('models', [])]
    print(f\"{len(names)} model(s): {', '.join(names[:3])}{'...' if len(names) > 3 else ''}\" if names else '0 models pulled yet')
except:
    print('connected')
" 2>/dev/null || echo "connected")
        pass "Ollama reachable — $MODEL_INFO"
    else
        warn "Ollama not reachable at ${OLLAMA_HOST} — start it or adjust OLLAMA_HOST in .env"
    fi
fi

# Summary
TOTAL=$((PASS+FAIL+WARN))
echo ""
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e " Results  ${GREEN}${PASS} passed${NC}  ${RED}${FAIL} failed${NC}  ${YELLOW}${WARN} warnings${NC}  (${TOTAL} total)"
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

if [ "$FAIL" -gt 0 ]; then
    echo -e "${RED}${FAIL} check(s) FAILED — see ✗ lines above.${NC}"
    exit 1
else
    echo -e "${GREEN}All required checks passed.${NC}"
    [ "$WARN" -gt 0 ] && \
        echo -e "${YELLOW}${WARN} warning(s) — see ⚠ lines above (hardware-dependent or optional).${NC}"
    exit 0
fi
