FROM node:22-bookworm-slim

ENV TZ=America/Sao_Paulo \
    DISABLE_AUTOUPDATER=1 \
    DISABLE_TELEMETRY=1

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      weasyprint poppler-utils fonts-noto-core fonts-noto-cjk \
      jq ca-certificates tzdata coreutils util-linux \
      python3 python3-venv git \
 && rm -rf /var/lib/apt/lists/*

RUN npm install -g @anthropic-ai/claude-code@2.1.309 && npm cache clean --force

# Always the contract from main: rebuild with --no-cache to pick up a new interface version
ARG INTERFACE_SOURCE="git+https://github.com/grodrigues04/interface-personal-whats.git@main"
RUN python3 -m venv /opt/interface \
 && /opt/interface/bin/pip install --no-cache-dir "interface-personal-whats @ ${INTERFACE_SOURCE}"

COPY --chmod=755 scheduler.sh run.sh smoke-test.sh run-as-claude-user.sh /app/
COPY --chmod=644 send_results.py /app/

# Starts as root on purpose: see run-as-claude-user.sh
WORKDIR /data

CMD ["/app/scheduler.sh"]
