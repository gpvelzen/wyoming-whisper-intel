# syntax=docker/dockerfile:1
FROM intel/oneapi-toolkit:latest

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# --- base tools & dependencies optimization ---
RUN apt-get update && apt-get install -y --no-install-recommends \
      git cmake build-essential ca-certificates wget \
      python3 python3-venv python3-pip curl \
      && rm -rf /var/lib/apt/lists/*

ENV OPENVINO_VERSION=2026.4.1
ENV OPENVINO_PACKAGE_URL=https://storage.openvinotoolkit.org/repositories/openvino/packages/2026.4.1/linux/openvino_toolkit_ubuntu24_2026.4.1.22982.07f9c262b05_x86_64.tgz

# Download and install prebuilt OpenVINO
RUN wget ${OPENVINO_PACKAGE_URL} -O openvino.tgz && \
    tar -xzf openvino.tgz && \
    rm openvino.tgz && \
    sed -i 's/apt-get install /apt-get install -y /g' openvino_toolkit_ubuntu24_${OPENVINO_VERSION}.*/install_dependencies/install_openvino_dependencies.sh && \
    /bin/bash openvino_toolkit_ubuntu24_${OPENVINO_VERSION}.*/install_dependencies/install_openvino_dependencies.sh && \
    mkdir -p /opt/intel && \
    mv openvino_toolkit_ubuntu24_${OPENVINO_VERSION}.* /opt/intel/openvino_${OPENVINO_VERSION}

# --- Set OpenVINO environment variables
ENV INTEL_OPENVINO_DIR=/opt/intel/openvino_${OPENVINO_VERSION}
ENV PATH=$INTEL_OPENVINO_DIR/bin:$PATH
ENV LD_LIBRARY_PATH=$INTEL_OPENVINO_DIR/runtime/lib/intel64:$LD_LIBRARY_PATH

# --- Clone and Build whisper.cpp with OpenVINO support
RUN git clone https://github.com/ggerganov/whisper.cpp.git /whisper.cpp
WORKDIR /whisper.cpp
RUN /bin/bash -c "source $INTEL_OPENVINO_DIR/setupvars.sh && \
    cmake -B build -DWHISPER_OPENVINO=1 -DCMAKE_BUILD_TYPE=Release && \
    cmake --build build --config Release"

# --- wyoming bridge (API client) ---
WORKDIR /
RUN git clone https://github.com/ser/wyoming-whisper-api-client.git \
 && cd wyoming-whisper-api-client \
 && ./script/setup

# Make sure the repo's venv bins are easily reachable when debugging
ENV PATH="/wyoming-whisper-api-client/.venv/bin:${PATH}"

# --- Sane GPU & Service Defaults ---
ENV ONEAPI_DEVICE_SELECTOR=level_zero:gpu \
    ZE_ENABLE_PCI_ID_DEVICE_ORDER=1 \
    WHISPER_MODEL=small \
    WHISPER_LANG=en \
    WHISPER_BEAM_SIZE=5 \
    WHISPER_HTTP_HOST=127.0.0.1 \
    WHISPER_HTTP_PORT=8910 \
    WYOMING_URI=tcp://0.0.0.0:7891 \
    MODEL_BASE_URL=https://huggingface.co/ggerganov/whisper.cpp/resolve/main \
    MODELS_DIR=/models

RUN mkdir -p /models

# Expose Wyoming port for Home Assistant
EXPOSE 7891

HEALTHCHECK --start-period=90s --interval=30s --timeout=5s --retries=3 \
  CMD curl -f http://127.0.0.1:${WHISPER_HTTP_PORT}/ || exit 1

# Copy orchestrator scripts
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
