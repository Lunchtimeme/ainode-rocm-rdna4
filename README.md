# AINode (ROCm)

> **About this fork**
> This is a fork of [legal-hkr/ainode-rocm](https://github.com/legal-hkr/ainode-rocm), retargeted for AMD RDNA4 GPUs (tested on RX 9070 XT). The original project targets RDNA3 (RX 7900 XTX / gfx1100); this fork switches the ComfyUI PyTorch ROCm nightly target to `gfx1201` (RX 9070 XT) and adds a SearXNG metasearch service for Open WebUI web search. ComfyUI is pinned to a tested upstream release (see `COMFYUI_REF`), and the stack can optionally serve the ternary Bonsai 2 27B model through the PrismML llama.cpp fork alongside Ollama.

## Description

A self-contained privacy-focused AI stack for interacting with LLMs and Stable Diffusion, leveraging AMD's ROCm toolkit.

## Highlights

A privacy-focused approach is implemented as follows:

*   Telemetry across all components is disabled.
*   Only the primary instance of Open WebUI is authorized to persistently store generated text and images. These can be located within the `data/openwebui/data` directory.
*   The amnesic approach utilizes `tmpfs` for mounting input, output, and cache directories. This configuration necessitates periodic container restarts to prevent excessive RAM consumption.

## Components

This repository contains Docker configuration files for setting up the following components:

*   **Open WebUI:** A versatile web interface for interacting with various AI models.
*   **Ollama:** A backend for Large Language Models (LLMs), providing a simple and efficient way to run and manage models.
*   **Bonsai 2 (optional):** A ternary 27B model served by the PrismML llama.cpp fork, running alongside Ollama on port `8080`. Only active when the binaries and weights are installed; see [Bonsai 2 via PrismML llama-server](#bonsai-2-via-prismml-llama-server).
*   **ComfyUI:** A node-based UI for Stable Diffusion, allowing for complex workflows and customization.
*   **ChromaDB:** A vector database for storing and retrieving embeddings, enabling efficient retrieval-augmented generation (RAG).
*   **Kokoro FastAPI:** A backend for Text-to-Speech (TTS), providing high-quality voice generation.
*   **SearXNG:** A metasearch engine that aggregates results from multiple search engines, used as a web search backend for Open WebUI.
*   **Nginx:** A reverse proxy server, managing incoming requests and routing them to the appropriate backend services.

## Repository Structure

The repository is organized as follows:

*   `docker` - Contains Dockerfiles for all stack components.
*   `docker/llamacpp` - Startup script and router preset for the optional Bonsai 2 server (`start.sh`, `models.ini`). The PrismML binaries are downloaded by the user and ignored by git.
*   `examples` - Contains configuration examples.
*   `compose.yml` - Docker Compose configuration file.

## Prerequisites

*   System with AMD ROCm toolkit installed, the stack was built and tested on Linux.
*   Docker and Docker Compose installed, Podman should work, too.

## Getting Started

Follow these steps to get your AINode stack up and running:

1.  **Clone the repository:**
    ```bash
    git clone https://github.com/Lunchtimeme/ainode-rocm-rdna4.git ainode
    cd ainode
    ```
    This command will download the repository to your local machine. Make sure you have Git installed.

2.  **Create the data directory structure:**
    ```bash
    mkdir -p data/{chroma,comfyui/user,comfyui/custom_nodes,common/models,desktop/home,desktop/home_i3,ollama,openwebui/data,reverseproxy/htpasswd,reverseproxy/sites_enabled,searxng} ssl
    ```

3.  **Place SSL certificates:**
    Copy the `ainode.crt` and `ainode.key` files into the `ssl` directory. These files are used for secure communication via HTTPS. You can generate your own self-signed certificates or use a certificate from a trusted Certificate Authority (CA), example on how to do that can be found in the `examples/ssl` directory. The entire ssl directory is gitignored so your certificates never leave your machine.

4.  **Create Basic Auth credentials for ComfyUI:**
    ```bash
    cd data/reverseproxy/htpasswd
    printf "USERNAME:$(openssl passwd -apr1)\n" >> .htpasswd
    cd ../../../
    ```
    Replace `USERNAME` with your desired username. You'll be prompted to enter the password.

5.  **Review and configure Docker Compose files:**
    The `compose.yml` file defines the services (containers) that make up the stack and how they interact. The `Dockerfile` files in `docker/*` directories contain instructions for building the Docker images for each service. Examine the `compose.yml` and `Dockerfile` files to understand the stack's configuration, mainly the reverse proxy configuration in the `data/reverseproxy/sites-enabled` directory. Some examples can be found in the `examples/reverseproxy` directory. You should also set UIDs and GIDs in the `compose.yml` according to your environment. Also, make sure that `ENABLE_SIGNUP` in the `docker/openwebui/Dockerfile` is initially set to `true` so you can create the admin account. You can change it to `false` afterwards.

    If you want to use the SearXNG metasearch service, copy `examples/searxng/settings.yml` to `data/searxng/settings.yml` and replace `CHANGE_ME_TO_A_RANDOM_SECRET_KEY` with a strong secret before starting the stack.

6.  **Build and run the stack:**
    Navigate to the repository directory and start the Docker containers:
    ```bash
    # 1. Build the base image first (required)
    docker build -t ainode-base:python313 ./docker/base

    # 2. Build all services
    docker compose build

    # 3. Start the stack
    docker compose up -d
    ```
    The `-d` flag runs the containers in detached mode (in the background). It is highly suggested to run the stack without `-d` at first to monitor the startup process.

7.  **Access the interfaces:**
    *   The standard Open WebUI interface will be accessible via port `443` (HTTPS).
    *   The Amnesic Open WebUI interface will be accessible via port `8443` (HTTPS).
    *   The Ollama API will be accessible on the standard port `11434`.
    *   The SearXNG metasearch engine is reachable internally at `http://ainode-searxng:8080`.
    
    You can access these interfaces using your web browser or with tools like `curl` or `Postman`.

    To access ComfyUI and Kokoro FastAPI WebUI, you must properly set your DNS configuration or `/etc/hosts` file to reflect the configuration in the `data/reverseproxy/sites-enabled` directory. If you're running AINode on localhost, you can add the following to your `/etc/hosts` file:
    ```configuration
    127.0.0.1   comfyui.localdomain             comfyui
    127.0.0.1   ollama.localdomain              ollama
    127.0.0.1   openwebui.localdomain           openwebui
    127.0.0.1   openwebui-amnesic.localdomain   openwebui-amnesic
    127.0.0.1   kokoro-fastapi.localdomain      kokoro-fastapi
    ```
    With this setup, you can access the components by using the specified hostname in your URL, e.g., `https://comfyui`, `https://openwebui`, etc.

8.  **Configure service URLs in Open WebUI:**
    Once the stack is up and running, log into Open WebUI and add the internal service endpoints through the web GUI:
    *   **SearXNG (web search):** `http://ainode-searxng:8080`
    *   **ComfyUI (image generation):** `http://ainode-comfyui:8188`
    *   **Ollama (LLM backend):** `http://ainode-ollama:11434`
    *   **Bonsai 2 (optional, if installed):** `http://ainode-ollama:8080/v1`

## Bonsai 2 via PrismML llama-server

The `ollama` container can serve [Bonsai 2 27B](https://huggingface.co/prism-ml/Ternary-Bonsai-2-27B-gguf) in addition to Ollama: a 27B-class reasoning model stored in ternary weights (~7.2 GB on disk instead of ~54 GB at FP16). The ternary packings are loaded by the PrismML build of `llama-server`, which runs as a second, OpenAI-compatible endpoint on port `8080` next to Ollama on `11434`.

Neither the binaries nor the weights are part of this repository. Both are downloaded by you and are ignored by git.

### Why share the Ollama container

Both servers share the GPU, but only one of them holds VRAM at a time in practice: Bonsai is loaded when a request arrives and released again after `sleep-idle-seconds` (120 s by default), so ComfyUI or an Ollama model gets the VRAM back without restarting anything. If the binaries or model files are missing, `start.sh` skips Bonsai and starts Ollama as usual, so this is safe to leave enabled.

### 1. Binaries

Download a Linux x86_64 build of the PrismML llama.cpp fork for your backend from the [PrismML llama.cpp instructions](https://docs.prismml.com/run/llamacpp) (a ROCm build is used here, tested with build `b10831`) and extract it into `docker/llamacpp/`:

```bash
cd docker/llamacpp
tar -xf llama-prism-bin-ubuntu-rocm-7.2-x64.tar.gz   # use the archive you downloaded
ls                                                   # -> llama-prism-<build>/, models.ini, start.sh
```

`start.sh` locates `llama-server` by itself (newest `llama-prism-*` directory, or `PRISM_SERVER=/path/to/llama-server`), so the directory name is irrelevant.

### 2. Weights

Put the GGUF pack and the optional vision projector into `data/common/models/bonsai/`:

```
data/common/models/bonsai/
├── Ternary-Bonsai-2-27B-Uncensored-Heretic-PQ2_0.gguf   # ternary pack, ~7.2 GB
└── mmproj-Q8_0.gguf                                     # vision tower, ~0.6 GB
```

`data/common/models` is mounted as `/models` inside the container, so those files are `/models/bonsai/...`. Upstream packs are named `Ternary-Bonsai-2-27B-PQ2_0.gguf` and `Ternary-Bonsai-2-27B-mmproj-Q8_0.gguf`; a fine-tune with the same packing works the same way, point `models.ini` at it.

### 3. Configuration

`docker/llamacpp/models.ini` is a `llama-server` router preset: `[*]` holds the shared defaults and every `[section]` becomes a model id. The shipped defaults target a 16 GB card:

```ini
[*]
n-gpu-layers = 99
ctx-size = 131072
cache-type-k = q8_0
cache-type-v = q8_0
flash-attn = true
sleep-idle-seconds = 120
```

The section name (`[bonsai2-27b-heretic]`) is what Open WebUI lists, rename it freely. Editing the preset needs no rebuild, the directory is mounted read-only at `/opt/prism`; just restart the container:

```bash
docker compose restart ollama
docker exec ainode-ollama tail -f /tmp/prism-server.log
```

### 4. Connect it

In Open WebUI, add an OpenAI-compatible connection pointing at `http://ainode-ollama:8080/v1` (Settings → Connections). From the host the port is not published; reach it through the stack or add a mapping to the `ollama` service if you want direct access.

Disable it at any time with `PRISM_ENABLE=0` in the environment of the `ollama` service, or by removing the binaries. `start.sh` always ends with `exec ollama serve`, so the container never loses its LLM backend.

## Updating ComfyUI

ComfyUI is pinned to one tested upstream release so that rebuilds are reproducible. The version appears in exactly two places, keep them in sync:

* `COMFYUI_REF` in `docker/comfyui/Dockerfile` (used by `git clone --branch`)
* the `image:` tag of the `comfyui` service in `compose.yml`

Both are currently `v0.44.0`.

A full `docker compose build comfyui` re-downloads the PyTorch ROCm nightly layer (6.8 GB) and the custom-node dependency layers (~2.9 GB) whenever the ComfyUI checkout changes, because the clone runs before the pip layers in that Dockerfile. For a bump that only needs ComfyUI itself, use the overlay instead: it keeps the existing image and replaces only the checkout plus the pip packages the release pins (typically 50-300 MB).

```bash
# build the thin overlay on top of the image you are running now
docker build -f docker/comfyui/Dockerfile.update \
    --build-arg BASE_IMAGE=ainode-comfyui:0.44.0 \
    --build-arg COMFYUI_REF=v0.45.0 \
    -t ainode-comfyui:0.45.0 ./docker/comfyui

# point compose.yml at the new tag, then recreate only that container
docker compose up -d --no-deps comfyui
```

`Dockerfile.update` keeps `PIP_CONSTRAINT` from the base image, so the ROCm PyTorch build cannot be replaced by the pip run. Verify the result with:

```bash
docker exec ainode-comfyui /home/user/venv/bin/python -c "import comfyui_version; print(comfyui_version.__version__)"
```

Keep the previous tag around until the new one has produced an image, that is your rollback: put the old tag back into `compose.yml` and `docker compose up -d --no-deps comfyui`.
