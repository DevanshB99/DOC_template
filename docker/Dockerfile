ARG BASE_IMAGE=osrf/ros:humble-desktop-full
ARG ONNXRUNTIME_STAGE=onnxruntime_noop
FROM alpine:3.19 AS onnxruntime_noop
RUN mkdir /ort

# For Jetson pass: ONNXRUNTIME_STAGE=dustynv/onnxruntime:1.20.2-r36.4.0
FROM ${ONNXRUNTIME_STAGE} AS onnxruntime_src
RUN mkdir -p /ort && \
    WHL=$(find /opt /dist /packages /data /build /root -maxdepth 5 \
        -name "onnxruntime_gpu*.whl" -type f 2>/dev/null | head -1) && \
    if [ -n "$WHL" ]; then \
        cp "$WHL" /ort/; \
    else \
        SITE=$(python3 -c "import site; print(site.getsitepackages()[0])" 2>/dev/null || echo "") && \
        if [ -n "$SITE" ] && [ -d "$SITE/onnxruntime" ]; then \
            cd "$SITE" && tar czf /ort/onnxruntime_pkg.tar.gz \
                $(ls -d onnxruntime onnxruntime_gpu*.dist-info 2>/dev/null); \
        fi; \
    fi || true

FROM ${BASE_IMAGE}

ARG ROS_DISTRO=humble
ENV ROS_DISTRO=${ROS_DISTRO}

ARG PLATFORM_TYPE=desktop
ENV PLATFORM_TYPE=${PLATFORM_TYPE}

# TORCH_INSTALL=cpu  → CPU wheel (linux / mac / rpi)
# TORCH_INSTALL=gpu  → CUDA wheel (linux-gpu)
# TORCH_INSTALL=skip → omit (jetson installs its own wheel below)
ARG TORCH_INSTALL=cpu

RUN printf '[global]\nindex-url = https://pypi.org/simple/\n' > /etc/pip.conf

RUN curl -sSL https://raw.githubusercontent.com/ros/rosdistro/master/ros.asc | \
    gpg --batch --yes --dearmor -o /usr/share/keyrings/ros-archive-keyring.gpg

