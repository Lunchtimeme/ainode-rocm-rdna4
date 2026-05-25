# ==============================================================================
# ComfyUI Container
# ==============================================================================
# AI image/video generation backend using ComfyUI with AMD ROCm support.
# Provides the API backend for the ComfyChair Android application.
#
# Features:
#   - ComfyUI with full ROCm 6.4 GPU acceleration
#   - PyTorch with ROCm support
#   - Pre-installed dependencies for common custom nodes
#   - bitsandbytes compiled with ROCm support
#   - bfloat16 support enabled for ROCm 6.4.1+
#
# Build args:
#   RENDER_GID - Host's render group GID (for GPU access)
#   VIDEO_GID  - Host's video group GID (for GPU access)
# ==============================================================================

FROM ainode-base:python313

# ------------------------------------------------------------------------------
# Build arguments for GPU group access
# ------------------------------------------------------------------------------
ARG RENDER_GID=28
ARG VIDEO_GID=27

# ------------------------------------------------------------------------------
# ROCm environment configuration
# ------------------------------------------------------------------------------
ENV ROCM_PATH="/opt/rocm"
ENV PATH="${PATH}:/opt/rocm/bin"

# MIOpen tuning mode (2 = fast, reduces startup time)
# See: https://github.com/ROCm/ROCm/issues/4742
ENV MIOPEN_FIND_MODE="2"

# Enable experimental AOTriton features for better performance
ENV TORCH_ROCM_AOTRITON_ENABLE_EXPERIMENTAL="1"

# ------------------------------------------------------------------------------
# System packages and GPU group setup
# ------------------------------------------------------------------------------
# Install ROCm SDK and required system packages, then fix GPU group GIDs
# to match host system for proper /dev/kfd and /dev/dri access.
# ------------------------------------------------------------------------------
USER root
RUN pacman -Syu --noconfirm \
    && pacman -S --noconfirm \
        ffmpeg \
        git-lfs \
        rocm-hip-sdk \
    # Fix GPU group GIDs to match host
    && groupmod -g ${RENDER_GID} render \
    && groupmod -g ${VIDEO_GID} video \
    # Add user to GPU groups
    && usermod -aG render,video user \
    # Ensure app directory has correct ownership
    && chown -R user:users /home/user/app \
    # Clean package cache
    && rm -rf /var/cache/pacman/pkg/* \
    && rm -rf /var/lib/pacman/sync/*

# ------------------------------------------------------------------------------
# ComfyUI installation
# ------------------------------------------------------------------------------
USER user
WORKDIR /home/user/app

# Initialize Git LFS for model downloads
RUN git lfs install

# Clone ComfyUI repository
RUN git clone --depth 1 https://github.com/comfyanonymous/ComfyUI.git .

# ------------------------------------------------------------------------------
# Python dependencies installation
# ------------------------------------------------------------------------------
# Installing all pip packages in consolidated layers to minimize image size.
# Grouped by: PyTorch -> ComfyUI core -> Node dependencies -> Special builds
# ------------------------------------------------------------------------------

# PyTorch with ROCm 6.4 support (large download, separate layer for caching)
RUN pip install --no-cache-dir \
    torch \
    torchvision \
    torchaudio \
    --index-url https://download.pytorch.org/whl/rocm6.4

# ComfyUI core requirements
RUN pip install --no-cache-dir -r requirements.txt

# Dependencies for popular custom nodes (consolidated into single layer)
# - insightface, facexlib: Face detection/recognition nodes
# - onnxruntime: ONNX model inference
# - opencv: Image processing
# - ffmpeg-python: Video processing
# - accelerate, diffusers: HuggingFace integrations
# - segment_anything, sam2: Segmentation models
# - ultralytics: YOLO models
RUN pip install --no-cache-dir \
    # Face processing
    insightface \
    filterpy \
    # ONNX runtime
    onnxruntime \
    # Image/video processing
    opencv-python-headless \
    ffmpeg-python \
    color-matcher \
    pywavelets \
    # HuggingFace ecosystem
    accelerate \
    diffusers \
    huggingface-hub \
    transformers \
    gguf \
    # ML utilities
    boto3 \
    dill \
    fal_client \
    ftfy \
    imageio-ffmpeg \
    matplotlib \
    piexif \
    pykalman \
    "pydantic>=2.0,<3.0" \
    redis \
    replicate \
    timm \
    ultralytics \
    # Segmentation
    segment_anything

# facexlib requires PEP 517 build
RUN pip install --no-cache-dir --use-pep517 facexlib

# SAM2 from GitHub (not on PyPI)
RUN pip install --no-cache-dir git+https://github.com/facebookresearch/sam2

# ------------------------------------------------------------------------------
# bitsandbytes with ROCm support
# ------------------------------------------------------------------------------
# Building from source with HIP backend for AMD GPU quantization support.
# See: https://huggingface.co/docs/bitsandbytes/main/en/installation#multi-backend
# ------------------------------------------------------------------------------
RUN pip install --no-cache-dir bitsandbytes

# ------------------------------------------------------------------------------
# ROCm bfloat16 patch
# ------------------------------------------------------------------------------
# Enable bfloat16 support for ROCm 6.4.1+
# See: https://github.com/kasper93/ComfyUI/commit/8d3e5acda351f140fc2b653ffe71bdb14e72e045
# ------------------------------------------------------------------------------
RUN sed -i 's/and (not is_amd()) //g' comfy/model_management.py

# ------------------------------------------------------------------------------
# Container startup
# ------------------------------------------------------------------------------
# --listen 0.0.0.0  : Accept connections from any interface (required for Docker)
# --port 8188       : Default ComfyUI port
# --temp-directory  : Use tmpfs for temporary files
# --preview-method  : Enable auto preview generation
# ------------------------------------------------------------------------------
CMD ["python", "./main.py", \
     "--listen", "0.0.0.0", \
     "--port", "8188", \
     "--temp-directory", "/tmp", \
     "--preview-method", "auto"]
