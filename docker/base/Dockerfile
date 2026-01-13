# ==============================================================================
# AINode Base Image
# ==============================================================================
# Arch Linux base image with Python 3.13 pre-installed from AUR.
# This image serves as the foundation for all Python-based services in AINode,
# eliminating redundant Python builds across multiple containers.
#
# Features:
#   - Python 3.13 built from AUR
#   - Common user/group setup for host UID/GID matching
#   - Virtual environment pre-configured
#   - Minimal footprint with cleaned package caches
#
# Build args:
#   USER_UID  - UID for the container user (default: 1000)
#   USER_GID  - GID for the users group (default: 100)
# ==============================================================================

FROM archlinux:base-devel

# ------------------------------------------------------------------------------
# Build arguments for user/group ID matching with host
# ------------------------------------------------------------------------------
ARG USER_UID=1000
ARG USER_GID=100

# ------------------------------------------------------------------------------
# Environment setup
# ------------------------------------------------------------------------------
ENV PYTHONUNBUFFERED=1

# ------------------------------------------------------------------------------
# System setup and Python 3.13 build dependencies
# ------------------------------------------------------------------------------
# Install ALL dependencies needed for Python 3.13 AUR build upfront.
# These are required by the python313 PKGBUILD:
#   - bluez-libs: Bluetooth support
#   - mpdecimal: Decimal module
#   - gdb: Used during build tests
#   - Other standard build deps included in base-devel
#
# We keep the sync database until after Python is built.
# ------------------------------------------------------------------------------
RUN groupmod -g ${USER_GID} users \
    && useradd -u ${USER_UID} -r -g users -s /sbin/nologin -m -c "User" user \
    && echo "user ALL=(ALL) NOPASSWD: /usr/bin/pacman" >> /etc/sudoers \
    # Update system and install Python build dependencies
    && pacman -Syu --noconfirm \
    && pacman -S --noconfirm \
        git \
        # Python 3.13 build dependencies (from AUR PKGBUILD)
        bluez-libs \
        mpdecimal \
        gdb \
        libnsl \
        libxcrypt \
    # Only clean package cache, keep sync database for makepkg
    && rm -rf /var/cache/pacman/pkg/* \
    # Prepare directories
    && mkdir -p /home/user/aur \
    && chown -R user:users /home/user

# ------------------------------------------------------------------------------
# Python 3.13 installation from AUR
# ------------------------------------------------------------------------------
# Building Python from AUR as non-root user.
# makepkg will use sudo to install any additional dependencies it needs.
# ------------------------------------------------------------------------------
USER user
WORKDIR /home/user/aur

RUN git clone --depth 1 https://aur.archlinux.org/python313.git \
    && cd python313 \
    && makepkg -si --noconfirm \
    # Cleanup AUR build artifacts
    && cd /home/user \
    && rm -rf /home/user/aur

# ------------------------------------------------------------------------------
# Final cleanup (after Python is built)
# ------------------------------------------------------------------------------
# Now we can safely remove the sync database, caches, and sudo privileges.
# The sudo rule was only needed for makepkg to install build dependencies.
# ------------------------------------------------------------------------------
USER root
RUN rm -rf /var/lib/pacman/sync/* \
    && rm -rf /var/cache/pacman/pkg/* \
    # Remove sudo privileges - no longer needed after Python build
    && sed -i '/user ALL=(ALL) NOPASSWD: \/usr\/bin\/pacman/d' /etc/sudoers \
    # Make python3.13 the default
    && ln -sf /usr/bin/python3.13 /usr/local/bin/python \
    && ln -sf /usr/bin/python3.13 /usr/local/bin/python3

# ------------------------------------------------------------------------------
# Python virtual environment setup
# ------------------------------------------------------------------------------
USER user
WORKDIR /home/user

RUN python -m venv /home/user/venv

ENV PATH="/home/user/venv/bin:${PATH}"

RUN pip install --no-cache-dir --upgrade pip setuptools

# ------------------------------------------------------------------------------
# Default working directory
# ------------------------------------------------------------------------------
# Create app directory with correct ownership before setting WORKDIR
RUN mkdir -p /home/user/app

WORKDIR /home/user/app
