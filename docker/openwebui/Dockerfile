# ==============================================================================
# Open WebUI Container
# ==============================================================================
# Web interface for interacting with Ollama and other LLM backends.
# Provides chat interface, RAG capabilities, and document processing.
#
# Features:
#   - Open WebUI with Ollama integration
#   - ChromaDB for vector storage (external service)
#   - Whisper for speech-to-text
#   - RAG with configurable embedding models
#   - Multi-stage build for smaller final image
#
# Build stages:
#   1. frontend-builder: Builds the SvelteKit frontend
#   2. runtime: Final image with backend and pre-built frontend
#
# Build args:
#   USER_UID - UID for the container user (default: 1000)
#   USER_GID - GID for the users group (default: 100)
# ==============================================================================

# ==============================================================================
# Stage 1: Frontend Builder
# ==============================================================================
# Builds the SvelteKit frontend. This stage is discarded after build,
# keeping npm and node_modules out of the final image.
# ==============================================================================
FROM archlinux AS frontend-builder

# Install Node.js for frontend build
RUN --mount=type=cache,target=/var/cache/pacman/pkg pacman -Syu --noconfirm \
    && pacman -S --noconfirm git npm

WORKDIR /build
ENV NODE_OPTIONS="--max-old-space-size=8192"
# Open WebUI revision to build: a tag (v0.13.3) or a commit id both work.
# Default = the commit this stack was built and tested against; override it in
# .env with AINODE_OWUI_REF. Keep in sync with compose.yml.
ARG AINODE_OWUI_REF=f8ae8a6c328946dc62cd0712961a0632574581bf
# Build the frontend from that exact revision (the ref now drives cache
# invalidation, so there is no CACHEBURST knob any more).
RUN git init -q . \
    && git remote add origin https://github.com/open-webui/open-webui.git \
    && git fetch -q --depth 1 origin "${AINODE_OWUI_REF}" \
    && git checkout -q FETCH_HEAD \
    # "--force" workaround for dependency resolution issue
    # See: https://github.com/open-webui/open-webui/issues/15880
    && npm ci --force \
    && npm run build


# ==============================================================================
# Stage 2: Runtime
# ==============================================================================
# Final image with Python backend and pre-built frontend assets.
# ==============================================================================
FROM ainode-base:python313 AS runtime

# ------------------------------------------------------------------------------
# Build arguments
# ------------------------------------------------------------------------------
ARG USER_UID=1000
ARG USER_GID=100

# ------------------------------------------------------------------------------
# Open WebUI environment configuration
# ------------------------------------------------------------------------------
ENV ENV="prod"
# WEBUI_SECRET_KEY is supplied at runtime by compose.yml from .env. It used to be
# declared empty here, which both hid the knob and tripped the
# SecretsUsedInArgOrEnv lint; image ENV would lose to runtime env anyway.

# Model storage paths
ENV HF_HOME="/home/user/app/backend/data/embedding/models"
ENV SENTENCE_TRANSFORMERS_HOME="/home/user/app/backend/data/embedding/models"

# Tokenizer settings
ENV TIKTOKEN_ENCODING_NAME="cl100k_base"
ENV TIKTOKEN_CACHE_DIR="/home/user/app/backend/data/cache/tiktoken"

# LLM Backend (Ollama)
ENV OLLAMA_BASE_URL="http://ainode-ollama:11434"
ENV OPENAI_API_BASE_URL=""
ENV OPENAI_API_KEY=""

# Disable telemetry
ENV SCARF_NO_ANALYTICS="true"
ENV DO_NOT_TRACK="true"
ENV ANONYMIZED_TELEMETRY="false"

# Whisper speech-to-text settings
ENV WHISPER_MODEL="base"
ENV WHISPER_MODEL_DIR="/home/user/app/backend/data/whisper/models"

