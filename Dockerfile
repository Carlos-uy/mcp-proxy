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
#
# Nota de procedencia: este Dockerfile NO deriva del oficial de
# tumf/mcp-shell-server (https://github.com/tumf/mcp-shell-server/
# blob/main/Dockerfile) — ese solo hace `pip install .` desde su
# propio código fuente y corre por stdio puro, sin SSE ni soporte
# para múltiples servidores. Acá se usa el paquete publicado en
# PyPI como una pieza más de un stack distinto (mcp-proxy + varios
# servidores nombrados vía servers.json). Ningún bloque de abajo
# está tomado de ese archivo; es un diseño propio de punta a punta.
# ─────────────────────────────────────────────────────────────
FROM python:3.13-slim AS base

WORKDIR /app

# Dependencias mínimas de sistema. python:3.13-slim viene sin wget,
# curl NI unzip — este bloque tiene que ir ANTES de cualquier RUN que
# los necesite (Katana más abajo usa curl+unzip).
# ca-certificates: TLS para cscli. curl+gnupg: setup de NodeSource.
# unzip: para descomprimir el binario de Katana.
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl gnupg unzip \
    && mkdir -p /etc/apt/keyrings \
    && curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/*

# ─────────────────────────────────────────────────────────────
# Katana — crawler activo de ProjectDiscovery para extracción de
# endpoints (incluye los que solo aparecen en JavaScript, no
# linkeados en el HTML). Repo: https://github.com/projectdiscovery/katana
# Manual/flags: https://docs.projectdiscovery.io/tools/katana/overview
#
# Resuelve "latest" DINÁMICAMENTE en cada build, pero sin pasar por
# la API REST (api.github.com/repos/.../releases/latest) — esa API
# tiene rate limit de 60 requests/hora sin autenticar por IP, y se
# agota rápido con varios rebuilds seguidos. En cambio, se sigue el
# redirect propio de la página de releases (github.com, no la API),
# que no comparte ese límite: /releases/latest redirige a
# /releases/tag/<version-real>, de ahí se saca el tag y se arma la
# URL de descarga del asset directo — el binario que se instala
# siempre es la versión que esté publicada como "latest" en ese
# momento, no una fija.
#
# Usa curl (no wget) porque curl ya se instaló arriba para Node.js —
# evita sumar una segunda herramienta que hace lo mismo.
# ─────────────────────────────────────────────────────────────
RUN KATANA_TAG=$(curl -fsSL -o /dev/null -w '%{url_effective}' https://github.com/projectdiscovery/katana/releases/latest | grep -oE '[^/]+$') \
    && KATANA_VERSION="${KATANA_TAG#v}" \
    && curl -fsSL -o /tmp/katana.zip "https://github.com/projectdiscovery/katana/releases/download/${KATANA_TAG}/katana_${KATANA_VERSION}_linux_amd64.zip" \
    && unzip /tmp/katana.zip -d /usr/local/bin katana \
    && chmod +x /usr/local/bin/katana \
    && rm /tmp/katana.zip

# Copiamos SOLO el binario cscli desde la imagen oficial.
# No pasa por apt/dpkg, no queda vendorizado en este repo:
# la próxima vez que se reconstruya esta imagen con --pull,
# se trae automáticamente la versión que sea "latest" en Docker Hub.
COPY --from=crowdsec-src /usr/local/bin/cscli /usr/local/bin/cscli
RUN chmod +x /usr/local/bin/cscli

# mcp-proxy: bridge stdio -> SSE/HTTP
# mcp-shell-server: ejecuta el comando whitelisteado (cscli) vía stdio
# httpx: cliente HTTP usado por el server MCP de Telegram (envío de
# medios, descargas pinneadas) — repo: https://github.com/encode/httpx
# boto3: SDK de AWS/S3, quedó de un intento anterior con RustFS que
# se descartó (ver historial) — candidato a sacar si no se usa más.
RUN pip install --no-cache-dir mcp-proxy mcp-shell-server httpx boto3

# uv/uvx: equivalente Python de "npx" — crea entornos efímeros al vuelo
# para correr paquetes sin instalarlos globalmente. Necesario para
# cualquier servidor MCP futuro que se invoque como "uvx <paquete>".
RUN pip install --no-cache-dir uv

# ─────────────────────────────────────────────────────────────
# Nmap — escaneo de puertos/servicios para el server MCP de red.
# Repo: https://github.com/nmap/nmap · Manual: https://nmap.org/book/man.html
# Instalado vía apt (Debian empaqueta una versión estable, no "latest"
# como Katana/cscli arriba — para una versión más nueva habría que
# compilar desde el repo en vez de usar el paquete de Debian).
# Modos -sS/-O (privilegiados) además necesitan cap_add: [NET_RAW,
# NET_ADMIN] en el compose — no alcanza con instalar el binario.
# ─────────────────────────────────────────────────────────────
RUN apt-get update && apt-get install -y --no-install-recommends nmap && rm -rf /var/lib/apt/lists/*

# Puerto donde mcp-proxy expone todos los servidores por SSE/HTTP.
# Referenciado más abajo por EXPOSE y por el ENTRYPOINT — cambiarlo
# acá alcanza para que ambos usos queden consistentes.
ENV MCP_PORT=8000

# servers.json es el default de fallback horneado en la imagen.
# En producción se monta por volumen desde la NAS
# (/DATA/AppData/mcp-crowdsec-gateway/servers.json -> /app/servers.json),
# así que agregar/ajustar servidores o su ALLOW_COMMANDS no requiere
# rebuild: solo editar el archivo en la NAS y reiniciar el contenedor.
COPY servers.json /app/servers.json

# Debe coincidir con el valor de MCP_PORT de arriba — EXPOSE es solo
# documentación para quien lea/use la imagen (no abre el puerto por
# sí mismo), el bind real lo hace mcp-proxy vía --port en el ENTRYPOINT.
EXPOSE 8000

# mcp-proxy lee servers.json y levanta cada servidor nombrado como
# subproceso stdio, exponiéndolos por SSE en:
#   http://0.0.0.0:$MCP_PORT/servers/<nombre>/sse
# --pass-environment reenvía variables del contenedor a los subprocesos
# (por ejemplo CROWDSEC_LAPI_URL); el ALLOW_COMMANDS de cada servidor
# ya viene definido en su propio bloque "env" dentro de servers.json.
ENTRYPOINT ["sh", "-c", "mcp-proxy --pass-environment --port=${MCP_PORT} --host=0.0.0.0 --named-server-config /app/servers.json"]