# Remove stale apt sources baked into NVIDIA base images
RUN sed -i '/isaac\.download\.nvidia\.com\/isaac-ros\/ubuntu/d' /etc/apt/sources.list 2>/dev/null || true && \
    grep -rl 'isaac\.download\.nvidia\.com/isaac-ros/ubuntu' \
        /etc/apt/sources.list.d/ 2>/dev/null | xargs rm -f || true && \
    grep -rl 'apt\.kitware\.com' \
        /etc/apt/sources.list.d/ 2>/dev/null | xargs rm -f || true && \
    grep -rl 'dl\.yarnpkg\.com' \
        /etc/apt/sources.list.d/ 2>/dev/null | xargs rm -f || true && \
    find /usr/share/keyrings/ \( -name "kitware*.gpg" -o -name "kitware*.asc" \
        -o -name "yarn*.gpg" -o -name "yarn*.asc" \) -delete || true && \
    rm -rf /var/lib/apt/lists/*

COPY docker/packages.txt /tmp/packages.txt
RUN apt-get update && \
    grep -v '^#' /tmp/packages.txt | grep -v '^$' | \
    xargs apt-get install -y --no-install-recommends && \
    rm -rf /var/lib/apt/lists/* /tmp/packages.txt && \
    fc-cache -fv

# PyTorch — installed early so this ~2GB layer is cached independently of ROS/pip changes
RUN if [ "$TORCH_INSTALL" = "cpu" ]; then \
        pip3 install --no-cache-dir \
            --index-url https://download.pytorch.org/whl/cpu \
            torch torchvision; \
    elif [ "$TORCH_INSTALL" = "gpu" ]; then \
        pip3 install --no-cache-dir \
            --index-url https://pypi.org/simple/ \
            torch torchvision; \
    fi

RUN python3 -m pip install --upgrade colcon-common-extensions colcon-core

RUN colcon mixin list | grep -q "default" || \
    colcon mixin add default \
        https://raw.githubusercontent.com/colcon/colcon-mixin-repository/master/index.yaml && \
    colcon mixin update default

RUN rosdep update

# micro-ROS base workspace
RUN mkdir -p /workspaces/base_ws/src
WORKDIR /workspaces/base_ws

RUN git clone -b $ROS_DISTRO \
    https://github.com/micro-ROS/micro_ros_setup.git src/micro_ros_setup
RUN sudo apt-get update && rosdep update && \
    rosdep install --from-paths src --ignore-src -y

RUN /bin/bash -c "source /opt/ros/${ROS_DISTRO}/setup.bash && \
    colcon build --executor sequential \
    --cmake-args -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=OFF"

RUN /bin/bash -c "source /opt/ros/${ROS_DISTRO}/setup.bash && \
    source install/setup.bash && \
    ros2 run micro_ros_setup create_agent_ws.sh"

RUN /bin/bash -c "source /opt/ros/${ROS_DISTRO}/setup.bash && \
    source install/setup.bash && \
    ros2 run micro_ros_setup build_agent.sh"

# Isaac ROS apt repository (Jetson only)
RUN if [ "$PLATFORM_TYPE" = "jetson" ]; then \
        curl -sSL https://isaac.download.nvidia.com/isaac-ros/repos.key | \
            gpg --batch --yes --dearmor \
                -o /usr/share/keyrings/isaac-ros-archive-keyring.gpg && \
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/isaac-ros-archive-keyring.gpg] \
https://isaac.download.nvidia.com/isaac-ros/release-3 $(lsb_release -cs) release" \
            > /etc/apt/sources.list.d/isaac-ros.list; \
    fi

COPY docker/overlay_packages.txt /tmp/overlay_packages.txt
RUN apt-get update && \
    grep -v '^#' /tmp/overlay_packages.txt | grep -v '^$' | \
    xargs apt-get install -y --no-install-recommends && \
    rm -rf /var/lib/apt/lists/* /tmp/overlay_packages.txt

# TODO: Add Jetson-only packages to docker/overlay_packages_jetson.txt
COPY docker/overlay_packages_jetson.txt /tmp/overlay_packages_jetson.txt
RUN if [ "$PLATFORM_TYPE" = "jetson" ]; then \
        apt-get update && \
        grep -v '^#' /tmp/overlay_packages_jetson.txt | grep -v '^$' | \
        xargs apt-get install -y --no-install-recommends && \
        rm -rf /var/lib/apt/lists/*; \
    fi && rm -f /tmp/overlay_packages_jetson.txt

# TODO: Add your Python dependencies to docker/requirements.txt
COPY docker/requirements.txt /tmp/requirements.txt
RUN apt-get remove -y python3-sympy 2>/dev/null || true
RUN python3 -m pip install --index-url https://pypi.org/simple/ \
    -r /tmp/requirements.txt && rm /tmp/requirements.txt

# Jetson.GPIO — Jetson only (fails on import on non-Jetson hardware)
RUN if [ "$PLATFORM_TYPE" = "jetson" ]; then \
        pip3 install --no-cache-dir --index-url https://pypi.org/simple/ Jetson.GPIO; \
    fi

# Jetson: NVIDIA PyTorch wheel (JetPack 6.1 / CUDA 12.2)
RUN if [ "$PLATFORM_TYPE" = "jetson" ]; then \
        TORCH_WHL="torch-2.5.0a0+872d972e41.nv24.08.17622132-cp310-cp310-linux_aarch64.whl" && \
        curl -L -o "/tmp/${TORCH_WHL}" \
            "https://developer.download.nvidia.com/compute/redist/jp/v61/pytorch/${TORCH_WHL}" && \
        pip3 install --no-cache-dir --force-reinstall --no-deps "/tmp/${TORCH_WHL}" && \
        rm "/tmp/${TORCH_WHL}" && \
        pip3 install --no-cache-dir --index-url https://pypi.org/simple/ \
            nvidia-cusparselt-cu12 && \
        CUSPARSELT_LIB=$(find /usr/local/lib/python3.10 -name "libcusparseLt.so*" \
            -type f 2>/dev/null | head -1 | xargs dirname 2>/dev/null) && \
        if [ -n "$CUSPARSELT_LIB" ]; then \
            echo "$CUSPARSELT_LIB" > /etc/ld.so.conf.d/nvidia-cusparselt.conf && ldconfig; \
        fi && \
        pip3 install --no-cache-dir --no-deps \
            --index-url https://pypi.org/simple/ "torchvision==0.20.1"; \
    fi

# onnxruntime-gpu from Jetson ONNXRUNTIME_STAGE (no-op on non-Jetson)
COPY --from=onnxruntime_src /ort/ /tmp/ort/
RUN WHL=$(ls /tmp/ort/onnxruntime_gpu*.whl 2>/dev/null | head -1) && \
    if [ -n "$WHL" ]; then \
        pip3 uninstall -y onnxruntime 2>/dev/null || true && \
        pip3 install --no-cache-dir --force-reinstall --no-deps \
            --index-url https://pypi.org/simple/ "$WHL"; \
    elif [ -f /tmp/ort/onnxruntime_pkg.tar.gz ]; then \
        pip3 uninstall -y onnxruntime 2>/dev/null || true && \
        SITE=$(python3 -c "import site; print(site.getsitepackages()[0])") && \
        tar xzf /tmp/ort/onnxruntime_pkg.tar.gz -C "$SITE"; \
    fi && rm -rf /tmp/ort

# onnxruntime-gpu from PyPI for linux-gpu (x86_64 CUDA build)
RUN if [ "$PLATFORM_TYPE" = "gpu" ]; then \
        pip3 uninstall -y onnxruntime 2>/dev/null || true && \
        pip3 install --no-cache-dir --index-url https://pypi.org/simple/ onnxruntime-gpu; \
    fi

RUN apt-get update && apt-get install -y --no-install-recommends \
    ros-${ROS_DISTRO}-rmw-cyclonedds-cpp && \
    rm -rf /var/lib/apt/lists/*

# Image default is CycloneDDS; entrypoint and compose override to FastDDS at runtime
ENV RMW_IMPLEMENTATION=rmw_cyclonedds_cpp

# PulseAudio ALSA bridge — sounddevice finds no devices without this inside Docker
RUN apt-get update && apt-get install -y --no-install-recommends \
        libpulse0 pulseaudio-utils libasound2-plugins && \
    rm -rf /var/lib/apt/lists/*

RUN printf 'pcm.!default { type pulse fallback "sysdefault" }\nctl.!default { type pulse fallback "sysdefault" }\n' \
        > /etc/asound.conf

RUN mkdir -p /workspaces/shared_ws/src /data /models

# gscam2 from source — Jetson only (arm64/Jammy binary not available)
RUN mkdir -p /workspaces/gscam2_ws/src && \
    if [ "$PLATFORM_TYPE" = "jetson" ]; then \
        apt-get update && \
        apt-get install -y --no-install-recommends \
            libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev && \
        rm -rf /var/lib/apt/lists/* && \
        git clone --depth 1 https://github.com/clydemcqueen/gscam2.git \
            /workspaces/gscam2_ws/src/gscam2 && \
        /bin/bash -c "source /opt/ros/${ROS_DISTRO}/setup.bash && \
            cd /workspaces/gscam2_ws && \
            colcon build --executor sequential \
                --cmake-args -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=OFF"; \
    fi

RUN apt-get update && apt-get install -y sudo && rm -rf /var/lib/apt/lists/*

ARG USERNAME=doc_user
ARG UID=1000
ARG GID=${UID}
ARG VIDEO_GID=44
ARG DIALOUT_GID=20
ARG AUDIO_GID=29
ARG INPUT_GID=105
ARG PLUGDEV_GID=46
ARG I2C_GID=121
ARG GPIO_GID=999

RUN getent group video   || groupadd --gid ${VIDEO_GID}   video
RUN getent group dialout || groupadd --gid ${DIALOUT_GID} dialout
RUN getent group audio   || groupadd --gid ${AUDIO_GID}   audio
RUN getent group input   || groupadd --gid ${INPUT_GID}   input
RUN getent group plugdev || groupadd --gid ${PLUGDEV_GID} plugdev
RUN if [ "$PLATFORM_TYPE" = "jetson" ]; then \
        getent group i2c || groupadd --gid ${I2C_GID} i2c; \
        getent group gpio || groupadd --gid ${GPIO_GID} gpio; \
    fi

# Handle pre-existing UID/GID (Isaac ROS base ships ubuntu at UID 1000)
RUN if getent group ${GID} > /dev/null 2>&1; then \
        groupmod -n ${USERNAME} "$(getent group ${GID} | cut -d: -f1)"; \
    else \
        groupadd --gid ${GID} ${USERNAME}; \
    fi && \
    if getent passwd ${UID} > /dev/null 2>&1; then \
        OLD="$(getent passwd ${UID} | cut -d: -f1)" && \
        usermod -l ${USERNAME} -d /home/${USERNAME} -m "$OLD"; \
    else \
        useradd --uid ${UID} --gid ${GID} --create-home ${USERNAME}; \
    fi && \
    usermod -a -G video    ${USERNAME} && \
    usermod -a -G dialout  ${USERNAME} && \
    usermod -a -G audio    ${USERNAME} && \
    usermod -a -G input    ${USERNAME} && \
    usermod -a -G plugdev  ${USERNAME} && \
    if [ "$PLATFORM_TYPE" = "jetson" ]; then \
        usermod -a -G i2c ${USERNAME}; \
        usermod -a -G gpio ${USERNAME}; \
    fi && \
    echo "${USERNAME} ALL=(root) NOPASSWD:ALL" > /etc/sudoers.d/${USERNAME} && \
    chmod 0440 /etc/sudoers.d/${USERNAME} && \
    mkdir -p /home/${USERNAME} && \
    chown -R ${UID}:${GID} /home/${USERNAME}

RUN chown -R ${UID}:${UID} /workspaces/shared_ws/ && \
    chown -R ${UID}:${UID} /workspaces/gscam2_ws/ && \
    chown -R ${UID}:${UID} /data/ && \
    chown -R ${UID}:${UID} /models/

COPY ./docker/entrypoint.sh /
RUN chmod +x /entrypoint.sh
RUN echo "source /entrypoint.sh" >> /home/${USERNAME}/.bashrc

USER ${USERNAME}
ENTRYPOINT [ "/entrypoint.sh" ]
