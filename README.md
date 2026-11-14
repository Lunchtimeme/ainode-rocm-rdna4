# AINode (ROCm)

> **About this fork**
> This is a fork of [legal-hkr/ainode-rocm](https://github.com/legal-hkr/ainode-rocm), retargeted for AMD RDNA4 GPUs (tested on RX 9070 XT). The original project targets RDNA3 (RX 7900 XTX / gfx1100); this fork switches the ComfyUI PyTorch ROCm nightly target to `gfx1201` (RX 9070 XT), adds a SearXNG metasearch service for Open WebUI web search and a Crawl4AI extraction API for agents. ComfyUI is pinned to a tested upstream release (see `COMFYUI_REF`), and the stack can optionally serve the ternary Bonsai 2 27B model through the PrismML llama.cpp fork alongside Ollama.

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
*   **Bonsai 2 (optional):** A ternary 27B model served by the PrismML llama.cpp fork, running alongside Ollama on port `8080`. Only active when the binaries and weights are installed; setup is in [AGENTS.md](AGENTS.md).
*   **ComfyUI:** A node-based UI for Stable Diffusion, allowing for complex workflows and customization.
*   **ChromaDB:** A vector database for storing and retrieving embeddings, enabling efficient retrieval-augmented generation (RAG).
*   **Kokoro FastAPI:** A backend for Text-to-Speech (TTS), providing high-quality voice generation.
*   **SearXNG:** A metasearch engine that aggregates results from multiple search engines, used as a web search backend for Open WebUI.
*   **Crawl4AI:** A self-hosted web extraction API for agents, exposed at `crawl4ai.localdomain`.
*   **Strata (optional):** An alternative local model server with OpenAI- and Anthropic-compatible endpoints. Off by default; enable with the `strata` profile.
*   **Nginx:** A reverse proxy server, managing incoming requests and routing them to the appropriate backend services.

## Repository Structure

The repository is organized as follows:

*   `docker` - Contains Dockerfiles for all stack components.
*   `docker/llamacpp` - Startup script and router preset for the optional Bonsai 2 server (`start.sh`, `models.ini`). The PrismML binaries are downloaded by the user and ignored by git.
*   `scripts` - Host-side helpers: `render-config.sh` generates the nginx vhosts, `set-comfyui-password.sh` writes the basic-auth file.
*   `examples` - Versioned templates. `examples/reverseproxy/*` are the *source* of the generated vhosts.
*   `AGENTS.md` - Service access details and conventions for agents.
*   `compose.yml` - Docker Compose configuration; every host-specific value comes from `.env`.
*   `.env.example` - Documented list of every variable, with the defaults.

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
    mkdir -p data/{chroma,comfyui/user,comfyui/custom_nodes,common/models,desktop/home,desktop/home_i3,ollama,openwebui/data,reverseproxy/htpasswd,reverseproxy/sites-enabled,searxng} ssl
    ```
    The nginx vhost directory is `sites-enabled` (hyphen): `compose.yml` mounts exactly that path, and anything else leaves nginx with no server blocks at all.

3.  **Place SSL certificates:**
    Copy the `ainode.crt` and `ainode.key` files into the `ssl` directory. These files are used for secure communication via HTTPS. You can generate your own self-signed certificates or use a certificate from a trusted Certificate Authority (CA), example on how to do that can be found in the `examples/ssl` directory. The entire ssl directory is gitignored so your certificates never leave your machine.

4.  **Create Basic Auth credentials for ComfyUI:**
    ```bash
    scripts/set-comfyui-password.sh --user comfyui
    ```
    It prompts for a password and writes `data/reverseproxy/htpasswd/.htpasswd`. The hash must not live in `.env`: `$apr1$...` contains `$`, which compose reads as variable interpolation and silently strips.

5.  **Configure the installation:**
    ```bash
    cp .env.example .env
    chmod 600 .env
    $EDITOR .env
    ```
    Everything host-specific lives there; `.env.example` documents each variable and compose carries a working default for all of them. The two values people normally set:

    * `COMPOSE_PROFILES` - which services this machine runs. Always on: `ollama`, `openwebui`, `chroma`, `reverseproxy`. Optional: `comfyui`, `kokoro`, `searxng`, `crawl4ai`, `strata`. A service whose profile is not listed is neither built nor started, so this is also how you keep a small disk footprint.
    * The secrets: `CRAWL4AI_API_TOKEN`, `SEARXNG_SECRET` (`openssl rand -hex 24`). `WEBUI_SECRET_KEY` may stay empty, in which case Open WebUI generates and stores its own.

    SearXNG needs no file editing for its secret: `SEARXNG_SECRET` overrides `data/searxng/settings.yml`. The engine list lives in `examples/searxng/settings.yml`; copy it to `data/searxng/settings.yml` if you want to change which engines are used.

    Bonsai 2 is optional: extract the PrismML build into `docker/llamacpp/`, put the GGUF weights in `data/common/models/bonsai/`, and register them in `docker/llamacpp/models.ini`; see [AGENTS.md](AGENTS.md). Set `PRISM_ENABLE=0` in `.env` to skip the second server entirely.

    Then generate the nginx vhosts from their templates:
    ```bash
    scripts/render-config.sh
    ```
    This writes `data/reverseproxy/sites-enabled/*` from `examples/reverseproxy/*`, skipping any vhost whose profile is off and filling in the LAN domain and the two bearer tokens. Never edit the generated files; edit the templates and re-run it. `scripts/render-config.sh --check` tells you whether the live config matches the templates.

6.  **Build and run the stack:**
    Navigate to the repository directory and start the Docker containers:
    ```bash
    # 1. Build the base image first (required)
    docker build -t ainode-base:python313 ./docker/base

    # 2. Build the services enabled in COMPOSE_PROFILES
    docker compose build

    # 3. Start them (individual services: up -d --no-deps <service>)
    docker compose up -d
    ```
    The `-d` flag runs the containers in detached mode (in the background). It is highly suggested to run the stack without `-d` at first to monitor the startup process.

7.  **Access the interfaces:**
    *   Open WebUI is served through the reverse proxy on ports `80`/`443`.
    *   The Ollama API is published on `11434`.
    *   SearXNG listens on `8080` on the host and is proxied as `http://searxng.localdomain`.
    *   The optional Bonsai 2 endpoint is at `http://ainode-ollama:8080/v1` (LAN: `http://bonsai.localdomain`).
    *   Crawl4AI is at `http://crawl4ai.localdomain` (LAN; no credentials).
    
    You can access these interfaces using your web browser or with tools like `curl` or `Postman`.

    The definitive hostname list is `examples/reverseproxy/`. If you run AINode on localhost and have no LAN DNS, add this to `/etc/hosts`:
    ```configuration
    127.0.0.1   comfyui.localdomain        comfyui
    127.0.0.1   ollama.localdomain         ollama
    127.0.0.1   openwebui.localdomain      openwebui
    127.0.0.1   bonsai.localdomain         bonsai
    127.0.0.1   searxng.localdomain        searxng
    127.0.0.1   crawl4ai.localdomain       crawl4ai
    127.0.0.1   kokoro-fastapi.localdomain kokoro-fastapi
    127.0.0.1   strata.localdomain         strata
    ```
    With this setup, you can access the components by using the specified hostname in your URL, e.g., `https://comfyui`, `https://openwebui`, etc.

8.  **Configure service URLs in Open WebUI:**
    Note that `ENABLE_SIGNUP` is now a `.env` variable (`ENABLE_SIGNUP=true`, then set it to `false` after creating the admin account). Changing it is a restart, not a rebuild.
    Once the stack is up and running, log into Open WebUI and add the internal service endpoints through the web GUI:
    *   **SearXNG (web search):** `http://ainode-searxng:8080`
    *   **ComfyUI (image generation):** `http://ainode-comfyui:8188`
    *   **Ollama (LLM backend):** `http://ainode-ollama:11434`
    *   **Bonsai 2 (optional, if installed):** `http://ainode-ollama:8080/v1`

    For Bonsai, choose **OpenAI** as the connection type, use that base URL, and any placeholder API key.

Optional Bonsai 2 setup (PrismML binaries, weights, `models.ini`, Open WebUI connection) is documented in [AGENTS.md](AGENTS.md); the stack runs with Ollama alone if you skip Bonsai.

For VRAM management, `examples/openwebui/tools/native_image_gen_v2.py` can be imported through **Workspace → Tools** in Open WebUI; it unloads Ollama, Bonsai and ComfyUI models before and after image generation.
