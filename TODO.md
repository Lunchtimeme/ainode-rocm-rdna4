# AINode (ROCm) TODO List

A self-contained privacy-focused AI stack for interacting with LLMs and Stable Diffusion, leveraging AMD's ROCm toolkit.

### TODO

Everything here needs either an image rebuild (hours on a slow line) or hardware
that is not this machine. Everything cheap has been done.

- [ ] **Kokoro: install CPU-only PyTorch.** The image sets `DEVICE=cpu` /
  `USE_GPU=false` but installs `torch` from `download.pytorch.org/whl/rocm6.4`:
  15.6 GB of the 27.6 GB image, never used at runtime. Plan for the next Kokoro
  build: switch the torch index URL to `https://download.pytorch.org/whl/cpu`,
  drop `rocm-core` from the pacman list, and confirm `uv sync --extra cpu` does
  not re-resolve torch from PyPI (keep the constraint pin Open WebUI uses).
  Expected: ~5 GB image, build download ~3 GB instead of ~19 GB.
- [ ] **SearXNG image digest.** `AINODE_SEARXNG_TAG=latest` is overridable but not
  pinned by default. Pin a digest once a tag has proven stable.
- [ ] **Open WebUI embedding model.** `RAG_EMBEDDING_MODEL=sdadas/stella-pl-retrieval`
  is a Polish model and 6.19 GB of the image. Pick deliberately and pre-download
  it in the build.
- [ ] **Full clean-install build test.** The config layer is verified (compose
  golden, template render, fresh-checkout dry run, CI). What is untested is the
  build and first start on a machine with no images and no build cache. Do this
  on a fast connection and note every deviation from the README.
- [ ] `install.sh`: detect UID/GIDs and `gfx` from `rocminfo`, pick profiles, call
  `init-env.sh`, render vhosts, print download estimates before building.
- [ ] Optional: full Arch package reproducibility via `AINODE_ARCH_SNAPSHOT`
  (archive.archlinux.org dated repos). Costs a rebuild of every image.
- [ ] Optional: Podman support. The scripts honour `AINODE_DOCKER=podman`, but
  nothing has been tested against a Podman socket.
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
- [x] Strata as an optional, profile-gated service (off by default), and the
      "enabling Strata does not replace Ollama by itself" behaviour documented
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
- [x] `scripts/check-compose.sh` + `tests/compose.golden.json`: the compose
      regression harness is part of the repository, immune to exported shell
      variables, and runs in GitHub Actions
- [x] `UPGRADING.md`: in-place upgrade, rollback, and what not to do
- [x] Revision pins: Open WebUI, Kokoro and ComfyUI build from an explicit ref
      (default = the commit this stack was built against, overridable in `.env`),
      and ChromaDB's runtime stage no longer clones master
- [x] `scripts/init-env.sh` generates the required secrets, and
      `render-config.sh` refuses to run while an enabled profile's secret is empty
