#!/usr/bin/env bash

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

detect_platform() {
    if [ "$(uname)" = "Darwin" ]; then
        echo "mac"
    elif grep -qi "microsoft\|wsl" /proc/version 2>/dev/null; then
        echo "windows"
    elif [ -f /proc/device-tree/compatible ] && grep -q "nvidia" /proc/device-tree/compatible 2>/dev/null; then
        echo "jetson"
    elif [ -f /proc/device-tree/model ] && grep -q "Raspberry Pi" /proc/device-tree/model 2>/dev/null; then
        echo "rpi"
    elif command -v nvidia-smi &> /dev/null && nvidia-smi &> /dev/null; then
        echo "linux-gpu"
    else
        echo "linux"
    fi
}

PLATFORM_OVERRIDE=""
for arg in "$@"; do
    case $arg in
        --platform=*) PLATFORM_OVERRIDE="${arg#*=}" ;;
        --platform)   shift; PLATFORM_OVERRIDE="$1" ;;
    esac
done

if [ -n "$PLATFORM_OVERRIDE" ]; then
    case "$PLATFORM_OVERRIDE" in
        linux|linux-gpu|jetson|mac|rpi|windows) PLATFORM="$PLATFORM_OVERRIDE" ;;
        *) echo "Invalid platform '$PLATFORM_OVERRIDE'. Valid: linux, linux-gpu, jetson, mac, rpi, windows"; exit 1 ;;
    esac
else
    PLATFORM=$(detect_platform)
fi
_DETECTED_PLATFORM="$PLATFORM"

platform_display_name() {
    case "$1" in
        linux)     echo "Linux (x86_64)" ;;
        linux-gpu) echo "Linux with NVIDIA GPU (x86_64)" ;;
        jetson)    echo "Jetson (arm64)" ;;
        mac)       echo "macOS Apple Silicon (arm64)" ;;
        rpi)       echo "Raspberry Pi (arm64)" ;;
        windows)   echo "Windows / WSL2 (x86_64)" ;;
    esac
}

CONTAINER_NAME=$(basename "$SCRIPT_DIR" | tr '[:upper:]' '[:lower:]' | tr ' _' '-')
PROJECT_NAME=$(basename "$SCRIPT_DIR")

echo "========================================="
echo " $(platform_display_name "$PLATFORM") — $PROJECT_NAME"
echo "========================================="

cd "$SCRIPT_DIR" || exit 1

# .env
ENV_FILE="$SCRIPT_DIR/.env"
if [ ! -f "$ENV_FILE" ]; then
    [ -f "$SCRIPT_DIR/.env.example" ] && cp "$SCRIPT_DIR/.env.example" "$ENV_FILE" || touch "$ENV_FILE"
fi

set -a; source "$ENV_FILE"; set +a
PLATFORM="$_DETECTED_PLATFORM"
ROS_DOMAIN_ID="${ROS_DOMAIN_ID:-0}"

sed_inplace() {
    if [ "$(uname)" = "Darwin" ]; then sed -i '' "$@"; else sed -i "$@"; fi
}

update_env() {
    local key="$1" value="$2"
    if grep -q "^${key}=" "$ENV_FILE"; then
        sed_inplace "s/^${key}=.*/${key}=${value}/" "$ENV_FILE"
    else
        echo "${key}=${value}" >> "$ENV_FILE"
    fi
}

update_env "CONTAINER_NAME" "$CONTAINER_NAME"
update_env "PLATFORM" "$PLATFORM"
update_env "COMPOSE_PROFILES" "$PLATFORM"

# Host tool installation
if ! command -v vcs &> /dev/null; then
    echo "Installing vcstool..."
    if [ "$PLATFORM" = "mac" ]; then
        pip3 install vcstool 2>/dev/null || \
            pip3 install vcstool --break-system-packages 2>/dev/null || true
    else
        sudo apt install -y python3-vcstool 2>/dev/null || \
            pip3 install vcstool --break-system-packages 2>/dev/null || \
            pip3 install vcstool
    fi
    if ! command -v vcs &> /dev/null; then
        if [ "$PLATFORM" = "mac" ]; then
            pip3 install vcstool --break-system-packages 2>/dev/null || pip3 install vcstool
        else
            sudo apt install -y pipx && pipx install vcstool && pipx ensurepath
            export PATH="$PATH:$HOME/.local/bin"
        fi
    fi
fi

if ! python3 -c "import yaml" 2>/dev/null; then
    sudo apt-get install -y python3-yaml
fi

if ! python3 -c "import serial" 2>/dev/null; then
    sudo apt-get install -y python3-serial
