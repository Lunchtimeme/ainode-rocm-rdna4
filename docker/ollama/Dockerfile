# ==============================================================================
# Ollama Container
# ==============================================================================
# Large Language Model inference server with AMD ROCm GPU acceleration.
# Provides the LLM backend for Open WebUI and other clients.
#
# Features:
#   - Ollama with ROCm support for AMD GPUs
#   - Pre-configured for containerized deployment
#   - Disabled command history for privacy
#
# Build args:
#   USER_UID   - UID for the container user (default: 1000)
#   USER_GID   - GID for the users group (default: 100)
#   RENDER_GID - Host's render group GID (for GPU access)
#   VIDEO_GID  - Host's video group GID (for GPU access)
#
# Note: This container uses the official ollama-rocm package from Arch repos,
#       not the base image, as it doesn't require Python.
# ==============================================================================

FROM archlinux

# ------------------------------------------------------------------------------
# Build arguments
# ------------------------------------------------------------------------------
ARG USER_UID=1000
ARG USER_GID=100
ARG RENDER_GID=28
ARG VIDEO_GID=27

# ------------------------------------------------------------------------------
# Ollama environment configuration
# ------------------------------------------------------------------------------
ENV HOME="/home/user"

# Listen on all interfaces (required for Docker networking)
ENV OLLAMA_HOST="0.0.0.0"

# Disable command history for privacy
ENV OLLAMA_NOHISTORY=true

# Use tmpfs for temporary files (mapped in compose.yml)
ENV OLLAMA_TMPDIR="/home/user/tmp"

# ROCm paths
ENV ROCM_PATH="/opt/rocm"
ENV PATH="${PATH}:/opt/rocm/bin"

# ------------------------------------------------------------------------------
# System setup and Ollama installation
# ------------------------------------------------------------------------------
# Single layer for all system setup to minimize image size:
# 1. Fix group GIDs to match host
# 2. Create non-root user with GPU group membership
# 3. Install ollama-rocm and minimal dependencies
# 4. Clean package cache
# ------------------------------------------------------------------------------
RUN groupmod -g ${USER_GID} users \
    && groupmod -g ${RENDER_GID} render \
    && groupmod -g ${VIDEO_GID} video \
    # Create user with GPU group access
    && useradd -u ${USER_UID} -r -g users -G render,video -s /sbin/nologin -m -c "User" user \
    # Install Ollama with ROCm support
    && pacman -Syu --noconfirm \
    && pacman -S --noconfirm \
        ollama-rocm \
        rocm-core \
    # Clean package cache (saves ~500MB)
    && rm -rf /var/cache/pacman/pkg/* \
    && rm -rf /var/lib/pacman/sync/* \
    # Set ownership
    && chown -R user:users /home/user

# ------------------------------------------------------------------------------
# Container startup
# ------------------------------------------------------------------------------
USER user
WORKDIR /home/user

# Ollama runs as a server by default
# Models are stored in /home/user/.ollama (mounted as volume)
ENTRYPOINT ["ollama"]
CMD ["serve"]
