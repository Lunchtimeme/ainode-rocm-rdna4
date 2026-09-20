# ==============================================================================
# ComfyUI Container
# ==============================================================================
# AI image/video generation backend using ComfyUI with AMD ROCm support.
# Provides the API backend for the ComfyChair Android application.
#
# Features:
#   - ComfyUI with ROCm 10.2 nightly GPU acceleration (Dynamic VRAM support)
#   - PyTorch with ROCm support (pip-based ROCm from AMD's whl-next nightly index)
#   - Pre-installed dependencies for common custom nodes
#   - bitsandbytes (quantization)
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
# ROCm libraries come from pip packages (TheRock), there is no system ROCm under /opt/rocm
# Do not set PYTORCH_HIP_ALLOC_CONF=expandable_segments:True - it breaks generation with Dynamic VRAM (HIP out of memory during VAE decode) and makes it slower

# MIOpen tuning mode (2 = fast, reduces startup time)
# See: https://github.com/ROCm/ROCm/issues/4742
ENV MIOPEN_FIND_MODE="2"

# Enable experimental AOTriton features for better performance
ENV TORCH_ROCM_AOTRITON_ENABLE_EXPERIMENTAL="1"

# ------------------------------------------------------------------------------
# System packages and GPU group setup
# ------------------------------------------------------------------------------
# Install system packages, then fix GPU group GIDs to match host system for
# proper /dev/kfd and /dev/dri access.
# ------------------------------------------------------------------------------
USER root
RUN pacman -Syu --noconfirm \
    && pacman -S --noconfirm \
        ffmpeg \
        git-lfs \
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

# PyTorch with ROCm 10.2 nightly from AMD's whl-next index (large download, separate layer for caching)
# Nightly instead of stable 7.14.1: the bundled ROCR 1.21 in 7.14.x wheels keeps one CPU core at 100% (ROCm/TheRock#7051), reportedly fixed in newer nightlies
# Stable fallback: "torch[device-gfx1100]==2.12.0+rocm7.14.1" "torchvision==0.27.0+rocm7.14.1" "torchaudio==2.11.0+rocm7.14.1" from https://repo.amd.com/rocm/whl-multi-arch/
# device-gfx1100 = RX 7900 XTX; PyPI stays as extra index for the regular dependencies
RUN pip install --no-cache-dir --pre \
    "torch[device-gfx1100]==2.15.0a0+rocm10.2.0a20260918" \
    "torchvision==0.30.0a0+rocm10.2.0a20260918" \
    "torchaudio==2.11.0.3+rocm10.2.0a20260918" \
    --index-url https://nightly.repo.amd.com/rocm/whl-next/ \
    --extra-index-url https://pypi.org/simple

# Keep later pip installs from replacing the ROCm build of PyTorch
RUN pip freeze | grep -i -E '^(torch|torchvision|torchaudio|triton)==' > /home/user/torch-constraints.txt
ENV PIP_CONSTRAINT="/home/user/torch-constraints.txt"

# ComfyUI core requirements
RUN pip install --no-cache-dir -r requirements.txt

# Dependencies for popular custom nodes (consolidated into single layer)
# - comfyui-manager: Node Manager
# - insightface, facexlib: Face detection/recognition nodes
# - onnxruntime: ONNX model inference
# - opencv: Image processing
# - ffmpeg-python: Video processing
# - accelerate, diffusers: HuggingFace integrations
# - segment_anything, sam2: Segmentation models
# - ultralytics: YOLO models
RUN pip install --no-cache-dir \
    # Node Manager
    comfyui-manager \
    matrix-nio \
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

# bitsandbytes with ROCm support
RUN pip install --no-cache-dir bitsandbytes

# ------------------------------------------------------------------------------
# Container startup
# ------------------------------------------------------------------------------
# --listen 0.0.0.0       : Accept connections from any interface (required for Docker)
# --port 8188            : Default ComfyUI port
# --temp-directory       : Use tmpfs for temporary files
# --preview-method       : Enable auto preview generation
# --async-offload        : Overlap weight offloading with computation (2 streams)
# --enable-dynamic-vram  : Load model weights on demand, spilling to RAM when VRAM runs out
# --fast-disk            : Disk-backed dynamic loading and offload over unpinned RAM (helps with fast NVMe)
# ------------------------------------------------------------------------------
CMD ["python", "./main.py", \
     "--listen", "0.0.0.0", \
     "--port", "8188", \
     "--temp-directory", "/tmp", \
     "--preview-method", "auto", \
     "--async-offload", \
     "--enable-dynamic-vram", \
     "--fast-disk", \
     "--enable-manager"]