fi

# Import ROS2 source repositories
SRC_DIR="$SCRIPT_DIR/src"
mkdir -p "$SRC_DIR"
cd "$SRC_DIR"
# TODO: Add your ROS2 package repositories to src/src.repos before running ./install.sh
vcs import < ./src.repos 2>/dev/null || vcs pull < ./src.repos || true

# git-lfs
if ! command -v git-lfs &> /dev/null; then
    echo "Installing git-lfs..."
    if [ "$PLATFORM" = "mac" ]; then
        brew install git-lfs
    else
        curl -s https://packagecloud.io/install/repositories/github/git-lfs/script.deb.sh | sudo bash
        sudo apt-get install -y git-lfs
    fi
    git lfs install
fi

# Import data repositories
DATA_DIR="$SCRIPT_DIR/data"
cd "$DATA_DIR"
vcs import < ./data.repos 2>/dev/null || vcs pull < ./data.repos || true
for dir in "$DATA_DIR"/*/; do
    if [ -d "$dir/.git" ]; then
        cd "$dir"
        git lfs install --local 2>/dev/null || true
        git lfs pull || true
        cd "$DATA_DIR"
    fi
done

# Import model repositories
MODELS_DIR="$SCRIPT_DIR/models"
cd "$MODELS_DIR"
# TODO: Add model weight repositories to models/models.repos
vcs import < ./models.repos 2>/dev/null || vcs pull < ./models.repos || true

# Arduino CLI
ARDUINO_DIR="$SCRIPT_DIR/arduino"
ARDUINO_CLI="$ARDUINO_DIR/bin/arduino-cli"
ARDUINO_CONFIG="$ARDUINO_DIR/arduino-cli.yaml"

if [ ! -x "$ARDUINO_CLI" ]; then
    echo "Installing Arduino CLI..."
    mkdir -p "$ARDUINO_DIR"
    cd "$ARDUINO_DIR"
    curl -fsSL https://raw.githubusercontent.com/arduino/arduino-cli/master/install.sh | sh
    cd "$SCRIPT_DIR"
fi

"$ARDUINO_CLI" --config-file "$ARDUINO_CONFIG" config set library.enable_unsafe_install true >/dev/null

yaml_get() {
    python3 - "$1" "$2" "${3-}" <<'PY'
import sys, yaml
path, key, default = sys.argv[1], sys.argv[2], sys.argv[3]
with open(path) as f:
    data = yaml.safe_load(f) or {}
val = data.get(key)
print(val if val is not None else default)
PY
}

yaml_extra_libs() {
    python3 - "$1" <<'PY'
import sys, yaml
with open(sys.argv[1]) as f:
    data = yaml.safe_load(f) or {}
for lib in data.get('extra_libraries') or []:
    url = lib.get('git_url', '')
    ver = lib.get('version', '')
    if url:
        print(f"{url}#{ver}" if ver else url)
PY
}

sketch_yaml_field() {
    python3 - "$1" "$2" <<'PY'
import sys, yaml, re
path, field = sys.argv[1], sys.argv[2]
with open(path) as f:
    data = yaml.safe_load(f) or {}
profiles = data.get('profiles') or {}
default = data.get('default_profile')
if default and default in profiles:
    profile = profiles[default]
elif profiles:
    profile = next(iter(profiles.values()))
else:
    profile = {}

def split_versioned(s):
    m = re.match(r'^(.+?)\s*\(([^)]*)\)\s*$', s)
    if m: return m.group(1).strip(), m.group(2).strip()
    return s.strip(), ''

if field == 'fqbn':
    print(profile.get('fqbn', ''))
elif field == 'platform':
    plats = profile.get('platforms') or []
    if plats:
        name, ver = split_versioned(plats[0].get('platform', ''))
        print(f"{name}@{ver}" if ver else name)
elif field == 'platform_url':
    plats = profile.get('platforms') or []
    if plats:
        print(plats[0].get('platform_index_url', ''))
elif field == 'libraries':
    for lib in profile.get('libraries') or []:
        name, ver = split_versioned(lib)
        print(f"{name}@{ver}" if ver else name)
PY
}

find_uf2_drive() {
    local label="$1"
    UF2_DRIVE=$(mount | grep -i "$label" | awk '{print $3}')
    if [ -n "$UF2_DRIVE" ]; then return 0; fi
    local dev
    dev=$(lsblk -o NAME,LABEL -rn 2>/dev/null | grep -i "$label" | awk '{print $1}')
    if [ -n "$dev" ]; then
        UF2_DRIVE="/mnt/${label,,}"
        sudo mkdir -p "$UF2_DRIVE"
        sudo mount "/dev/$dev" "$UF2_DRIVE"
        return 0
    fi
    UF2_DRIVE=""; return 1
}

flash_uf2() {
    local sketch_dir="$1" meta="$2"
    local sketch_name; sketch_name=$(basename "$sketch_dir")
    local label;       label=$(yaml_get "$meta" bootloader_label "RPI-RP2")
    local serial_glob; serial_glob=$(yaml_get "$meta" serial_glob "/dev/ttyACM*")

    if ! find_uf2_drive "$label"; then
        local port; port=$(ls $serial_glob 2>/dev/null | head -n 1)
        if [ -z "$port" ]; then
            echo "WARNING: $sketch_name: no $label drive and no $serial_glob port. Connect the board and re-run."
            return 1
        fi
        echo "Resetting $port into bootloader..."
        python3 -c "
import serial, time
s = serial.Serial('$port'); s.baudrate = 1200; s.dtr = False; time.sleep(0.1); s.close()
" 2>/dev/null || { sudo stty -F "$port" 1200; exec 3<>"$port"; sleep 0.1; exec 3>&-; }
        local found=false
        for i in $(seq 1 30); do
            if find_uf2_drive "$label"; then found=true; break; fi
            sleep 1
        done
        [ "$found" != true ] && echo "WARNING: $label drive did not appear." && return 1
    fi

    local uf2
    uf2=$(find "$HOME/.cache/arduino/sketches" -name "${sketch_name}.ino.uf2" 2>/dev/null | head -n 1)
    [ -z "$uf2" ] && uf2=$(find "$sketch_dir" -name "*.uf2" 2>/dev/null | head -n 1)
    [ -z "$uf2" ] && echo "WARNING: $sketch_name: .uf2 not found." && return 1
    sudo cp "$uf2" "$UF2_DRIVE/" && sync
    echo "✓ $sketch_name flashed"
    [[ "$UF2_DRIVE" == /mnt/* ]] && sudo umount "$UF2_DRIVE" 2>/dev/null || true
}

flash_serial() {
    local sketch_dir="$1" meta="$2" fqbn="$3"
    local sketch_name; sketch_name=$(basename "$sketch_dir")
    local serial_glob; serial_glob=$(yaml_get "$meta" serial_glob "/dev/ttyUSB*")
    local port;        port=$(ls $serial_glob 2>/dev/null | head -n 1)
    [ -z "$port" ] && echo "WARNING: $sketch_name: no port matching $serial_glob." && return 1
    [ -z "$fqbn" ] && echo "WARNING: $sketch_name: no fqbn." && return 1
    "$ARDUINO_CLI" --config-file "$ARDUINO_CONFIG" upload \
        --fqbn "$fqbn" --port "$port" "$sketch_dir" && \
        echo "✓ $sketch_name flashed" || { echo "✗ $sketch_name upload failed"; return 1; }
}

SKETCHES=()
while IFS= read -r line; do
    SKETCHES+=("$line")
done < <(find "$SRC_DIR" -path "*/.git" -prune -o \
    -name sketch.yaml -print | xargs -I {} dirname {} | sort -u)

