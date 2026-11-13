# ==============================================================================
# Crawl4AI Container
# ==============================================================================
# Self-hosted web extraction API for the AINode stack.
#
# Upstream image, used as-is. Everything that changes at runtime lives in
# compose.yml (env, limits, mounts) or data/crawl4ai/config.yml; only settings
# that must never drift and are worth a rebuild belong here.
#
# Pin: 0.9.5 is the security release that closes GHSA-w4xc-px5p-c32w,
# GHSA-qj46-wp7m-rgj8, GHSA-f856-7xp9-w3cc, GHSA-j843-8p47-rhxp,
# GHSA-rhjm-7hj7-75fx and GHSA-j2qh-f73r-mg3q. Do not downgrade.
# Digest is the amd64 manifest; this stack builds for x86_64 only.
#
# Build args: none.
# ==============================================================================

FROM unclecode/crawl4ai:0.9.5@sha256:636a6f9e5127f54771f14f709bf1b95693aacc30512426b26d09768b0269f1f4

LABEL org.opencontainers.image.title="AINode Crawl4AI" \
      org.opencontainers.image.description="Crawl4AI 0.9.5 web extraction API for the AINode stack" \
      org.opencontainers.image.base.name="unclecode/crawl4ai:0.9.5"

# Persistent runtime defaults (rebuild to change).
# 0.9.5 prints a Crawl4AI Cloud notice on first run; this instance is
# self-hosted and LAN-only, so silence it.
ENV CRAWL4AI_NO_CLOUD_NOTICE=1
