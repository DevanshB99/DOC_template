#!/bin/bash

source /opt/ros/${ROS_DISTRO}/setup.bash

if [ -f /workspaces/base_ws/install/setup.bash ]; then
    source /workspaces/base_ws/install/setup.bash
fi

if [ -d /workspaces/shared_ws/src ]; then
    colcon build --symlink-install \
        --cmake-args -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=OFF \
        --base-paths /workspaces/shared_ws/src
fi

if [ -f /workspaces/shared_ws/install/setup.bash ]; then
    source /workspaces/shared_ws/install/setup.bash
fi

export RMW_IMPLEMENTATION=rmw_fastrtps_cpp

# TODO: Replace with your bringup launch command
# exec ros2 launch <your_package> bringup.launch.py "$@"
exec "$@"
