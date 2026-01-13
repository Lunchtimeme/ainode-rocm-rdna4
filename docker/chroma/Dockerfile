# ==============================================================================
# ChromaDB Container
# ==============================================================================
# Vector database for storing and querying embeddings.
# Used by Open WebUI for RAG (Retrieval-Augmented Generation).
#
# Features:
#   - ChromaDB with persistent storage
#   - gRPC and REST API support
#   - Multi-stage build to exclude Rust toolchain from final image
#   - Telemetry disabled
#
# Build stages:
#   1. builder: Compiles ChromaDB with Rust/maturin
#   2. runtime: Final image with only Python runtime
#
# Build args:
#   USER_UID        - UID for the container user (default: 1000)
#   USER_GID        - GID for the users group (default: 100)
#   CHROMADB_VERSION - ChromaDB version to build (default: 0.6.3)
#   REBUILD_HNSWLIB  - Force rebuild of hnswlib (default: false)
# ==============================================================================

# ==============================================================================
# Stage 1: Builder
# ==============================================================================
# Compiles ChromaDB's Rust components. Rust toolchain (~1GB) is not included
# in the final image.
# ==============================================================================
FROM ainode-base:python313 AS builder

ARG CHROMADB_VERSION=0.6.3
ARG REBUILD_HNSWLIB=false

# Install Rust and build dependencies
USER root
RUN pacman -Syu --noconfirm \
    && pacman -S --noconfirm \
        protobuf \
        rust \
    # Create build directory with correct ownership
    && mkdir -p /home/user/build \
    && chown -R user:users /home/user/build \
    && rm -rf /var/cache/pacman/pkg/*

USER user
WORKDIR /home/user/build

# Clone ChromaDB at specified version
RUN git clone --depth 1 --branch ${CHROMADB_VERSION} \
    https://github.com/chroma-core/chroma.git .

# Install build dependencies
RUN pip install --no-cache-dir \
    cffi \
    fastapi \
    maturin \
    opentelemetry-instrumentation \
    opentelemetry-instrumentation-fastapi \
    patchelf

# Install ChromaDB Python dependencies
RUN pip install --no-cache-dir -r requirements.txt

# Conditionally rebuild hnswlib (needed for some architectures)
RUN if [ "${REBUILD_HNSWLIB}" = "true" ]; then \
        pip install --no-cache-dir --no-binary :all: --force-reinstall chroma-hnswlib; \
    fi

# Install gRPC dependencies
RUN pip install --no-cache-dir grpcio grpcio-tools

# Build protobuf files and install ChromaDB
RUN make -C idl proto_python \
    && pip uninstall chromadb -y || true \
    && pip install --no-cache-dir --find-links target/wheels/ chromadb


# ==============================================================================
# Stage 2: Runtime
# ==============================================================================
# Minimal runtime image without Rust toolchain or build artifacts.
# ==============================================================================
FROM ainode-base:python313 AS runtime

ARG USER_UID=1000
ARG USER_GID=100

# ------------------------------------------------------------------------------
# ChromaDB environment configuration
# ------------------------------------------------------------------------------
# Disable telemetry
ENV ANONYMIZED_TELEMETRY="false"

# Enable persistent storage
ENV IS_PERSISTENT="true"
ENV PERSIST_DIRECTORY="/home/user/app/chroma"

# ------------------------------------------------------------------------------
# Copy installed packages from builder
# ------------------------------------------------------------------------------
# Copy the entire venv with all installed packages
COPY --from=builder --chown=user:users /home/user/venv /home/user/venv

# ------------------------------------------------------------------------------
# Application setup
# ------------------------------------------------------------------------------
USER user
WORKDIR /home/user/app

# Clone ChromaDB for config files and scripts (minimal clone)
RUN git clone --depth 1 https://github.com/chroma-core/chroma.git .

# Disable telemetry user ID (set to zeros even with telemetry disabled)
RUN mkdir -p .cache/chroma \
    && echo -n 00000000-0000-0000-0000-000000000000 > .cache/chroma/telemetry_user_id

# ------------------------------------------------------------------------------
# Container startup
# ------------------------------------------------------------------------------
# uvicorn settings:
#   --workers 1      : Single worker (sufficient for most use cases)
#   --host 0.0.0.0   : Accept connections from any interface
#   --port 8000      : Default ChromaDB port
#   --proxy-headers  : Trust X-Forwarded-* headers from reverse proxy
#   --reload         : Auto-reload on code changes (development)
#   --timeout-keep-alive : Keep connections alive for 30 seconds
# ------------------------------------------------------------------------------
ENTRYPOINT ["uvicorn", "chromadb.app:app"]
CMD ["--workers", "1", \
     "--host", "0.0.0.0", \
     "--port", "8000", \
     "--proxy-headers", \
     "--reload", \
     "--log-config", "/home/user/app/chromadb/log_config.yml", \
     "--timeout-keep-alive", "30"]
