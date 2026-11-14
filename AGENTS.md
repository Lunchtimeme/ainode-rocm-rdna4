# AGENTS.md — AINode stack

Guide for agents working in this repository. It describes the running services,
how to reach them, and the house rules. **Never put secrets in this file.**
Credentials belong in `.env` (gitignored) or `data/` (gitignored).

## Layout and conventions

- `compose.yml` — compose project `ainode`, one bridge network `ainode-internal`,
  containers named `ainode-<service>`. Every host-specific value is
  `${AINODE_*:-default}` and comes from `.env`; a missing `.env` still works.
- `docker/<service>/Dockerfile` — build-time settings only (base image pin,
  packages, persistent defaults). Changing these requires a rebuild.
- `compose.yml` — semi-permanent service settings (environment, volumes, limits,
  ports, build args). Runtime settings that used to live as `ENV` in a Dockerfile
  (Open WebUI's `ENABLE_SIGNUP`, `WEBUI_SECRET_KEY`, ...) now live here, because
  runtime env overrides image `ENV` and flipping one costs a restart, not a rebuild.
- `scripts/render-config.sh` — generates `data/reverseproxy/sites-enabled/*` from
  `examples/reverseproxy/*`; `--check` diffs, `--reload` applies. Refuses to run
  without `envsubst`, refuses to run when an enabled profile's bind-mount source
  (`data/crawl4ai/config.yml`) is missing, and writes the vhosts mode 600 because
  they contain bearer tokens.
- `scripts/set-comfyui-password.sh` — writes the ComfyUI basic-auth file.
- `scripts/build-base.sh` — builds `ainode-base:python313` with `AINODE_USER_UID`
  from `.env`; a bare `docker build` always produces uid 1000.
- `scripts/check-compose.sh` — renders `compose.yml` with `tests/compose.test.env`
  and diffs against `tests/compose.golden.yml`; `--update` accepts the change.
- `scripts/lib-env.sh` — shared `.env` loader and command checks.
- `scripts/init-env.sh` — creates `.env` from `.env.example` and generates any
  empty `CRAWL4AI_API_TOKEN` / `SEARXNG_SECRET`; idempotent.
- `.github/workflows/config-check.yml` — runs the compose golden test, the shell
  syntax check and the template render on every push. No image is built.
- `data/<service>/` — runtime state and configuration (gitignored). Sanitized
  copies live in `examples/<service>/` so the repo shows the expected shape
  without local secrets. **`data/reverseproxy/sites-enabled/` is generated**:
  edit `examples/reverseproxy/` and re-run `scripts/render-config.sh`.
- `.env` — local secrets and host settings (gitignored, chmod 600). Template and
  full variable list: `.env.example`. Never read values into commits, logs, or
  documentation.
- Secrets that contain `$` (apr1 hashes) cannot go in `.env`; compose would strip
  them as interpolation. They stay files: `data/reverseproxy/htpasswd/.htpasswd`,
  `ssl/`.

House rules:

- **Additive changes only.** Do not change an existing service's image, volumes,
  network, or published ports. Never restart or rebuild the ROCm services
  (`comfyui`, `ollama`, `kokoro-fastapi`, `openwebui`) without an explicit request.
- **Optional services are compose profiles** (`comfyui`, `kokoro`, `searxng`,
  `crawl4ai`, `strata`); `COMPOSE_PROFILES` in `.env` is the switch. Anything
  gated that way must also keep `reverseproxy`'s `depends_on` entry
  `required: false` and must not leave a vhost pointing at it — an nginx
  `proxy_pass` to a missing container stops nginx from spawning any worker and
  silently kills every other vhost.
- **Target one service.** Never run bare `docker compose up -d`; it can recreate
  unrelated services. Use `docker compose up -d --no-deps <service>`.
- **Logging is off by design.** The `x-common` anchor sets
  `logging.driver: none`; new services inherit it. Do not override it with
  `json-file`. `docker logs` is intentionally unavailable. Application log levels
  should be `ERROR` or higher.
- **Build contexts stay small.** Most services use `context: .`; the root
  `.dockerignore` excludes `data/`, `.git/`, `docker/llamacpp/`, `examples/`,
  `ssl/`, and `.env`. A wrapper image that only pins an upstream `FROM` should use
  a service-local context (`./docker/<service>`), as `crawl4ai` does.
- **Reverse proxy changes** go in `data/reverseproxy/sites-enabled/` as numbered
  files, with a sanitized mirror in `examples/reverseproxy/`. Apply with
  `docker exec ainode-reverseproxy nginx -t && docker exec ainode-reverseproxy nginx -s reload`
  — reload, never restart.
- **DNS names** are `*.localdomain` records on the LAN router. Adding a name is a
  router change, not an `/etc/hosts` edit.
- **Prerequisites:** Compose >= 2.20 (`depends_on: required: false`), BuildKit via
  the `docker-buildx` plugin (cache mounts), `gettext` for `envsubst`. The scripts
  check what they need and name the package that provides it.
- **Upgrades are in place**, never a fresh clone next to the old tree: container
  names, ports and `data/` are shared. See `UPGRADING.md`.
- **Version pins are repository defaults, not `.env` defaults.** The tested
  upstream revision is the default in `compose.yml` (`${VAR:-<ref>}`) and in the
  Dockerfile `ARG`, so checking out a newer tag of this repo moves the pins with
  it. `.env` only ever *overrides* them, for someone trying a newer release.
  `scripts/check-compose.sh` fails when the two defaults disagree.
- **Secrets with `$` in them** (apr1 hashes) cannot live in `.env`; they stay files
  under `data/reverseproxy/htpasswd/`.

## Service map

| Service | Container | Internal address | LAN name |
|---|---|---|---|
| SearXNG | `ainode-searxng` | `ainode-searxng:8080` | `http://searxng.localdomain` |
| Crawl4AI | `ainode-crawl4ai` | `ainode-crawl4ai:11235` | `http://crawl4ai.localdomain` |
| Ollama | `ainode-ollama` | `ainode-ollama:11434` | `http://ollama.localdomain:11434` |
| Bonsai 2 / Prism | `ainode-ollama` | `ainode-ollama:8080` | `http://bonsai.localdomain` |
| ComfyUI | `ainode-comfyui` | `ainode-comfyui:8188` | `http://comfyui.localdomain` |
| Open WebUI | `ainode-openwebui` | `ainode-openwebui:8080` | `http://openwebui.localdomain` |
| Strata (opt.) | `ainode-strata` | `ainode-strata:8080` | `http://strata.localdomain` |

`chroma` and `kokoro-fastapi` are internal-only; reach them by container name on
`ainode-internal`.

A hostname whose service is disabled in `COMPOSE_PROFILES` has no vhost at all and
falls through to the catch-all `00default`, which answers `404` on purpose. A
`502` means the vhost exists but the container behind it is down.

From another container on `ainode-internal`, use the internal address; from the
host or another LAN device, use the `*.localdomain` name. Internal calls skip the
proxy (and its auth/token injection).

Self-signed TLS: use `http://` for local clients. `https://` works in browsers
after accepting the certificate.

## SearXNG — local web search

- JSON API: `curl 'http://searxng.localdomain/search?q=term&format=json'`
  (add `&pageno=2`, `&language=cs`, `&safesearch=0` as needed).
- Results carry `url`, `title`, `content` (engine snippet), `engine`, `score`.
  SearXNG does **not** fetch page bodies; use Crawl4AI for full text.
- Config: `data/searxng/settings.yml`, mirrored at
  `examples/searxng/settings.yml`. `search.formats` must include `json` for API
  clients. After editing: `docker compose restart searxng`.
- No authentication on the LAN. Logging driver is `none`.

## Crawl4AI — local web extraction

- Endpoint: `POST http://crawl4ai.localdomain/md` with JSON
  `{"url": "https://example.com", "f": "fit"}`.
  `f=fit` extracts main content (default, best for agents); `f=raw` converts the
  whole page including navigation; `f=bm25`/`f=llm` need a `q` and, for `llm`, a
  configured provider.
- LAN requests need no credential: the reverse proxy injects the bearer token.
  Direct calls to `ainode-crawl4ai:11235` need
  `Authorization: Bearer $CRAWL4AI_API_TOKEN` (value in `.env`). Never print the
  token.
- `GET /health` is public and returns the version. `http://crawl4ai.localdomain/`
  redirects to the playground.
- Config: `data/crawl4ai/config.yml`, mirrored at
  `examples/crawl4ai/config.yml`. Current intent: deep crawling **off** (0.9.5
  opt-in), hooks and JWT off, static token only, browser pool 8, container capped
  at 4 GB. After editing: `docker compose restart crawl4ai`.
- Image pin: `unclecode/crawl4ai:0.9.5` (security release). Do not downgrade.
- Hermes uses it through the `crawl4ai` plugin and
  `web.extract_backend: crawl4ai`.

## Ollama — local LLMs

- Native API: `http://ollama.localdomain:11434` — `/api/tags`, `/api/chat`,
  `/api/generate`, `/api/embed`. (`https://ollama.localdomain` also works with a
  self-signed cert; the plain port-80 vhost belongs to Open WebUI.)
- OpenAI-compatible: `http://ollama.localdomain:11434/v1/chat/completions`.
- List installed models: `curl -s http://ollama.localdomain:11434/api/tags` or
  `docker exec ainode-ollama ollama list`. Use the exact `name` returned by the
  API in requests; do not assume a model is installed.
- Models live in `data/ollama`; shared model files are under
  `data/common/models` (mounted at `/models`).

## Bonsai 2 / Prism — local OpenAI-compatible model

- Endpoint: `http://bonsai.localdomain/v1` (OpenAI-compatible), also reachable as
  `ainode-ollama:8080/v1` inside the stack.
- Model id: `bonsai2-27b-heretic` (see `docker/llamacpp/models.ini`). It is a
  router preset: the model is **not** loaded at startup, loads on the first
  request, and unloads after 120 s idle to share the GPU with Ollama and ComfyUI.
- Inspect status and list models: `curl -s http://bonsai.localdomain/v1/models`
  (`status.value` reports `loaded`/`unloaded`).
- Chat example: `POST /v1/chat/completions` with
  `{"model":"bonsai2-27b-heretic","messages":[...]}`.
- Binaries and the router preset live in `docker/llamacpp/` (mounted at
  `/opt/prism`). Start script: `docker/llamacpp/start.sh`.
- Setup: extract a PrismML Linux x86_64 build into `docker/llamacpp/` (gitignored);
  put the GGUF pack and optional `mmproj` projector in
  `data/common/models/bonsai/`; register them in `docker/llamacpp/models.ini` as a
  `[section]` (`model = /models/bonsai/<pack>.gguf`, optional `mmproj`). The section
  name is the model id. Apply with `docker compose restart ollama`.
- Open WebUI: Admin Panel -> Settings -> Connections -> add **OpenAI** with base
  URL `http://ainode-ollama:8080/v1` and a placeholder API key.
- Disable: `PRISM_ENABLE=0` in `.env` (it is passed to the `ollama` service), or
  remove the binaries.
- VRAM: the router loads on the first request and unloads after 120 s idle. For
  explicit unloads around image generation, import
  `examples/openwebui/tools/native_image_gen_v2.py` via Workspace -> Tools; it
  releases Ollama, Bonsai and ComfyUI models.

## ComfyUI — image and video generation

- LAN URL: `http://comfyui.localdomain` — **basic auth is required**. Credentials
  are in `data/reverseproxy/htpasswd/.htpasswd`; never copy them into docs or
  commits.
- Internal API: `ainode-comfyui:8188` (no proxy auth inside the network).
- API: `POST /prompt` with a workflow JSON, `GET /history/{prompt_id}`,
  `GET /view?filename=...`, WebSocket `/ws?clientId=...`.
- Models are shared from `data/common/models`; ComfyUI state and custom nodes are
  under `data/comfyui/`.
- A live ComfyUI session may have work in progress; do not restart it without
  asking.

## Verification

```
scripts/check-compose.sh                                  # compose.yml vs golden render
docker compose -f ~/ainode/compose.yml config --services   # what COMPOSE_PROFILES selects
scripts/render-config.sh --check                          # live vhosts vs templates
docker compose -f ~/ainode/compose.yml ps
curl -s 'http://searxng.localdomain/search?q=test&format=json' | head -c 200
curl -s http://crawl4ai.localdomain/health
curl -s http://ollama.localdomain:11434/api/tags   | head -c 200
curl -s http://bonsai.localdomain/v1/models  | head -c 200
curl -s -o /dev/null -w '%{http_code}\n' http://comfyui.localdomain/
```

Expected: `check-compose.sh` prints "matches the golden config"; `config --services`
lists the core four plus whatever the profiles add; `render-config.sh --check` prints
"vhosts are up to date"; SearXNG and Ollama
return JSON; Crawl4AI returns
`{"status":"ok",...}`; Bonsai returns a model list; ComfyUI returns `401` without
basic auth (that is the auth gate working).
