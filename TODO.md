# AINode (ROCm) TODO List

A self-contained privacy-focused AI stack for interacting with LLMs and Stable Diffusion, leveraging AMD's ROCm toolkit.

### TODO
- [ ] Pin the floating git clones: `AINODE_OWUI_REF`, `AINODE_KOKORO_REF`, SearXNG digest, and fix `docker/chroma/Dockerfile` cloning master in the runtime stage. Each is one image rebuild; do them when that image is rebuilt anyway.
- [ ] Optional: full Arch package reproducibility via `AINODE_ARCH_SNAPSHOT` (archive.archlinux.org dated repos). Costs a rebuild of every image, so it stays opt-in.
- [ ] `install.sh`: detect UID/GIDs and `gfx` from `rocminfo`, pick profiles, generate secrets, write `.env`, render vhosts, print download estimates.
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
