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
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates \
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

ENV ALLOW_COMMANDS="cscli"
ENV MCP_PORT=8000

EXPOSE 8000

# mcp-proxy levanta mcp-shell-server como subproceso stdio
# y lo expone como servidor SSE en 0.0.0.0:$MCP_PORT.
# Se invoca el entry point de consola "mcp-shell-server" (el que
# instala pip), no "python -m mcp_shell_server.server": ese módulo
# no está pensado para ejecutarse así y cierra el stdio al arrancar.
# --pass-environment es obligatorio: por defecto mcp-proxy NO hereda
# el entorno del contenedor hacia el subproceso, así que sin esto
# ALLOW_COMMANDS nunca le llega a mcp-shell-server.
ENTRYPOINT ["sh", "-c", "mcp-proxy --pass-environment --port=${MCP_PORT} --host=0.0.0.0 -- mcp-shell-server"]
