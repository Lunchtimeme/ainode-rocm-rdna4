#!/usr/bin/env python3
"""Canonical form of `docker compose config --format json`.

Why this exists: `docker compose config` is the right way to see what compose
will actually run, but its output is not stable across compose releases. Key
order inside a service changes, and newer versions add fields such as
`create_host_path` that older ones never emit. Diffing the raw output makes the
regression test fail for reasons that have nothing to do with compose.yml.

This filter keeps the model and discards the presentation:

  * keys are sorted, so ordering differences disappear
  * fields listed in IGNORED (version-specific cosmetics) are dropped
  * the absolute repository path becomes <repo>, so the golden file is portable
  * bearer tokens and secrets become <redacted>

Usage: docker compose ... config --format json | canonicalize-compose.py <repo>
"""
import json
import sys

IGNORED = {"create_host_path", "pull_policy"}
SECRET_KEYS = {
    "CRAWL4AI_API_TOKEN",
    "SEARXNG_SECRET",
    "STRATA_API_KEY",
    "API_KEY",
    "WEBUI_SECRET_KEY",
}


def scrub(node, root):
    if isinstance(node, dict):
        return {k: scrub(v, root) for k, v in node.items() if k not in IGNORED}
    if isinstance(node, list):
        return [scrub(v, root) for v in node]
    if isinstance(node, str):
        return node.replace(root, "<repo>")
    return node


def main():
    root = sys.argv[1].rstrip("/")
    doc = scrub(json.load(sys.stdin), root)
    services = doc.get("services") if isinstance(doc, dict) else None
    if not isinstance(services, dict):
        return
    for svc in services.values():
        if not isinstance(svc, dict):
            continue
        env = svc.get("environment")
        if isinstance(env, dict):
            for key in list(env):
                if key in SECRET_KEYS:
                    env[key] = "<redacted>"
    json.dump(doc, sys.stdout, indent=2, sort_keys=True)
    sys.stdout.write("\n")


if __name__ == "__main__":
    main()
