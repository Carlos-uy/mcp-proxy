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

# Dependencias mínimas de sistema: ca-certificates, curl, unzip, xz-utils
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl unzip xz-utils \
    && rm -rf /var/lib/apt/lists/*

# Node.js — instala siempre la última versión LTS disponible
RUN NODE_VERSION=$(python3 -c "import json, urllib.request; data = json.load(urllib.request.urlopen('https://nodejs.org/dist/index.json')); print(next(r['version'] for r in data if r['lts']))") \
    && echo "Instalando Node.js ${NODE_VERSION} (última LTS)" \
    && curl -fsSL -o /tmp/node.tar.xz "https://nodejs.org/dist/${NODE_VERSION}/node-${NODE_VERSION}-linux-x64.tar.xz" \
    && tar -xJf /tmp/node.tar.xz -C /usr/local --strip-components=1 \
    && rm /tmp/node.tar.xz \
    && node --version && npm --version

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

# ─────────────────────────────────────────────────────────────
# Subfinder — enumeración PASIVA de subdominios (ProjectDiscovery),
# nunca toca el dominio en sí. Repo: https://github.com/projectdiscovery/subfinder
# Mismo patrón que Katana: resuelve "latest" por el redirect de
# github.com (no la API, evita su rate limit). Funciona sin API key;
# para más cobertura acepta claves opcionales en provider-config.yaml.
# ─────────────────────────────────────────────────────────────
RUN SUBFINDER_TAG=$(curl -fsSL -o /dev/null -w '%{url_effective}' https://github.com/projectdiscovery/subfinder/releases/latest | grep -oE '[^/]+$') \
    && SUBFINDER_VERSION="${SUBFINDER_TAG#v}" \
    && curl -fsSL -o /tmp/subfinder.zip "https://github.com/projectdiscovery/subfinder/releases/download/${SUBFINDER_TAG}/subfinder_${SUBFINDER_VERSION}_linux_amd64.zip" \
    && unzip /tmp/subfinder.zip -d /usr/local/bin subfinder \
    && chmod +x /usr/local/bin/subfinder \
    && rm /tmp/subfinder.zip

# ─────────────────────────────────────────────────────────────
# ffuf — fuerza bruta de rutas/archivos para el server MCP de red
# (net_ffuf_scan). Repo: https://github.com/ffuf/ffuf
# Flags: https://github.com/ffuf/ffuf/wiki/Usage-and-examples
#
# Mismo patrón que Katana/Subfinder arriba: resuelve "latest" siguiendo
# el redirect de /releases/latest (no la API REST, por el rate limit de
# 60 req/hora sin autenticar). OJO: a diferencia de Katana/Subfinder, el
# asset de ffuf es .tar.gz, no .zip — se verificó el patrón de nombre
# contra el .goreleaser.yml oficial del repo (name_template de la
# sección "archives") y contra el listado real de assets de una release
# publicada: ffuf_<version>_linux_amd64.tar.gz (sin "v" en la versión).
# Se extrae con tar (ya disponible en la imagen base de Debian, no hace
# falta instalarlo), no con unzip.
# ─────────────────────────────────────────────────────────────
RUN FFUF_TAG=$(curl -fsSL -o /dev/null -w '%{url_effective}' https://github.com/ffuf/ffuf/releases/latest | grep -oE '[^/]+$') \
    && FFUF_VERSION="${FFUF_TAG#v}" \
    && curl -fsSL -o /tmp/ffuf.tar.gz "https://github.com/ffuf/ffuf/releases/download/${FFUF_TAG}/ffuf_${FFUF_VERSION}_linux_amd64.tar.gz" \
    && tar -xzf /tmp/ffuf.tar.gz -C /usr/local/bin ffuf \
    && chmod +x /usr/local/bin/ffuf \
    && rm /tmp/ffuf.tar.gz

# ─────────────────────────────────────────────────────────────
# httpx (ProjectDiscovery) — toolkit de recon HTTP a escala para el server
# MCP de red (net_httpx_probe). Repo: https://github.com/projectdiscovery/httpx
#
# ⚠️ NO CONFUNDIR con el paquete Python "httpx" (encode/httpx) instalado
# más abajo para el MCP de Telegram — son dos proyectos sin relación que
# comparten nombre por casualidad. Este es un binario Go que queda en
# /usr/local/bin/httpx; el otro es una librería que vive en site-packages
# de Python. Conviven sin conflicto real (namespaces distintos), esta nota
# es solo para que no confunda a quien lea este archivo después.
#
# Mismo patrón que Katana/Subfinder: resuelve "latest" siguiendo el
# redirect de /releases/latest (no la API REST, por el rate limit de 60
# req/hora sin autenticar). Asset .zip, verificado contra un listado real
# de release: httpx_<version>_linux_amd64.zip.
# ─────────────────────────────────────────────────────────────
RUN HTTPX_TAG=$(curl -fsSL -o /dev/null -w '%{url_effective}' https://github.com/projectdiscovery/httpx/releases/latest | grep -oE '[^/]+$') \
    && HTTPX_VERSION="${HTTPX_TAG#v}" \
    && curl -fsSL -o /tmp/httpx.zip "https://github.com/projectdiscovery/httpx/releases/download/${HTTPX_TAG}/httpx_${HTTPX_VERSION}_linux_amd64.zip" \
    && unzip /tmp/httpx.zip -d /usr/local/bin httpx \
    && chmod +x /usr/local/bin/httpx \
    && rm /tmp/httpx.zip

# ─────────────────────────────────────────────────────────────
# naabu (ProjectDiscovery) — port scanner SYN/CONNECT de alta velocidad
# para el server MCP de red (net_naabu_scan). Repo: https://github.com/projectdiscovery/naabu
# Pensado como descubrimiento rápido de puertos abiertos en rangos grandes,
# complementario a nmap (que sigue siendo quien hace -sV/-O con detalle,
# vía net_nmap_scan, una vez que naabu ya encontró qué puertos están
# abiertos).
#
# Mismo patrón de resolución de "latest" + asset .zip que los anteriores,
# verificado: naabu_<version>_linux_amd64.zip.
#
# El modo SYN (el rápido) necesita root + cap_add: [NET_RAW, NET_ADMIN] en
# el compose — las mismas capabilities que ya usás, opcionalmente, para
# NET_ENABLE_NMAP_PRIVILEGED. Sin esas capabilities, naabu sigue
# funcionando en modo CONNECT (sin privilegios), solo que más lento y más
# fácil de detectar. Gateado además en la app por NET_ENABLE_NAABU_PRIVILEGED
# (ver network-mcp_server.py) — el cap_add del contenedor es necesario pero
# no suficiente, hace falta el opt-in explícito también en la config.
# ─────────────────────────────────────────────────────────────
RUN NAABU_TAG=$(curl -fsSL -o /dev/null -w '%{url_effective}' https://github.com/projectdiscovery/naabu/releases/latest | grep -oE '[^/]+$') \
    && NAABU_VERSION="${NAABU_TAG#v}" \
    && curl -fsSL -o /tmp/naabu.zip "https://github.com/projectdiscovery/naabu/releases/download/${NAABU_TAG}/naabu_${NAABU_VERSION}_linux_amd64.zip" \
    && unzip /tmp/naabu.zip -d /usr/local/bin naabu \
    && chmod +x /usr/local/bin/naabu \
    && rm /tmp/naabu.zip

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

# Librerías del server WebScraper: trafilatura (texto limpio + metadata),
# extruct (datos estructurados: JSON-LD/Open Graph), beautifulsoup4+lxml
# (links/tablas/imágenes de la página). httpx ya está arriba, no se repite.
RUN pip install --no-cache-dir trafilatura extruct beautifulsoup4 lxml lxml-html-clean

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
