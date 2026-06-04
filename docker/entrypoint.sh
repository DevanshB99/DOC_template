#!/bin/bash

export PATH=$PATH:$HOME/.local/bin

git config --global --add safe.directory '*' 2>/dev/null || true

source /opt/ros/${ROS_DISTRO}/setup.bash

if [ -f /workspaces/base_ws/install/setup.bash ]; then
    source /workspaces/base_ws/install/setup.bash
fi

if [ -f /workspaces/gscam2_ws/install/setup.bash ]; then
    source /workspaces/gscam2_ws/install/setup.bash
fi

if [ -f /workspaces/shared_ws/install/setup.bash ]; then
    source /workspaces/shared_ws/install/setup.bash
else
    echo "Building overlay workspace..."
    if (cd /workspaces/shared_ws && colcon build --symlink-install \
            --cmake-args -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=OFF); then
        source /workspaces/shared_ws/install/setup.bash
        echo "✓ Workspace built"
    else
        echo "⚠ Workspace build failed"
    fi
fi

# FastDDS is required for micro-ROS agent discovery (embedded Fast-DDS)
export RMW_IMPLEMENTATION=rmw_fastrtps_cpp

export QT_QPA_PLATFORM=xcb

XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp/runtime-$(id -u)}"
export XDG_RUNTIME_DIR
mkdir -p "$XDG_RUNTIME_DIR" && chmod 0700 "$XDG_RUNTIME_DIR" 2>/dev/null || true

if [ "${PLATFORM_TYPE:-desktop}" != "jetson" ]; then
    export LIBGL_ALWAYS_SOFTWARE=1
    case "${DISPLAY:-}" in
        host.docker.internal:*)
            export QT_OPENGL=software
            export QT_QUICK_BACKEND=software
            export QT_XCB_GL_INTEGRATION=none
            ;;
    esac
fi

exec "$@"
