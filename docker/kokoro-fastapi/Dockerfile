FROM archlinux

ARG USER_UID
ARG USER_GID
ARG RENDER_GID
ARG VIDEO_GID

# Set the target device (gpu|cpu)
ENV DEVICE="cpu"
ENV USE_GPU="false"

# Kokoro FastAPI specific
ENV PYTHONUNBUFFERED="1"
ENV PYTHONPATH="/home/user/app:/home/user/app/api"
ENV UV_LINK_MODE="copy"

# Decide if you want to download the voice model during installation
ENV DOWNLOAD_MODEL="true"

WORKDIR /home/user/app

# Fix GIDs for groups to match host
RUN groupmod -g ${USER_GID} users
RUN groupmod -g ${RENDER_GID} render
RUN groupmod -g ${VIDEO_GID} video

# Add a user
RUN useradd -u ${USER_UID} -r -g users -G render,video -s /sbin/nologin -m -c "User" user

# Install dependencies
RUN pacman -Syu --noconfirm && pacman -S --noconfirm base-devel espeak-ng ffmpeg git rocm-core sudo vim

# Update paths to include ROCm
ENV ROCM_PATH="/opt/rocm"
ENV PATH="${PATH}:/opt/rocm/bin"

# Allow user to build packages from AUR
RUN echo "user ALL=(ALL) NOPASSWD: /usr/bin/pacman" >> /etc/sudoers

# Prepare the runtime environment
RUN chown -R user:users /home/user

# Prepare directory for AUR
RUN mkdir -p /home/user/aur
RUN chown user:users /home/user/aur
USER user

## Install Python 3.13
WORKDIR /home/user/aur/python313
RUN git clone https://aur.archlinux.org/python313.git /home/user/aur/python313
RUN makepkg -si --noconfirm

# Cleanup
WORKDIR /home/user/app
RUN rm -rf /home/user/aur

# Make python3.13 the default python (requires root)
USER root
RUN ln -sf /usr/bin/python3.13 /usr/local/bin/python
RUN ln -sf /usr/bin/python3.13 /usr/local/bin/python3
USER user

# Kokoro has somewhere hardcoded path to the app, temporary workaround
USER root
RUN ln -s /home/user/app /app
USER user

# Prepare Python virtual environment
RUN python -m venv /home/user/venv
ENV PATH="/home/user/venv/bin:${PATH}"
RUN pip install virtualenv --no-cache-dir
RUN pip install --upgrade pip setuptools GitPython --no-cache-dir

#Install Kokoro FastAPI dependencies
RUN pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/rocm6.4

# Clone Kokoro FastAPI repository and copy scripts requied to run in Docker to the /app directory
RUN git clone https://github.com/remsky/Kokoro-FastAPI.git /home/user/app

RUN cp docker/scripts/* ./
RUN chmod +x ./*.sh

# Fix Spacy version not compatible with Python 3.13
RUN sed -i 's/spacy==3.8.5/spacy==3.8.7/g' /home/user/app/pyproject.toml

# AV 16.0.0 is missing wheel for x86_64
RUN sed -i 's/av>=14.2.0/av==15.1.0/g' /home/user/app/pyproject.toml

# Kokoro FastAPI uses UV
RUN pip install uv --no-cache-dir
RUN uv venv --python 3.13
RUN uv sync --extra ${DEVICE} --no-cache

# Download the voice model if needed
RUN if [ "${DOWNLOAD_MODEL}" = "true" ]; then \
        pip install loguru && \
        python ./download_model.py --output api/src/models/v1_0; \
    fi

# Default port is 8880
CMD ["sh", "./entrypoint.sh"]
