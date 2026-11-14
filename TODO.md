# AINode (ROCm) TODO List

A self-contained privacy-focused AI stack for interacting with LLMs and Stable Diffusion, leveraging AMD's ROCm toolkit.

### TODO

Everything here needs either an image rebuild (hours on a slow line) or
hardware/CI that is not this machine. Everything cheap has been done.

- [ ] **Kokoro: install CPU-only PyTorch.** The image sets `DEVICE=cpu` / `USE_GPU=false` but installs `torch` from `download.pytorch.org/whl/rocm6.4`, which is 15.6 GB of the 27.6 GB image and is never used at runtime. Switching to the CPU wheels (~0.2 GB) should cut the image by more than half and the build download from ~19 GB to ~3 GB. Needs a rebuild to verify `uv sync --extra cpu` does not pull a second torch; do it together with the next Kokoro rebuild.
- [ ] **Pin the floating git clones:** `AINODE_OWUI_REF`, `AINODE_KOKORO_REF`, SearXNG image digest, and `docker/chroma/Dockerfile`'s runtime stage cloning master while the builder pins `CHROMADB_VERSION`. Each is one image rebuild; do them when that image is rebuilt anyway.
  Cheapest first: chroma (~10 min) and searxng (~33 min at 2 MB/s). Open WebUI (~11 GB) and Kokoro (~19 GB) are the expensive ones; the `docker/comfyui/Dockerfile.update` overlay pattern cuts those to a clone + requirements.
- [ ] **Open WebUI embedding model.** `RAG_EMBEDDING_MODEL=sdadas/stella-pl-retrieval` is a Polish model, 6.19 GB of the image, and a surprising default for an English stack. Pick deliberately and pre-download in the build.
- [ ] **Full clean-install build test.** Clone to a fresh directory with no `data/`, no images and no build cache, then follow README end to end. The config layer is verified (`scripts/check-compose.sh`, `render-config.sh --check`, a fresh-checkout dry run); what is untested is the build itself on a machine that has no cached layers.
- [ ] `install.sh`: detect UID/GIDs and `gfx` from `rocminfo`, pick profiles, generate secrets, write `.env`, render vhosts, print download estimates.
- [ ] Optional: full Arch package reproducibility via `AINODE_ARCH_SNAPSHOT` (archive.archlinux.org dated repos). Costs a rebuild of every image, so it stays opt-in.
- [ ] Optional: Podman support. The scripts honour `AINODE_DOCKER=podman`, but nothing has been tested against a Podman socket.
- [ ] Offer the .env/profiles rework upstream once this line has proven stable.

### Done

- [x] Initial commit
- [x] Move all variables to .env file
      Every literal in `compose.yml` is `${VAR:-default}`; secrets live in `.env`
      (Crawl4AI token, SearXNG secret, WebUI key) or in files where a `$` would be
      destroyed by interpolation (`htpasswd`). Runtime settings that were baked
      into Dockerfiles (Open WebUI's `ENABLE_SIGNUP`, `DEFAULT_USER_ROLE`,
      `WEBUI_SECRET_KEY`, `PRISM_ENABLE`) are compose environment now.
- [x] Optional services via compose profiles (`comfyui`, `kokoro`, `searxng`, `crawl4ai`, `strata`)
- [x] nginx vhosts generated from `examples/reverseproxy/`; deferred upstream
      resolution so a disabled service can never take the proxy down
- [x] Fix README install steps (sites_enabled -> sites-enabled, phantom 8443, port claims)
- [x] BuildKit cache mounts (pip/pacman/uv) in every Dockerfile
- [x] Strata as an optional, profile-gated service (off by default)
- [x] Wire up the variables that were advertised but inert: `AINODE_GPU_ARCH` and
      `AINODE_COMFYUI_REF` reach the ComfyUI build, `AINODE_PREFIX` reaches Open
      WebUI's Ollama and Chroma URLs
- [x] Runtime config files are seeded before first start (`examples/searxng`,
      `examples/crawl4ai`) and `render-config.sh` refuses to run without them
- [x] Generated vhosts are mode 600: they contain the bearer tokens
- [x] SearXNG port published on loopback only
- [x] Prerequisites documented and checked: Compose >= 2.20, buildx, gettext;
      Podman claim removed
- [x] `scripts/build-base.sh` builds the base image with the configured UID
- [x] `scripts/check-compose.sh` + `tests/compose.golden.yml`: the compose
      regression harness is part of the repository
- [x] `UPGRADING.md`: in-place upgrade, rollback, and what not to do