# RAG configuration
ENV RAG_EMBEDDING_MODEL="sdadas/stella-pl-retrieval"
ENV RAG_RERANKING_MODEL="sdadas/polish-reranker-roberta-v2"

# ChromaDB connection (external service)
ENV CHROMA_HTTP_HOST="ainode-chroma"
ENV CHROMA_HTTP_PORT="8000"
ENV CHROMA_HTTP_HEADERS="User-Agent=OpenWebUI"
ENV CHROMA_HTTP_SSL=false

# Authentication settings
ENV DEFAULT_USER_ROLE="admin"
ENV ENABLE_SIGNUP="true"
ENV WEBUI_AUTH="true"

# ------------------------------------------------------------------------------
# System packages
# ------------------------------------------------------------------------------
USER root
RUN --mount=type=cache,target=/var/cache/pacman/pkg pacman -Syu --noconfirm \
    && pacman -S --noconfirm \
        apache \
        ffmpeg \
        sqlite \
    # Ensure app directory has correct ownership
    && chown -R user:users /home/user/app \
    # Clean package cache
    && rm -rf /var/lib/pacman/sync/*

# ------------------------------------------------------------------------------
# Open WebUI installation
# ------------------------------------------------------------------------------
USER user
WORKDIR /home/user/app

# Backend code only; the frontend comes from the builder stage. Same revision
# as above, so both stages always agree.
ARG AINODE_OWUI_REF=f8ae8a6c328946dc62cd0712961a0632574581bf
RUN git init -q . \
    && git remote add origin https://github.com/open-webui/open-webui.git \
    && git fetch -q --depth 1 origin "${AINODE_OWUI_REF}" \
    && git checkout -q FETCH_HEAD

# Disable telemetry user ID (set to zeros even with telemetry disabled)
RUN mkdir -p .cache/chroma \
    && echo -n 00000000-0000-0000-0000-000000000000 > .cache/chroma/telemetry_user_id

# ------------------------------------------------------------------------------
# Python dependencies
# ------------------------------------------------------------------------------
# PyTorch CPU-only (Open WebUI doesn't need GPU for inference)
RUN --mount=type=cache,target=/home/user/.cache/pip pip install \
    torch \
    torchvision \
    torchaudio \
    --index-url https://download.pytorch.org/whl/cpu

# Fix rapidocr-onnxruntime version matching issue
RUN sed -i 's/rapidocr-onnxruntime==1.4.4/rapidocr-onnxruntime/g' backend/requirements.txt

# Install backend dependencies
RUN --mount=type=cache,target=/home/user/.cache/pip pip install -r backend/requirements.txt

# Fix for Python 3.13: audioop module deprecated
# See: https://github.com/jiaaro/pydub/issues/725#issuecomment-2439291764
RUN --mount=type=cache,target=/home/user/.cache/pip pip install audioop-lts hf_xet

# ------------------------------------------------------------------------------
# Pre-download models (reduces first-run time)
# ------------------------------------------------------------------------------
# Download embedding model for RAG
RUN python -c "import os; from sentence_transformers import SentenceTransformer; SentenceTransformer(os.environ['RAG_EMBEDDING_MODEL'], device='cpu')"

# Download Whisper model for speech-to-text
RUN python -c "import os; from faster_whisper import WhisperModel; WhisperModel(os.environ['WHISPER_MODEL'], device='cpu', compute_type='int8', download_root=os.environ['WHISPER_MODEL_DIR'])"

# Download tiktoken encoding
RUN python -c "import os; import tiktoken; tiktoken.get_encoding(os.environ['TIKTOKEN_ENCODING_NAME'])"

# ------------------------------------------------------------------------------
# Copy pre-built frontend from builder stage
# ------------------------------------------------------------------------------
COPY --from=frontend-builder --chown=user:users /build/build ./build

# ------------------------------------------------------------------------------
# Container startup
# ------------------------------------------------------------------------------
CMD ["sh", "./backend/start.sh"]
