# ==============================================================================
# Hindsight decider
# ==============================================================================
# hs-decide-1-flash on CPU: a 0.8B model that answers typed questions about a
# state in one forward pass (POST /v1/systemone). It replaces a share of the
# memory service's LLM calls with typed judgements.
#
# Why a separate image at all: the vendor serving package needs Python 3.12+,
# while the Hindsight image ships 3.11, so its torch/transformers layers cannot
# be reused. This image is tiny on purpose — no ROCm, no CUDA, no GPU-aware
# torch, because the model is prefill-only and runs well on AVX-512.
#
# Build args (defaults are repository pins; override from .env if needed):
#   TORCH_VERSION         torch CPU wheel to install first
#   TRANSFORMERS_VERSION  transformers release the serving package expects
#   HS_DECIDE_REPO        Hub repository holding the weights and serving code
#   HS_DECIDE_REV         Hub revision (commit) to pin both to
# ==============================================================================

FROM python:3.12-slim

ARG TORCH_VERSION=2.13.0
ARG TRANSFORMERS_VERSION=5.23.0
ARG HS_DECIDE_REPO=hindsight-ai/hs-decide-1-flash
ARG HS_DECIDE_REV=e2c789026dfd1f7608cafb2ef6a9bb31397af802
ARG USER_UID=1000
ARG USER_GID=100

# HS_DECIDE_REV is re-exported so the runtime command pins what the build used.
ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    HF_HOME=/models/hf \
    HS_DECIDE_REV=${HS_DECIDE_REV} \
    TOKENIZERS_PARALLELISM=false

# ------------------------------------------------------------------------------
# CPU torch first, from the CPU index
# ------------------------------------------------------------------------------
# Doing this before anything that depends on torch is the whole trick: the
# default PyPI wheel is the CUDA build and drags in several GB of nvidia-*
# libraries this container can never use.
# ------------------------------------------------------------------------------
RUN --mount=type=cache,target=/root/.cache/pip \
    pip install "torch==${TORCH_VERSION}" --index-url https://download.pytorch.org/whl/cpu

# ------------------------------------------------------------------------------
# The serving package, installed from a pinned Hub revision
# ------------------------------------------------------------------------------
# It is not on PyPI, and it is 44 KB of Apache-2.0 Python, so it is fetched at
# build time from the same commit as the weights. --no-deps keeps pip from
# resolving `vllm` (an optional extra we do not want) or re-resolving torch.
# ------------------------------------------------------------------------------
RUN --mount=type=cache,target=/root/.cache/pip \
    pip install "transformers==${TRANSFORMERS_VERSION}" \
                "pydantic==2.14.4" \
                "huggingface-hub[cli]==2.4.0" \
                "fastapi==0.165.0" \
                "uvicorn==0.54.0" \
    && hf download "${HS_DECIDE_REPO}" --revision "${HS_DECIDE_REV}" \
           --include "serving/*" --local-dir /tmp/hs \
    && pip install --no-deps /tmp/hs/serving \
    && rm -rf /tmp/hs

# ------------------------------------------------------------------------------
# Runtime
# ------------------------------------------------------------------------------
# The weights are not baked in: /models is a bind mount, so a recreate never
# re-downloads 1.5 GiB. The uid/gid match the host user that owns data/, passed
# as build args like every other built service here.
# ------------------------------------------------------------------------------
RUN useradd --uid "${USER_UID}" --gid "${USER_GID}" --create-home \
        --shell /usr/sbin/nologin decider

COPY --chmod=0755 entrypoint.sh /usr/local/bin/entrypoint.sh

USER ${USER_UID}
WORKDIR /home/decider
EXPOSE 8000

# /health does not run a forward pass, so it stays cheap under load. The start
# period covers the first-run weight download on a slow link.
HEALTHCHECK --interval=30s --timeout=6s --start-period=900s --retries=3 \
    CMD python -c "import sys,urllib.request; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8000/health', timeout=5).status == 200 else 1)"

# Weights live in the bind mount, not the image, so a recreate never re-downloads
# 1.5 GiB. The entrypoint fetches them on first start and then serves.
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
