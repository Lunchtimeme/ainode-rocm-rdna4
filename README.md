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

9.  **Optional: serve Bonsai 2 next to Ollama:**
    If you want the ternary 27B model as a second endpoint, follow [Bonsai 2 via PrismML llama-server](#bonsai-2-via-prismml-llama-server). It needs the PrismML binaries extracted into `docker/llamacpp/`, the GGUF pack and its vision projector in `data/common/models/bonsai/`, and one entry in `docker/llamacpp/models.ini`. Ollama alone keeps working if you skip it.

## Bonsai 2 via PrismML llama-server

[Bonsai 2 27B](https://huggingface.co/prism-ml/Ternary-Bonsai-2-27B-gguf) is a 27B-class reasoning model: Qwen 3.8 27B compressed to ternary weights, ~7.2 GB instead of ~54 GB at FP16. The `ollama` container serves it through the PrismML build of `llama-server` as a second, OpenAI-compatible endpoint on port `8080`, next to Ollama on `11434`. It has no container of its own - the binaries are bind-mounted from `docker/llamacpp` and `start.sh` starts both processes in the Ollama container.

### Why a separate server is needed

Ollama cannot load these weights. The ternary packings use the GGML tensor types `142` (`PQ2_0`) and `143` (`PTQ1_0`), which the llama.cpp engine bundled in Ollama does not implement. With `ollama-rocm` 0.32.0 (the Arch package version installed when this image was built) the import fails immediately:

```console
$ ollama create bonsai -f Modelfile      # Modelfile: FROM /models/bonsai/...PQ2_0.gguf
parsing GGUF
Error: tensor "output.weight" size overflow
```

Upstream tracks this in [ggml-org/llama.cpp#29058](https://github.com/ggml-org/llama.cpp/issues/29058), where Ollama 0.34.2 is also reported to still have no size handling for types 142/143. There is a `Q2_0` pack of the same model (stock llama.cpp types, ~7.6 GB) that upstream llama.cpp can load from build `b11556` onward, but that requires an engine built from `b11556` or newer - and an older engine loads it *without warning* and produces incoherent text. Ollama bundles its own engine, so until it ships one that new, the PrismML `llama-server` is the working route.

Everything below is optional. Without the binaries and the weights, `start.sh` skips Bonsai and starts Ollama alone, so the `entrypoint` in `compose.yml` can stay as it is.

### 1. Binaries

Download a Linux x86_64 build of the PrismML llama.cpp fork for your backend from the [PrismML llama.cpp instructions](https://docs.prismml.com/run/llamacpp) (a ROCm build is used here, tested with build `b10831`) and extract it into `docker/llamacpp/`:

```bash
cd docker/llamacpp
tar -xf llama-prism-bin-ubuntu-rocm-7.2-x64.tar.gz   # use the archive you downloaded
ls                                                   # -> llama-prism-<build>/, models.ini, start.sh
```

The binaries are not part of this repository and are git-ignored. `start.sh` locates `llama-server` by itself (newest `llama-prism-*` directory, or `PRISM_SERVER=/path/to/llama-server`), so the directory name is irrelevant.

### 2. Weights

Save the GGUF pack and the optional vision projector under `data/common/models/bonsai/`, which is `/models` inside the container:

```bash
mkdir -p data/common/models/bonsai
mv ~/Downloads/Ternary-Bonsai-2-27B-*.gguf data/common/models/bonsai/
```

```
data/common/models/bonsai/
├── Ternary-Bonsai-2-27B-Uncensored-Heretic-PQ2_0.gguf   # ternary pack, ~7.2 GB
└── mmproj-Q8_0.gguf                                     # vision tower, ~0.6 GB
```

The upstream packs are named `Ternary-Bonsai-2-27B-PQ2_0.gguf` (language model) and `Ternary-Bonsai-2-27B-mmproj-Q8_0.gguf` (vision). A fine-tune with the same packing, like the one above, works the same way. Inside the container those files are `/models/bonsai/...`; `data/common/models` is git-ignored, so the weights never end up in the repository.

### 3. Register the model

Placing a file in the folder is **not** enough. `start.sh` starts the router with `--models-preset /opt/prism/models.ini`, so every `[section]` in that file is exactly one model, and the section name is the model id clients see. Add a section for the pack you downloaded, or edit the one that ships with the repository:

```ini
[bonsai2-27b-heretic]
model = /models/bonsai/Ternary-Bonsai-2-27B-Uncensored-Heretic-PQ2_0.gguf
mmproj = /models/bonsai/mmproj-Q8_0.gguf
```

`model` is the only required key. Drop `mmproj` if you do not need image input, and rename the section freely - that name is what shows up in Open WebUI. The `[*]` block above the sections applies to all of them: context size, KV cache type, sampling and `sleep-idle-seconds`.

The folder is not scanned automatically: the router has a `--models-dir` mode for that, but this stack uses the preset because it carries the per-model settings and the vision projector. The directory is mounted read-only at `/opt/prism`, so a change needs a container restart, not a rebuild:

```bash
docker compose restart ollama
docker exec ainode-ollama tail -n 20 /tmp/prism-server.log     # shows the preset it loaded
docker exec ainode-ollama curl -s http://127.0.0.1:8080/v1/models
```

### 4. Connect it to Open WebUI

The router speaks the OpenAI chat-completions API, so it is added as a second provider next to the existing Ollama connection - both listings appear in the same model selector:

1.  **Admin Panel -> Settings -> Connections -> +** (Add Connection).
2.  **Type:** `OpenAI`. **Base URL:** `http://ainode-ollama:8080/v1`. **API key:** empty, the router has no authentication; some Open WebUI versions insist on a value, any placeholder works.
3.  Save, then refresh the model list. `bonsai2-27b-heretic` (or whatever you called the section) is selectable alongside the Ollama models.

The endpoint is only reachable from inside the stack; no host port is published. Add a mapping to the `ollama` service if you want to call it from the host or from another machine.

### 5. VRAM is shared - you manage it

Bonsai, Ollama and ComfyUI all use the same GPU. The router loads a model on the first request and releases it after `sleep-idle-seconds` (120 s by default), which is the only automatic protection - it does not know what the rest of the stack is doing, and it is not aware of ComfyUI at all. Keeping the two apart is up to you:

*   A loaded Bonsai 2 27B holds ~7.2 GB of weights, ~4 GiB of KV cache at the configured `ctx-size = 131072` with `q8_0`, and ~0.6 GB for the vision projector - most of a 16 GB card.
*   If ComfyUI or a large Ollama model is holding VRAM when a Bonsai request arrives, the load fails with `cudaMalloc failed: out of memory` and the request returns HTTP 500. The reverse happens too: a ComfyUI model load can fail while Bonsai is resident.
*   Serialise the usage: let one side idle out (or stop it) before starting the other. Lowering `ctx-size`, switching the KV cache to `q4_0`, or dropping `mmproj` shrinks Bonsai if you need it to coexist with something else.
*   ComfyUI keeps its models resident until it needs the space. To hand the GPU over immediately: `docker exec ainode-comfyui /home/user/venv/bin/python -c "import json,urllib.request;urllib.request.urlopen(urllib.request.Request('http://127.0.0.1:8188/free',data=json.dumps({'unload_models':True,'free_memory':True}).encode(),headers={'Content-Type':'application/json'}))"`.

### Disabling it

Set `PRISM_ENABLE=0` in the environment of the `ollama` service, or remove the binaries / `models.ini`. `start.sh` always ends with `exec ollama serve`, so the container never loses its LLM backend either way.

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
