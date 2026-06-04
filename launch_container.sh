#!/bin/bash

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR" || exit 1

[ -f .env ] && source .env

CONTAINER_NAME="${CONTAINER_NAME:-doc_template}"
PLATFORM="${PLATFORM:-linux}"

# Non-interactive mode (systemd service)
if [ ! -t 0 ] || [ ! -t 1 ]; then
    echo "Starting '$CONTAINER_NAME' in service mode..."
    docker compose up --no-recreate -d "$PLATFORM"
    docker wait "$CONTAINER_NAME" 2>/dev/null || true
    exit $?
fi

# X11 display forwarding
if [ "$(uname)" = "Darwin" ]; then
    if ! pgrep -q Xquartz && ! pgrep -q X11; then
        open -a XQuartz 2>/dev/null; sleep 3
    fi
    _xsock=$(ls -t /tmp/.X11-unix/X* 2>/dev/null | head -1)
    _xnum="${_xsock##*/X}"
    if command -v socat >/dev/null 2>&1 && [ -n "$_xsock" ]; then
        pkill -f "socat.*TCP-LISTEN:6100" 2>/dev/null; sleep 0.3
        socat TCP-LISTEN:6100,fork,reuseaddr,bind=127.0.0.1 \
              "UNIX-CONNECT:${_xsock}" 2>/dev/null &
        _socat_pid=$!
        trap 'kill $_socat_pid 2>/dev/null' EXIT
        export DOCKER_DISPLAY="host.docker.internal:100"
        DISPLAY=":${_xnum}" xhost +localhost 2>/dev/null
        DISPLAY=":${_xnum}" xhost + 2>/dev/null
    else
        ! command -v socat >/dev/null 2>&1 && \
            echo "⚠  socat not found — run: brew install socat"
        export DOCKER_DISPLAY=":${_xnum:-0}"
        DISPLAY=":${_xnum:-0}" xhost + 2>/dev/null
    fi
else
    if [ -z "$DISPLAY" ]; then
        for sock in /tmp/.X11-unix/X*; do
            [ -S "$sock" ] && export DISPLAY=":${sock##*X}" && break
        done
    fi
    if [ -n "$DISPLAY" ]; then
        XAUTH=/tmp/.docker.xauth
        [ -d "$XAUTH" ] && sudo rm -rf "$XAUTH"
        [ -e "$XAUTH" ] && [ ! -w "$XAUTH" ] && sudo rm -f "$XAUTH"
        install -m 666 /dev/null "$XAUTH" 2>/dev/null || sudo install -m 666 /dev/null "$XAUTH"
        xauth nlist "$DISPLAY" 2>/dev/null | sed -e 's/^..../ffff/' | \
            xauth -f "$XAUTH" nmerge - 2>/dev/null
        if ! xhost +local:docker 2>/dev/null; then
            GDM_XAUTH=$(ls /run/user/*/gdm/Xauthority 2>/dev/null | head -1)
            [ -n "$GDM_XAUTH" ] && \
                sudo XAUTHORITY="$GDM_XAUTH" DISPLAY="$DISPLAY" xhost +local:docker 2>/dev/null || true
        fi
    fi
fi

# Find running container
COMPOSE_PROJECT=$(echo "${CONTAINER_NAME}" | tr '-' '_')
RUNNING_CONTAINER=$(docker ps --format '{{.Names}}' | \
    grep -E "^(${CONTAINER_NAME}|${COMPOSE_PROJECT})(-${PLATFORM}-run-.*)?$" | head -n 1)

# On macOS, pass the socat TCP relay address (set above) rather than the host's
# XQuartz Unix socket path, which is unreachable from inside Docker bridge.
if [ "$(uname)" = "Darwin" ]; then
    EFFECTIVE_DISPLAY="${DOCKER_DISPLAY:-host.docker.internal:100}"
else
    EFFECTIVE_DISPLAY="$DISPLAY"
fi
EXEC_ENV=(-e "XAUTHORITY=/tmp/.docker.xauth")
[ -n "$EFFECTIVE_DISPLAY" ] && EXEC_ENV+=(-e "DISPLAY=$EFFECTIVE_DISPLAY")

if [ -n "$RUNNING_CONTAINER" ]; then
    CURRENT_IMAGE="${CONTAINER_NAME:-doc_template}:humble"
    RUNNING_IMAGE=$(docker inspect --format '{{.Config.Image}}' "$RUNNING_CONTAINER" 2>/dev/null)
    if [ "$RUNNING_IMAGE" != "$CURRENT_IMAGE" ]; then
        echo "⚠  Running container uses image '$RUNNING_IMAGE', current is '$CURRENT_IMAGE'."
        echo "   Run: docker rm -f $RUNNING_CONTAINER  then re-run ./launch_container.sh"
    fi
    echo "Attaching to '$RUNNING_CONTAINER'..."
    if [ $# -eq 0 ]; then
        exec docker exec -it "${EXEC_ENV[@]}" "$RUNNING_CONTAINER" \
            /bin/bash -c 'source /workspaces/shared_ws/install/setup.bash 2>/dev/null; exec bash -i'
    else
        exec docker exec -it "${EXEC_ENV[@]}" "$RUNNING_CONTAINER" \
            /bin/bash -c "source /workspaces/shared_ws/install/setup.bash 2>/dev/null; $*"
    fi
else
    echo "Starting '$CONTAINER_NAME' ($PLATFORM)..."
    if [ $# -eq 0 ]; then
        docker compose run --rm --remove-orphans "$PLATFORM" /bin/bash -c '
            cd /workspaces/shared_ws
            echo ""
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo " Building ROS workspace..."
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            colcon build --symlink-install \
                --cmake-args -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=OFF
            source install/setup.bash
            echo ""
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo " Workspace ready.  Use ./connect.sh for additional shells."
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo ""
            exec bash -i
        '
    else
        docker compose run --rm --remove-orphans "$PLATFORM" /bin/bash -c "source ~/.bashrc && $*"
    fi
fi
