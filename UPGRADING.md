# Updating AINode

Two situations, two procedures. Read the one that matches you.

The important idea first: **your data is not inside the images.** Chats, models,
vector data, custom nodes and certificates live in `data/` and `ssl/` on your
disk, and the settings live in `.env`. Updating the software replaces the
containers around that data. If you keep those three things, nothing is lost.

---

## Before anything else: back up

Takes a minute. On a stopped or running stack, either is fine for these folders:

```bash
cd ~/ainode
tar czf ~/ainode-backup-$(date +%F).tar.gz data ssl .env
```

That archive is your undo button. Keep it somewhere else, not only on the same disk.

---

## A. Coming from an older version (before `.env` / profiles)

This covers installations cloned before version `v1.0.0`. In those versions the
settings were edited directly in `compose.yml` and the Dockerfiles.

**Do not clone the new version next to the old one and start it.** Both use the
same container names and the same ports, and the new copy would start with an
empty `data/` directory.

Update in place, in the directory you already have:

```bash
cd ~/ainode
git fetch --tags
git checkout v1.0.0          # or main, if you prefer the latest
```

Your `data/` and `ssl/` folders are untracked, so the checkout does not touch
them. Now recreate the configuration in the new format:

```bash
cp .env.example .env
chmod 600 .env
$EDITOR .env
```

Fill in:

* `AINODE_USER_UID` - `id -u`
* `AINODE_RENDER_GID`, `AINODE_VIDEO_GID` - `getent group render` / `video`, third field
* `CRAWL4AI_API_TOKEN` - **the same token as before.** It is the one in
  `data/reverseproxy/sites-enabled/40crawl4ai` (an `Authorization: Bearer ...` line).
  Reusing it means browsers and clients keep working.
* `SEARXNG_SECRET` - the same value as `secret_key:` in `data/searxng/settings.yml`
* `COMPOSE_PROFILES` - the services you actually had. For a stack running
  everything except Strata: `searxng,crawl4ai,comfyui,kokoro`

Then the two config files and the vhosts:

```bash
# only if this file does not exist yet (it normally does on an older install)
ls data/crawl4ai/config.yml || cp examples/crawl4ai/config.yml data/crawl4ai/config.yml

scripts/render-config.sh
```

`render-config.sh` replaces the hand-written vhosts with generated ones and
prints a warning if it cannot write the directory. If it says the directory is
not writable, run the `sudo chown` it suggests; your old install may have left
those files owned by root.

Now the containers. **You do not have to rebuild to migrate.** The images you
already have keep working:

```bash
docker compose up -d
```

Docker recreates only the containers whose definition changed. Your models,
chats and certificates are untouched. Nothing is downloaded.

Rebuild later, when convenient, to pick up the improvements in the images
(BuildKit download cache, corrected GPU group ids, newer Kokoro/Open WebUI).
The next build of an image is the expensive one; after that the cache makes
repeat builds fast. On a slow line, do one service at a time, e.g.
`docker compose build openwebui && docker compose up -d --no-deps openwebui`.

Finally, check it:

```bash
docker compose ps
curl -s -o /dev/null -w '%{http_code}\n' http://openwebui.localdomain/   # 200
curl -s http://crawl4ai.localdomain/health                              # {"status":"ok",...}
```

---

## B. Routine update of a `v1.0.0` or newer installation

```bash
cd ~/ainode
git fetch --tags
git checkout v1.0.1          # or: git pull
scripts/render-config.sh --check    # did the vhost templates change?
```

If `--check` reports differences, apply them with `scripts/render-config.sh --reload`
(it tests the configuration and reloads nginx; it does not interrupt the stack).

Then bring things up to date. Server images (SearXNG, Crawl4AI, Strata) are
pulled; the rest are built locally, so name them explicitly if you want to limit
what happens:

```bash
docker compose pull --ignore-buildable   # pull only images that come from a registry
docker compose build                     # rebuild only what this machine's profiles select
mkdir -p data/decider                    # only when hindsight-decider is in COMPOSE_PROFILES:
                                         # compose would otherwise create it root-owned, and the
                                         # container runs as your uid and cannot write the weights
docker compose up -d                     # recreate what changed
```

`--ignore-buildable` matters: most services here are built from the Dockerfiles in
this repository, and without the flag compose also tries to *pull* them from a
registry and prints confusing "pull access denied" errors for images that were
never published.

`docker compose up -d` is safe: it leaves containers alone when nothing about
them changed, and your `data/` is never touched.

---

## Rolling back

```bash
cd ~/ainode
git checkout v1.0.0        # the version that worked
docker compose up -d
```

Because the settings are in `.env` (not in the code), a rollback does not need a
new configuration. If the newer version ran a database migration that the older
one cannot read (Open WebUI is the one to watch), restore `data/` from the backup
you made at the top of this file.

---

## Things not to do

* **Never clone over an existing installation.** Update in place.
* **Never run `docker compose down -v`** on this stack. It removes volumes, and
  while this project keeps its state in `data/`, it is the one command that can
  turn a mistake into data loss.
* **Never edit `data/reverseproxy/sites-enabled/` by hand.** It is generated;
  edit `examples/reverseproxy/` and re-run `scripts/render-config.sh`.
* **Do not put an apr1 hash in `.env`.** A `$` in a value is read as variable
  interpolation and silently stripped; use `scripts/set-comfyui-password.sh`.
* **Do not `docker image prune -a`** without thinking: it also removes the images
  this stack builds and your next `up` would rebuild them, which on a slow line
  is hours. `docker image prune` (dangling only) is always safe.

---

## Versions come with the repository

The upstream revisions this stack is built from (Open WebUI, Kokoro, ComfyUI,
ChromaDB, the Crawl4AI image) are defaults inside `compose.yml` and the
Dockerfiles, so checking out a newer tag of *this* repository also moves you to
the versions that were tested with it. Your `.env` can override any of them
(`AINODE_OWUI_REF`, `AINODE_KOKORO_REF`, `AINODE_COMFYUI_REF`, ...) - do that to
try a newer upstream release, and remember it when you next upgrade, because an
override in `.env` stays until you change it.

## Where everything lives

| What | Where | Survives updates |
|---|---|---|
| Models, chats, RAG data, custom nodes | `data/` | yes, never touched |
| Certificates | `ssl/` | yes |
| Your settings and secrets | `.env` | yes |
| Generated nginx vhosts | `data/reverseproxy/sites-enabled/` | regenerated from `examples/` |
| Container images | Docker's storage | yes, until you prune |
| Backups you made | wherever you put them | yes |
