# Cirql server + client, one process, one machine (SOH-173 hosting off the laptop).
# Mirrors the laptop host exactly: the same Python (3.14) and the same pinned
# packages (requirements.lock is `pip freeze` from the .venv that serves the demo).
FROM python:3.14-slim

ENV PYTHONUNBUFFERED=1 PIP_NO_CACHE_DIR=1 DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends curl ca-certificates git unzip \
    && curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY requirements.lock .
RUN pip install -r requirements.lock
# jaclang's client bundler shells out to bun (not npm); install it explicitly so the
# image build does not depend on a silent auto-download that needs unzip and network.
RUN curl -fsSL https://bun.sh/install | bash
ENV BUN_INSTALL=/root/.bun PATH=/root/.bun/bin:$PATH

COPY . .
# The client bundle is built on the deploying machine (scripts/fly_deploy.sh runs
# `jac build` and copies .jac/client/dist to deploy/client-dist), then shipped here.
# Fly's remote builder OOM-kills the Vite build, and a boot-time build takes 7+
# minutes on a shared CPU. jac start reuses the bundle when client.*.js exists.
COPY deploy/client-dist/ /app/.jac/client/dist/
RUN ls /app/.jac/client/dist/client.*.js

# The volume is mounted at /data; the entrypoint links .jac/data and uploads/ into it.
RUN chmod +x scripts/entrypoint.sh
EXPOSE 8080
CMD ["scripts/entrypoint.sh"]