if [ ${#SKETCHES[@]} -eq 0 ]; then
    echo "No firmware sketches found — skipping firmware section"
else
    echo "Stopping containers to free serial ports..."
    cd "$SCRIPT_DIR"
    docker compose down --remove-orphans 2>/dev/null || true

    cd "$ARDUINO_DIR"
    mkdir -p "$ARDUINO_DIR/tmp"
    export TMPDIR="$ARDUINO_DIR/tmp"
    "$ARDUINO_CLI" --config-file "$ARDUINO_CONFIG" core update-index

    EXTRA_LIBS_DIR="$ARDUINO_DIR/extra-libraries"
    mkdir -p "$EXTRA_LIBS_DIR"

    for sketch_dir in "${SKETCHES[@]}"; do
        sketch_name=$(basename "$sketch_dir")
        sketch_yaml="$sketch_dir/sketch.yaml"
        meta="$sketch_dir/firmware.yaml"

        echo "=== $sketch_name ==="
        [ ! -f "$meta" ] && echo "✗ missing firmware.yaml" && exit 1

        fqbn=$(sketch_yaml_field "$sketch_yaml" fqbn)
        platform_spec=$(sketch_yaml_field "$sketch_yaml" platform)
        platform_url=$(sketch_yaml_field "$sketch_yaml" platform_url)
        [ -z "$fqbn" ] && echo "✗ sketch.yaml has no fqbn" && exit 1

        if [ -n "$platform_spec" ]; then
            core_args=(core install "$platform_spec")
            [ -n "$platform_url" ] && core_args+=(--additional-urls "$platform_url")
            "$ARDUINO_CLI" --config-file "$ARDUINO_CONFIG" "${core_args[@]}"
        fi

        while IFS= read -r lib; do
            [ -z "$lib" ] && continue
            "$ARDUINO_CLI" --config-file "$ARDUINO_CONFIG" lib install "$lib"
        done < <(sketch_yaml_field "$sketch_yaml" libraries)

        while IFS= read -r entry; do
            [ -z "$entry" ] && continue
            url="${entry%%#*}"
            ver=""; [[ "$entry" == *"#"* ]] && ver="${entry##*#}"
            libname=$(basename "$url" .git)
            target="$EXTRA_LIBS_DIR/$libname"
            [ -d "$target" ] && [ ! -d "$target/.git" ] && rm -rf "$target"
            if [ ! -d "$target/.git" ]; then
                [ -n "$ver" ] && \
                    git clone --depth 1 --branch "$ver" "$url" "$target" || \
                    git clone --depth 1 "$url" "$target"
            fi
            # Alias micro_ros_arduino esp32 prebuilt to S3/S2/C3/C6/H2 variants
            if [ "$libname" = "micro_ros_arduino" ] && [ -d "$target/src/esp32" ]; then
                for variant in esp32s3 esp32s2 esp32c3 esp32c6 esp32h2; do
                    [ ! -e "$target/src/$variant" ] && \
                        ln -sfn esp32 "$target/src/$variant"
                done
            fi
        done < <(yaml_extra_libs "$meta")

        cat > "$sketch_dir/domain_id.h" <<EOF
// AUTO-GENERATED by install.sh — do not edit manually.
#pragma once
#define MICROROS_DOMAIN_ID $ROS_DOMAIN_ID
EOF

        echo "Compiling $sketch_name (MICROROS_DOMAIN_ID=$ROS_DOMAIN_ID)..."
        "$ARDUINO_CLI" --config-file "$ARDUINO_CONFIG" \
            compile --fqbn "$fqbn" --libraries "$EXTRA_LIBS_DIR" "$sketch_dir"
        echo "✓ $sketch_name compiled"

        flash_method=$(yaml_get "$meta" flash_method)
        case "$flash_method" in
            uf2)    flash_uf2    "$sketch_dir" "$meta"       || true ;;
            serial) flash_serial "$sketch_dir" "$meta" "$fqbn" || true ;;
            *)      echo "✗ unknown flash_method '$flash_method'"; exit 1 ;;
        esac
    done
    unset TMPDIR
