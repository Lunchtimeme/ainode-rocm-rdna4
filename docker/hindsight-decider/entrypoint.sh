#!/bin/sh
# Fetch the weights once, then serve. The download is resumable, so a killed
# first start continues where it stopped instead of starting over.
set -eu

MODEL_DIR="${HS_DECIDE_MODEL_DIR:-/models/hs-decide-1-flash}"
REV="${HS_DECIDE_REV:-main}"
MARKER="$MODEL_DIR/.revision"

# One file is not proof of a complete download: a kill between files leaves
# model.safetensors behind and no tokenizer, which the server only rejects at
# load time (restart loop). The marker keeps a changed HS_DECIDE_REV from being
# served silently out of the old directory.
need_fetch=0
for f in model.safetensors config.json tokenizer.json; do
    [ -f "$MODEL_DIR/$f" ] || need_fetch=1
done
if [ -f "$MARKER" ] && [ "$(cat "$MARKER")" != "$REV" ]; then
    echo "hindsight-decider: weights are at $(cat "$MARKER"), image pins $REV" >&2
    need_fetch=1
fi

if [ "$need_fetch" = 1 ]; then
    echo "hindsight-decider: fetching $(basename "$MODEL_DIR") at $REV"
    # --local-dir gives a plain folder the server can load without a hub lookup,
    # and resumes from .cache/huggingface/download inside it.
    hf download "${HS_DECIDE_REPO:-hindsight-ai/hs-decide-1-flash}" \
        --revision "$REV" \
        --local-dir "$MODEL_DIR"
    printf '%s' "$REV" > "$MARKER"
else
    echo "hindsight-decider: using weights in $MODEL_DIR"
fi

# bfloat16 is 2x faster than torch's float32 CPU default on Zen 5; float32 needs
# 3.3 GB instead of 0.6 GB, so the compose memory cap has to grow with it.
exec hindsight-decision-serve-transformers "$MODEL_DIR" \
    --host 0.0.0.0 \
    --port 8000 \
    --device cpu \
    --dtype "${HS_DECIDE_DTYPE:-float32}" \
    --max-request-tokens "${HS_DECIDE_MAX_REQUEST_TOKENS:-7168}"
