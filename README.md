# AINode (ROCm)

> **About this fork**
> This is a fork of [legal-hkr/ainode-rocm](https://github.com/legal-hkr/ainode-rocm), retargeted for AMD RDNA4 GPUs (tested on RX 9070 XT). The original project targets RDNA3 (RX 7900 XTX / gfx1100); this fork selects the ComfyUI PyTorch ROCm wheel for the GPU you configure (`AINODE_GPU_ARCH`), adds a SearXNG metasearch service for Open WebUI web search and a Crawl4AI extraction API for agents. ComfyUI is pinned to a tested upstream release (see `AINODE_COMFYUI_REF`), and the stack can optionally serve the ternary Bonsai 2 27B model through the PrismML llama.cpp fork alongside Ollama.

## Description

A self-contained privacy-focused AI stack for interacting with LLMs and Stable Diffusion, leveraging AMD's ROCm toolkit.

## Highlights

A privacy-focused approach is implemented as follows:

*   Telemetry across all components is disabled.
*   Only the primary instance of Open WebUI is authorized to persistently store generated text and images. These can be located within the `data/openwebui/data` directory.
*   The amnesic approach utilizes `tmpfs` for mounting input, output, and cache directories. This configuration necessitates periodic container restarts to prevent excessive RAM consumption.
*   Every host-specific value lives in `.env`, and optional services are Docker Compose *profiles*: an installation only builds and runs what it asks for.

## Components

This repository contains Docker configuration files for setting up the following components:

*   **Open WebUI:** A versatile web interface for interacting with various AI models.
*   **Ollama:** A backend for Large Language Models (LLMs), providing a simple and efficient way to run and manage models.
*   **Bonsai 2 (optional):** A ternary 27B model served by the PrismML llama.cpp fork, running alongside Ollama on port `8080`. Only active when the binaries and weights are installed; setup is in [AGENTS.md](AGENTS.md).
*   **ComfyUI (optional profile):** A node-based UI for Stable Diffusion, allowing for complex workflows and customization.
*   **ChromaDB:** A vector database for storing and retrieving embeddings, enabling efficient retrieval-augmented generation (RAG).
*   **Kokoro FastAPI (optional profile):** A backend for Text-to-Speech (TTS), providing high-quality voice generation.
*   **SearXNG (optional profile):** A metasearch engine that aggregates results from multiple search engines, used as a web search backend for Open WebUI.
*   **Crawl4AI (optional profile):** A self-hosted web extraction API for agents, exposed at `crawl4ai.localdomain`.
*   **Strata (optional profile):** An alternative local model server with OpenAI- and Anthropic-compatible endpoints. Off by default; enable with the `strata` profile.
*   **Nginx:** A reverse proxy server, managing incoming requests and routing them to the appropriate backend services.

## Repository Structure

The repository is organized as follows:

*   `docker` - Contains Dockerfiles for all stack components.
*   `docker/llamacpp` - Startup script and router preset for the optional Bonsai 2 server (`start.sh`, `models.ini`). The PrismML binaries are downloaded by the user and ignored by git.
*   `scripts` - Host-side helpers: `render-config.sh` (nginx vhosts), `set-comfyui-password.sh` (basic auth), `build-base.sh` (base image with your UID), `check-compose.sh` (regression test).
*   `examples` - Versioned templates. `examples/reverseproxy/*` are the *source* of the generated vhosts; `examples/searxng/` and `examples/crawl4ai/` hold the runtime config files you copy into `data/`.
*   `tests` - Golden configuration for `scripts/check-compose.sh`.
*   `AGENTS.md` - Service access details and conventions for agents.
*   `UPGRADING.md` - How to update an existing installation without losing data.
*   `compose.yml` - Docker Compose configuration; every host-specific value comes from `.env`.
*   `.env.example` - Documented list of every variable, with the defaults.

## Prerequisites

*   Linux (tested on Arch/CachyOS) with the `amdgpu` kernel driver. The ROCm userspace lives inside the images; a system ROCm install is not required.
*   **Docker Engine with Compose 2.20 or newer** (`docker compose version`). 2.20 is the first release with `depends_on: required: false`, which the optional services rely on.
*   **BuildKit**, i.e. the `docker buildx` plugin (`docker buildx version`). The Dockerfiles use cache mounts so repeated builds do not re-download packages. On Arch: `sudo pacman -S docker-buildx`.
*   **gettext**, which provides `envsubst` (`command -v envsubst`). `scripts/render-config.sh` needs it. On Arch: `sudo pacman -S gettext`; Debian/Ubuntu: `gettext-base`; Fedora: `gettext`.
*   **git**, `curl`, and `openssl`.
*   Disk: roughly **45 GB free** for the minimal stack and **110 GB** for every optional service. Images are built locally, so plan for the build cache too.
*   Your user in the `docker` group (so the compose commands work without sudo).

Podman is **not** supported: the helper scripts call `docker exec` by default. If you want to experiment, set `AINODE_DOCKER=podman`, but expect rough edges.

## Getting Started

### Before you start

The first build is the expensive part, and it is a download. To give an idea, on the optional services:

| Profile | Built or pulled | Size |
|---|---|---|
| `searxng` | pulled | 0.4 GB |
| `crawl4ai` | pulled | 8 GB |
| `comfyui` | built | 24 GB (`~13 GB` downloaded) |
| `kokoro` | built | 28 GB (`~19 GB` downloaded) |
| `strata` | pulled | ~3 GB, plus the model |

That is why `.env.example` starts with only `searxng,crawl4ai`: it gets you a working stack quickly, and you can add the GPU-heavy services later by editing one line.

1.  **Clone the repository:**
    ```bash
    git clone https://github.com/Lunchtimeme/ainode-rocm-rdna4.git ainode
    cd ainode
    ```

2.  **Create the data directory structure:**
    ```bash
    mkdir -p data/{chroma,comfyui/user,comfyui/custom_nodes,common/models,crawl4ai,desktop/home,desktop/home_i3,ollama,openwebui/data,reverseproxy/htpasswd,reverseproxy/sites-enabled,searxng,strata} ssl
    ```
    `sites-enabled` is spelled with a hyphen: `compose.yml` mounts exactly that path, and anything else leaves nginx with no server blocks at all.

3.  **Seed the runtime configuration files.** These two files are mounted by path, so they must exist *before* the containers start:
    ```bash
    cp examples/searxng/settings.yml data/searxng/settings.yml
    cp examples/crawl4ai/config.yml  data/crawl4ai/config.yml
    ```
    * SearXNG needs `settings.yml` for its engine list and for the JSON API that Open WebUI and agents use. Without it SearXNG generates a default file that serves HTML only.
    * Crawl4AI mounts `config.yml` as a *file*. If it is missing, Docker creates an empty **directory** in its place and the service will not start.

    `scripts/render-config.sh` checks both and tells you if one is missing.

4.  **Place SSL certificates:**
    Copy `ainode.crt` and `ainode.key` into the `ssl` directory; the reverse proxy uses them for HTTPS. Two ways to get them are in [examples/ssl/README.md](examples/ssl/README.md): a one-command self-signed certificate for trying things out, or a local CA you install once so every browser trusts the stack. Either way **the certificate must list every hostname you use** - the SAN list in `examples/ssl/ainode.conf` matches the vhosts. The `ssl` directory is gitignored so your keys never leave your machine.

5.  **Create Basic Auth credentials for ComfyUI** (only if you enable the `comfyui` profile):
    ```bash
    scripts/set-comfyui-password.sh --user comfyui
    ```
    It prompts for a password and writes `data/reverseproxy/htpasswd/.htpasswd`. The hash must not live in `.env`: `$apr1$...` contains `$`, which compose reads as variable interpolation and silently strips.

6.  **Configure the installation:**
    ```bash
    scripts/init-env.sh
    $EDITOR .env
    ```
    `init-env.sh` creates `.env` from the example, locks it down, and generates `CRAWL4AI_API_TOKEN` and `SEARXNG_SECRET`. Both are needed by the default profiles: Crawl4AI authenticates to the proxy with its token, and SearXNG signs its session cookies with the secret - the example settings file only holds a placeholder. `scripts/render-config.sh` refuses to run while either is empty, so you cannot get a half-working stack by accident. Then check three things:

    * **Host id.** `AINODE_USER_UID` is your `id -u`; it is compiled into the images, so set it before the first build. The GPU group ids (`getent group render`, `getent group video`, third field) are applied at container start, so a wrong value costs a restart, not a rebuild.
    * **`COMPOSE_PROFILES`** - which services this machine runs. Always on: `ollama`, `openwebui`, `chroma`, `reverseproxy`. Optional: `comfyui`, `kokoro`, `searxng`, `crawl4ai`, `strata`. A service whose profile is not listed is neither built nor started.
    * **`AINODE_GPU_ARCH`** if your card is not an RX 9070 XT: `gfx1100` for RX 7900 series, `gfx1201` for RX 9070.

    `WEBUI_SECRET_KEY` can stay empty; Open WebUI then generates and stores its own. Bonsai 2 is optional: extract the PrismML build into `docker/llamacpp/`, put the GGUF weights in `data/common/models/bonsai/`, and register them in `docker/llamacpp/models.ini`; see [AGENTS.md](AGENTS.md). Set `PRISM_ENABLE=0` to skip the second server entirely.

    Then generate the nginx vhosts from their templates:
    ```bash
    scripts/render-config.sh
    ```
    This writes `data/reverseproxy/sites-enabled/*` (mode 600, they contain the bearer tokens) from `examples/reverseproxy/*`, skipping any vhost whose profile is off. Never edit the generated files; edit the templates and re-run it. `scripts/render-config.sh --check` tells you whether the live config matches the templates.

7.  **Build and run the stack:**
    ```bash
    # 1. Base image, built with your UID (required by every Python service)
    scripts/build-base.sh

    # 2. Build the services enabled in COMPOSE_PROFILES
    docker compose build

    # 3. Start them
    docker compose up -d
    ```
    `docker compose build` only builds what the profiles select. Start with `docker compose up` (no `-d`) the first time if you want to watch the startup output.

8.  **Access the interfaces:**
    *   Open WebUI is served through the reverse proxy on ports `80`/`443`.
    *   The Ollama API is published on `11434`.
    *   SearXNG is proxied as `http://searxng.localdomain`; its port is published on loopback only.
    *   The optional Bonsai 2 endpoint is at `http://ainode-ollama:8080/v1` (LAN: `http://bonsai.localdomain`).
    *   Crawl4AI is at `http://crawl4ai.localdomain` (LAN; no credentials).

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
    Remove the entries for services you did not enable; their hostnames answer `404` on purpose.

9.  **Configure service URLs in Open WebUI:**
    `ENABLE_SIGNUP` is a `.env` variable: create the admin account, then set it to `false` and restart Open WebUI (a restart, not a rebuild). Then add the internal endpoints:
    *   **SearXNG (web search):** `http://ainode-searxng:8080`
    *   **ComfyUI (image generation):** `http://ainode-comfyui:8188`
    *   **Ollama (LLM backend):** `http://ainode-ollama:11434`
    *   **Bonsai 2 (optional, if installed):** `http://ainode-ollama:8080/v1`

    For Bonsai, choose **OpenAI** as the connection type, use that base URL, and any placeholder API key.

Optional Bonsai 2 setup (PrismML binaries, weights, `models.ini`, Open WebUI connection) is documented in [AGENTS.md](AGENTS.md); the stack runs with Ollama alone if you skip Bonsai.

For VRAM management, `examples/openwebui/tools/native_image_gen_v2.py` can be imported through **Workspace → Tools** in Open WebUI; it unloads Ollama, Bonsai and ComfyUI models before and after image generation.

## Turning services on and off

`COMPOSE_PROFILES` decides what is *installed* (built, present, startable). Stopping and starting individual services is a separate, cheaper operation:

```bash
# stop ComfyUI temporarily, e.g. to give the GPU to a game
docker compose stop comfyui

# start it again (the profile has to be named when the container does not exist yet)
docker compose --profile comfyui up -d comfyui

# disable it for good: remove it from COMPOSE_PROFILES in .env, then
scripts/render-config.sh            # drops its vhost, so the hostname 404s
docker compose up -d --remove-orphans
```

What happens to what:

*   **Data survives everything.** `data/` is a bind mount, not a container layer, so stopping, removing or disabling a service never touches models, chats, custom nodes or the vector store.
*   **Images survive `stop` and `down`.** They are only removed by `docker compose down --rmi local` or `docker image prune`, which you should not need.
*   **Disabling a profile does not delete the image.** Re-enabling it is instant until you prune.
*   **A disabled service's hostname answers 404**, not 502: `scripts/render-config.sh` removes its vhost and the catch-all vhost answers instead. A 502 means the vhost exists but the container is down.

### Strata does not replace Ollama by itself

The `strata` profile adds a *second* inference server; it does not disable Ollama
and does not re-point Open WebUI, because Ollama is a core service. To make Strata
your main backend, stop Ollama (`docker compose stop ollama`) and add an **OpenAI**
connection in Open WebUI pointing at `http://ainode-strata:8080/v1` with the same
`STRATA_API_KEY`. Both engines want the same VRAM, so treat them as alternatives and
run one at a time unless you know the model fits twice.

## Updating an existing installation

See [UPGRADING.md](UPGRADING.md). Short version: back up `data/`, `ssl/` and `.env`; pull; run `scripts/render-config.sh --check`; build only what changed; `docker compose up -d`. Never re-clone over an existing installation.

## Development

```bash
scripts/check-compose.sh          # did compose.yml drift from the tested golden config?
scripts/check-compose.sh --update # accept the current render as the new golden
scripts/render-config.sh --check  # do the live vhosts match their templates?
```

`tests/compose.golden.yml` is rendered from a fixed environment (`tests/compose.test.env`), not your `.env`, so it is reproducible on any machine and safe to run in CI.