fi

cd "$SCRIPT_DIR"

# Build Docker image
echo "Building Docker image (profile: $PLATFORM)..."
docker compose --profile "$PLATFORM" build "$PLATFORM"
chmod +x "$SCRIPT_DIR/launch_container.sh" "$SCRIPT_DIR/connect.sh" 2>/dev/null || true

# Linux-only setup (skip on macOS and Windows/WSL2)
if [ "$PLATFORM" != "mac" ] && [ "$PLATFORM" != "windows" ]; then
    # Terminator
    if ! command -v terminator &> /dev/null; then
        sudo apt-get update && sudo apt-get install -y terminator
    fi

    # Persistent X11 access for Docker
    AUTOSTART_DIR="$HOME/.config/autostart"
    mkdir -p "$AUTOSTART_DIR"
    cat > "$AUTOSTART_DIR/docker-xhost.desktop" << 'XHOST_EOF'
[Desktop Entry]
Type=Application
Name=Docker X11 Access
Exec=xhost +local:docker
NoDisplay=true
X-GNOME-Autostart-enabled=true
XHOST_EOF
    xhost +local:docker 2>/dev/null || true

    # Desktop shortcuts
    APPS_DIR="$HOME/.local/share/applications/$(basename "$SCRIPT_DIR")"
    rm -rf "$APPS_DIR" 2>/dev/null || sudo rm -rf "$APPS_DIR"
    mkdir -p "$APPS_DIR"
    cp "$ENV_FILE" "$APPS_DIR/"
    cp "$SCRIPT_DIR/docker-compose.yaml" "$APPS_DIR/"
    cp "$SCRIPT_DIR/launch_container.sh" "$APPS_DIR/" && chmod +x "$APPS_DIR/launch_container.sh"
    [ -f "$SCRIPT_DIR/connect.sh" ] && \
        cp "$SCRIPT_DIR/connect.sh" "$APPS_DIR/" && chmod +x "$APPS_DIR/connect.sh"
    ASSETS_DIR="$APPS_DIR/assets"; mkdir -p "$ASSETS_DIR"
    for asset in "$SCRIPT_DIR/assets/"*; do [ -f "$asset" ] && cp "$asset" "$ASSETS_DIR/"; done

    for desktop_file in launch.desktop devel.desktop; do
        if [ -f "$SCRIPT_DIR/$desktop_file" ]; then
            cp "$SCRIPT_DIR/$desktop_file" "$APPS_DIR/"
            sed -i "s|Exec=.*|Exec=terminator --new-tab -e \"bash -c 'source $APPS_DIR/.env \&\& $APPS_DIR/launch_container.sh; exec bash'\"|" \
                "$APPS_DIR/$desktop_file"
            # TODO: Place icon.png and icon_dev.png in assets/ for desktop shortcuts
            [ "$desktop_file" = "launch.desktop" ] && \
                echo "Icon=$ASSETS_DIR/icon.png" >> "$APPS_DIR/$desktop_file"
            [ "$desktop_file" = "devel.desktop" ] && \
                echo "Icon=$ASSETS_DIR/icon_dev.png" >> "$APPS_DIR/$desktop_file"
            chmod +x "$APPS_DIR/$desktop_file"
            rm -f "$HOME/Desktop/$desktop_file"
            cp "$APPS_DIR/$desktop_file" "$HOME/Desktop/" && chmod +x "$HOME/Desktop/$desktop_file"
        fi
    done
    command -v update-desktop-database &> /dev/null && \
        update-desktop-database "$APPS_DIR"

    # Socket buffer limits for FastDDS / CycloneDDS
    SYSCTL_FILE="/etc/sysctl.d/99-fastdds.conf"
    sudo tee "$SYSCTL_FILE" > /dev/null << 'SYSCTL_EOF'
