#!/bin/sh
# ==============================================================================
# Ollama + Bonsai 2 startup script
# ==============================================================================
# Starts the optional Bonsai 2 router in the background and keeps Ollama in the
# foreground as PID 1.
#
# The Bonsai server is skipped cleanly (Ollama still starts) when:
#   - PRISM_ENABLE=0 is set in the environment, or
#   - no llama-server binary is found under /opt/prism, or
#   - /opt/prism/models.ini is missing.
#
# Layout expected inside the container (/opt/prism is bind-mounted from
# docker/llamacpp in the repository, the model files come from /models):
#
#   /opt/prism/start.sh          this script
#   /opt/prism/models.ini        router preset (model paths under /models)
#   /opt/prism/llama-prism-*/    extracted PrismML llama.cpp build
#                                  llama-server + libggml*/libllama* + /opt/rocm/lib
#
# Override the binary location with PRISM_SERVER=/path/to/llama-server.
# ==============================================================================

set -u

LOG=/tmp/prism-server.log
: > "$LOG"

start_bonsai() {
    if [ -n "${PRISM_SERVER:-}" ]; then
        server="$PRISM_SERVER"
    else
        # Several builds may be extracted side by side; use the newest one.
        server=$(find /opt/prism -maxdepth 3 -type f -name llama-server 2>/dev/null | sort | tail -n 1)
    fi

    if [ -z "$server" ] || [ ! -x "$server" ]; then
        echo "no llama-server binary under /opt/prism - Bonsai server disabled" >> "$LOG"
        return 0
    fi
    if [ ! -f /opt/prism/models.ini ]; then
        echo "no /opt/prism/models.ini - Bonsai server disabled" >> "$LOG"
        return 0
    fi

    server_dir=$(dirname "$server")
    echo "starting $(basename "$server_dir")/llama-server" >> "$LOG"

    # The PrismML build links against the shared libraries in its own directory
    # and the ROCm runtime shipped inside the image.
    LD_LIBRARY_PATH="$server_dir:/opt/rocm/lib" \
        "$server" \
        --models-preset /opt/prism/models.ini \
        --port 8080 \
        --host 0.0.0.0 \
        --no-webui \
        >> "$LOG" 2>&1 &
}

if [ "${PRISM_ENABLE:-1}" = "0" ]; then
    echo "PRISM_ENABLE=0 - Bonsai server disabled" >> "$LOG"
else
    start_bonsai
fi

# keep Ollama in the foreground as PID 1
exec /usr/bin/ollama serve
