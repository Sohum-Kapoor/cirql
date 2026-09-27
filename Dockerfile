# Cirql server + client, one process, one machine (SOH-173 hosting off the laptop).
# Mirrors the laptop host exactly: the same Python (3.14) and the same pinned
# packages (requirements.lock is `pip freeze` from the .venv that serves the demo).
FROM python:3.14-slim

ENV PYTHONUNBUFFERED=1 PIP_NO_CACHE_DIR=1 DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends curl ca-certificates git \
    && curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY requirements.lock .
RUN pip install -r requirements.lock

COPY . .
# Pre-build the client bundle into the image so the first boot serves / at once.
# If this step ever fails, the entrypoint's `jac start` builds it on first boot.
RUN jac build main.jac || echo "client prebuild skipped; first start will build it"

# The volume is mounted at /data; the entrypoint links .jac/data and uploads/ into it.
RUN chmod +x scripts/entrypoint.sh
EXPOSE 8080
CMD ["scripts/entrypoint.sh"]
