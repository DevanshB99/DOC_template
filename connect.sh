#!/bin/bash
# Attach a new shell to the already-running container without triggering a rebuild.
# Usage: ./connect.sh          — interactive bash
#        ./connect.sh rqt      — run a single command

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR" || exit 1

[ -f .env ] && source .env

CONTAINER_NAME="${CONTAINER_NAME:-doc_template}"
PLATFORM="${PLATFORM:-linux}"

COMPOSE_PROJECT=$(echo "${CONTAINER_NAME}" | tr '-' '_')
RUNNING_CONTAINER=$(docker ps --format '{{.Names}}' | \
    grep -E "^(${CONTAINER_NAME}|${COMPOSE_PROJECT})(-${PLATFORM}-run-.*)?$" | head -n 1)

if [ -z "$RUNNING_CONTAINER" ]; then
    echo "No container running. Start one with: ./launch_container.sh"
    exit 1
fi

if [ "$(uname)" = "Darwin" ]; then
    EFFECTIVE_DISPLAY="host.docker.internal:100"
else
    EFFECTIVE_DISPLAY="$DISPLAY"
fi
EXEC_ENV=(-e "XAUTHORITY=/tmp/.docker.xauth")
[ -n "$EFFECTIVE_DISPLAY" ] && EXEC_ENV+=(-e "DISPLAY=$EFFECTIVE_DISPLAY")

if [ $# -eq 0 ]; then
    exec docker exec -it "${EXEC_ENV[@]}" "$RUNNING_CONTAINER" \
        /bin/bash -c 'source /workspaces/shared_ws/install/setup.bash 2>/dev/null; exec bash -i'
else
    exec docker exec -it "${EXEC_ENV[@]}" "$RUNNING_CONTAINER" \
        /bin/bash -c "source /workspaces/shared_ws/install/setup.bash 2>/dev/null; $*"
fi
