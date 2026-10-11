# syntax=docker/dockerfile:1
FROM intel/oneapi-toolkit:latest

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

RUN apt-get update && apt-get install -y --no-install-recommends curl && rm -rf /var/lib/apt/lists/*

# --- base tools ---
RUN apt-get update && apt-get install -y --no-install-recommends \
      git cmake build-essential ca-certificates wget \
      python3 python3-venv python3-pip curl \
      && rm -rf /var/lib/apt/lists/*

#Download and install prebuilt OpenVINO
RUN wget ${OPENVINO_PACKAGE_URL} -O openvino.tgz && \
    tar -xzf openvino.tgz && \
    rm openvino.tgz && \
    sed -i 's/apt-get install /apt-get install -y /g' l_openvino_toolkit_ubuntu22_${OPENVINO_VERSION}.*/install_dependencies/install_openvino_dependencies.sh && \
    /bin/bash l_openvino_toolkit_ubuntu22_${OPENVINO_VERSION}.*/install_dependencies/install_openvino_dependencies.sh && \
    mkdir -p /opt/intel && \
    mv l_openvino_toolkit_ubuntu22_${OPENVINO_VERSION}.* /opt/intel/openvino_${OPENVINO_VERSION}

# --- Set OpenVINO environment variables
ENV INTEL_OPENVINO_DIR=/opt/intel/openvino_${OPENVINO_VERSION}
ENV PATH=$INTEL_OPENVINO_DIR/bin:$PATH
ENV LD_LIBRARY_PATH=$INTEL_OPENVINO_DIR/runtime/lib/intel64:$LD_LIBRARY_PATH

# --- Clone the whisper.cpp repository
RUN git clone https://github.com/ggerganov/whisper.cpp.git /whisper.cpp

# --- Build whisper.cpp with OpenVINO support
WORKDIR /whisper.cpp
RUN /bin/bash -c "source $INTEL_OPENVINO_DIR/setupvars.sh && \
    cmake -B build -DWHISPER_OPENVINO=1 -DCMAKE_BUILD_TYPE=Release && \
    cmake --build build --config Release && \
    ls -l build/bin"

# --- wyoming bridge (API client) ---
WORKDIR /
RUN git clone https://github.com/ser/wyoming-whisper-api-client.git \
 && cd wyoming-whisper-api-client \
 && ./script/setup

# Make sure the repo's venv bins are easily reachable when debugging
ENV PATH="/wyoming-whisper-api-client/.venv/bin:${PATH}"

# copy the startup script
COPY start.sh /usr/local/bin/start.sh
RUN chmod +x /usr/local/bin/start.sh && mkdir -p /models /var/log/whispercpp

# --- sane GPU defaults ---
ENV ONEAPI_DEVICE_SELECTOR=level_zero:gpu \
    ZE_ENABLE_PCI_ID_DEVICE_ORDER=1

# --- configurable defaults (override in compose) ---
ENV ONEAPI_DEVICE_SELECTOR=level_zero:gpu \
    ZE_ENABLE_PCI_ID_DEVICE_ORDER=1 \
    WHISPER_MODEL=small \
    WHISPER_LANG=en \
    WHISPER_BEAM_SIZE=5 \
    WHISPER_HTTP_HOST=0.0.0.0 \
    WHISPER_HTTP_PORT=8910 \
    WYOMING_URI=tcp://0.0.0.0:7891 \
    MODEL_BASE_URL=https://huggingface.co/ggerganov/whisper.cpp/resolve/main

# Only expose Wyoming port; whisper HTTP stays internal
EXPOSE 7891

HEALTHCHECK --start-period=60s --interval=30s --timeout=5s --retries=5 \
  CMD sh -lc '\
    url="http://${WHISPER_HTTP_HOST}:${WHISPER_HTTP_PORT}/"; \
    printf "HC url=%s ... " "$url" >&2; \
    code=$(curl -sS -o /dev/null -w "%{http_code}" "$url" || echo 000); \
    echo "status=$code" >&2; \
    [ "$code" != 000 ] && [ "$code" -lt 500 ] || exit 1'

CMD ["/usr/local/bin/start.sh"]
