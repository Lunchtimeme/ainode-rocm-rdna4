# ==============================================================================
# Kokoro FastAPI Container
# ==============================================================================
# Text-to-Speech API server using the Kokoro TTS model.
# Provides high-quality voice synthesis via a FastAPI interface.
#
# Features:
#   - Kokoro TTS model with FastAPI wrapper
#   - ROCm GPU support (configurable via DEVICE env)
#   - UV package manager for fast dependency resolution
#   - Optional model pre-download during build
#
# Build args:
#   RENDER_GID - Host's render group GID (for GPU access)
#   VIDEO_GID  - Host's video group GID (for GPU access)
#
# Environment:
#   DEVICE         - Target device: "gpu" or "cpu" (default: cpu)
#   DOWNLOAD_MODEL - Pre-download voice model during build (default: true)
# ==============================================================================

FROM ainode-base:python313

# ------------------------------------------------------------------------------
# Build arguments
# ------------------------------------------------------------------------------
ARG RENDER_GID=28
ARG VIDEO_GID=27

# ------------------------------------------------------------------------------
# Kokoro FastAPI environment configuration
# ------------------------------------------------------------------------------
# Device configuration (gpu|cpu)
ENV DEVICE="cpu"
ENV USE_GPU="false"

# Python settings for containerized execution
ENV PYTHONUNBUFFERED="1"
ENV PYTHONPATH="/home/user/app:/home/user/app/api"

# UV package manager settings
ENV UV_LINK_MODE="copy"

# Model download control - set to "false" to skip model download during build
ENV DOWNLOAD_MODEL="true"

# ROCm paths (used when DEVICE=gpu)
ENV ROCM_PATH="/opt/rocm"
ENV PATH="${PATH}:/opt/rocm/bin"

# ------------------------------------------------------------------------------
# System packages and GPU group setup
# ------------------------------------------------------------------------------
USER root
RUN pacman -Syu --noconfirm \
    && pacman -S --noconfirm \
        espeak-ng \
        ffmpeg \
        rocm-core \
    # Fix GPU group GIDs to match host
    && groupmod -g ${RENDER_GID} render \
    && groupmod -g ${VIDEO_GID} video \
    # Add user to GPU groups
    && usermod -aG render,video user \
    # Kokoro has hardcoded /app path in some places - create symlink as workaround
    && ln -s /home/user/app /app \
    # Ensure app directory has correct ownership
    && chown -R user:users /home/user/app \
    # Clean package cache
    && rm -rf /var/cache/pacman/pkg/* \
    && rm -rf /var/lib/pacman/sync/*

# ------------------------------------------------------------------------------
# Kokoro FastAPI installation
# ------------------------------------------------------------------------------
USER user
WORKDIR /home/user/app

# Clone repository and set up scripts
RUN git clone --depth 1 https://github.com/remsky/Kokoro-FastAPI.git . \
    && cp docker/scripts/* ./ \
    && chmod +x ./*.sh

# ------------------------------------------------------------------------------
# Dependency fixes for Python 3.13 compatibility
# ------------------------------------------------------------------------------
# - spacy 3.8.5 doesn't support Python 3.13, need 3.8.7+
# - av 16.0.0 missing wheel for x86_64, pin to 15.1.0
# ------------------------------------------------------------------------------
RUN sed -i 's/spacy==3.8.5/spacy==3.8.7/g' pyproject.toml \
    && sed -i 's/av>=14.2.0/av==15.1.0/g' pyproject.toml

# ------------------------------------------------------------------------------
# Python dependencies via UV
# ------------------------------------------------------------------------------
# Using UV for faster dependency resolution and installation.
# PyTorch is installed separately first for better layer caching.
# ------------------------------------------------------------------------------
RUN pip install --no-cache-dir \
    torch \
    torchvision \
    torchaudio \
    --index-url https://download.pytorch.org/whl/rocm6.4

# Install UV and sync dependencies
RUN pip install --no-cache-dir uv \
    && uv venv --python 3.13 \
    && uv sync --extra ${DEVICE} --no-cache

# ------------------------------------------------------------------------------
# Model pre-download (optional)
# ------------------------------------------------------------------------------
# Downloads the voice model during build to avoid first-run delays.
# Set DOWNLOAD_MODEL=false to skip this step and download at runtime.
# ------------------------------------------------------------------------------
RUN if [ "${DOWNLOAD_MODEL}" = "true" ]; then \
        pip install --no-cache-dir loguru \
        && python ./download_model.py --output api/src/models/v1_0; \
    fi

# ------------------------------------------------------------------------------
# Container startup
# ------------------------------------------------------------------------------
# Default port: 8880
# ------------------------------------------------------------------------------
CMD ["sh", "./entrypoint.sh"]