net.core.rmem_max=10485760
net.core.rmem_default=10485760
net.core.wmem_max=10485760
net.core.wmem_default=10485760
SYSCTL_EOF
    sudo sysctl --system

    # IP fragment reassembly cache — required for image topics across hosts
    grep -q "net.ipv4.ipfrag_high_thresh=134217728" /etc/sysctl.conf || \
        echo "net.ipv4.ipfrag_high_thresh=134217728" | sudo tee -a /etc/sysctl.conf
    grep -q "net.ipv4.ipfrag_low_thresh=100663296" /etc/sysctl.conf || \
        echo "net.ipv4.ipfrag_low_thresh=100663296" | sudo tee -a /etc/sysctl.conf
    sudo sysctl -p

    # Loopback multicast (required for ROS2 discovery with ROS_LOCALHOST_ONLY)
    sudo ip link set lo multicast on || true
    sudo tee /etc/systemd/system/lo-multicast.service > /dev/null << 'EOF'
[Unit]
Description=Enable multicast on loopback interface (required for ROS2)
After=network.target
[Service]
Type=oneshot
ExecStart=/sbin/ip link set lo multicast on
RemainAfterExit=yes
[Install]
WantedBy=multi-user.target
EOF
    sudo systemctl daemon-reload
    sudo systemctl enable lo-multicast.service 2>/dev/null || true

    # Systemd auto-start service
    SERVICE_NAME="$CONTAINER_NAME"
    sudo tee "/etc/systemd/system/${SERVICE_NAME}.service" > /dev/null << EOF
[Unit]
Description=$PROJECT_NAME ROS2 Docker Container ($PLATFORM)
After=docker.service network-online.target nvargus-daemon.service lo-multicast.service
Wants=network-online.target nvargus-daemon.service lo-multicast.service
Requires=docker.service

[Service]
Type=simple
User=$USER
WorkingDirectory=$SCRIPT_DIR
ExecStart=$SCRIPT_DIR/launch_container.sh
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
    sudo systemctl daemon-reload
    sudo systemctl enable "$SERVICE_NAME.service"
    sudo systemctl restart "$SERVICE_NAME.service"
fi

echo ""
echo "========================================="
echo " Installation complete: $CONTAINER_NAME"
echo " Platform: $(platform_display_name "$PLATFORM")"
echo "========================================="
echo ""
echo "  Launch:     ./launch_container.sh"
echo "  New shell:  ./connect.sh"
[ "$PLATFORM" != "mac" ] && [ "$PLATFORM" != "windows" ] && \
    echo "  Service:    sudo systemctl status $CONTAINER_NAME"
echo ""
