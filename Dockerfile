# ─────────────────────────────────────────────────────────────
# Stage 1: fuente oficial del binario cscli
# Se toma directo de la imagen que publica crowdsecurity, sin
# vendorizar ningún .deb en este repo. Cada build "tira" de lo
# que esté publicado como :latest en ese momento.
# ─────────────────────────────────────────────────────────────
FROM crowdsecurity/crowdsec:latest AS crowdsec-src

# ─────────────────────────────────────────────────────────────
# Stage 2: servidor MCP con transporte SSE
#
# mcp-shell-server solo habla stdio (no expone red por sí mismo).
# mcp-proxy es el puente que lo sirve como SSE/HTTP en un puerto,
# para que LibreChat (u otro cliente) lo alcance por red.
# No se forkea nada: ambos se instalan como paquetes pip.
# ─────────────────────────────────────────────────────────────
FROM python:3.13-slim AS base

WORKDIR /app

# Dependencias mínimas de sistema (certificados para TLS de cscli)
# + Node.js: necesario para "npx" (usado por servidores MCP oficiales
# de Anthropic como @modelcontextprotocol/server-filesystem).
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl gnupg \
    && mkdir -p /etc/apt/keyrings \
    && curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/*

# Copiamos SOLO el binario cscli desde la imagen oficial.
# No pasa por apt/dpkg, no queda vendorizado en este repo:
# la próxima vez que se reconstruya esta imagen con --pull,
# se trae automáticamente la versión que sea "latest" en Docker Hub.
COPY --from=crowdsec-src /usr/local/bin/cscli /usr/local/bin/cscli
RUN chmod +x /usr/local/bin/cscli

# mcp-proxy: bridge stdio -> SSE/HTTP
# mcp-shell-server: ejecuta el comando whitelisteado (cscli) vía stdio
RUN pip install --no-cache-dir mcp-proxy mcp-shell-server

ENV MCP_PORT=8000

# servers.json es el default de fallback horneado en la imagen.
# En producción se monta por volumen desde la NAS
# (/DATA/AppData/mcp-crowdsec-gateway/servers.json -> /app/servers.json),
# así que agregar/ajustar servidores o su ALLOW_COMMANDS no requiere
# rebuild: solo editar el archivo en la NAS y reiniciar el contenedor.
COPY servers.json /app/servers.json

EXPOSE 8000

# mcp-proxy lee servers.json y levanta cada servidor nombrado como
# subproceso stdio, exponiéndolos por SSE en:
#   http://0.0.0.0:$MCP_PORT/servers/<nombre>/sse
# --pass-environment reenvía variables del contenedor a los subprocesos
# (por ejemplo CROWDSEC_LAPI_URL); el ALLOW_COMMANDS de cada servidor
# ya viene definido en su propio bloque "env" dentro de servers.json.
ENTRYPOINT ["sh", "-c", "mcp-proxy --pass-environment --port=${MCP_PORT} --host=0.0.0.0 --named-server-config /app/servers.json"]
