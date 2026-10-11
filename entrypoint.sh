#!/bin/bash
set -e

# 1. Source OpenVINO environments
source /opt/intel/openvino_${OPENVINO_VERSION}/setupvars.sh

# 2. Manage Model Download dynamically
MODEL_FILE="ggml-${WHISPER_MODEL}.bin"
MODEL_PATH="${MODELS_DIR}/${MODEL_FILE}"

if [ ! -f "$MODEL_PATH" ]; then
    echo "📥 Model file $MODEL_FILE not found in $MODELS_DIR. Downloading from HuggingFace..."
    wget -q --show-progress "${MODEL_BASE_URL}/${MODEL_FILE}" -O "$MODEL_PATH"
else
    echo "✅ Found existing whisper model: $MODEL_FILE"
fi

# 3. Launch backend whisper-server with OpenVINO optimization
echo "🚀 Starting whisper.cpp HTTP server on GPU..."
/whisper.cpp/build/bin/whisper-server \
    -m "$MODEL_PATH" \
    --host "$WHISPER_HTTP_HOST" \
    --port "$WHISPER_HTTP_PORT" \
    -l "$WHISPER_LANG" &
WHISPER_PID=$!

# 4. Wait for local HTTP service to compile models and respond
echo "⏳ Waiting for whisper-server to initialize OpenVINO runtime..."
until curl -s -o /dev/null "http://${WHISPER_HTTP_HOST}:${WHISPER_HTTP_PORT}/"; do
    if ! kill -0 $WHISPER_PID 2>/dev/null; then
        echo "❌ whisper-server died during initialization. Checking logs..."
        exit 1
    fi
    sleep 2
done
echo "✅ whisper-server is healthy and ready!"

# 5. Execute Wyoming client bridge as the primary foreground container thread
echo "🌉 Launching Wyoming API Bridge..."
exec python3 -m wyoming_whisper_api_client \
    --uri "$WYOMING_URI" \
    --whisper-uri "http://${WHISPER_HTTP_HOST}:${WHISPER_HTTP_PORT}" \
    --model-name "$WHISPER_MODEL" \
    --beam-size "$WHISPER_BEAM_SIZE" \
    --language "$WHISPER_LANG"
