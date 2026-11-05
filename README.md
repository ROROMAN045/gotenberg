# gotenberg

Conversión HTML → PDF ([Gotenberg](https://gotenberg.dev)) para los proyectos de
MaterDev: un servicio propio del VPS. Hasta noviembre de 2026 vivía dentro de domus.
Diseño: `materdev-infra/docs/superpowers/specs/2026-11-05-aislar-n8n-gotenberg-design.md`.

| | |
|---|---|
| VPS | `/opt/materdev/gotenberg` (proyecto Compose `gotenberg`) |
| Contenedores | `gotenberg`, **sin puertos** y sin entrada pública; `gotenberg-salida` (squid), su única salida a internet |
| Datos | ninguno (no hay respaldo ni secretos) |

## Quién lo usa y cómo

Cada proyecto que lo usa tiene **su propia red de Docker**, interna, creada por
materdev-infra (`vps/instalar.sh` y `mac/espejo/espejo.sh`).

| Red | Quién | Cómo |
|---|---|---|
| `domus-gotenberg` | `domus-nginx` | `http://gotenberg:3000`, detrás de `/pdf-proxy/` de domus: sólo `forms/chromium/convert/html`, con límite por IP |

Un proyecto nuevo: red `<proyecto>-gotenberg` en materdev-infra y añadirla aquí en
`networks`.

## Seguridad

Lo que llega por `/pdf-proxy/` de domus es HTML de cualquiera, y Chromium carga lo
que diga. Las capas, explicadas en `docker-compose.yml`:

1. **Sin salida directa.** Todas sus redes son internas. A internet (fuentes de
   Google, QR, logos de las firmas) solo sale por `gotenberg-salida`, un squid que
   niega toda IP privada **después** de resolver el DNS (`squid/squid.conf`).
2. **Sin JavaScript.** Ningún PDF lo usa.
3. **Ficheros:** solo los de la propia petición, sin listados de carpetas.
4. **Lo local del contenedor** (`localhost`, `127.x`, IPv6…), adonde Chromium va sin
   proxy, está bloqueado en la lista de Gotenberg.

`scripts/probar-ssrf.sh` lo prueba todo de verdad: levanta este compose con una
«víctima» interna e intenta llegar a ella y a lo local. Corre en «Compilar», y
en el Mac con `bash scripts/probar-ssrf.sh`. Si se sube de versión Gotenberg o
squid, la prueba tiene que seguir pasando.

## Publicar

Como todo: rama → Pull Request → «Compilar» en verde → merge → Actions → «Publicar».
El VPS lo recoge (`materdev-infra/vps/despliegue/desplegar.sh`) y ejecuta
`scripts/publicar-en-vps.sh`, que da la publicación por buena solo si los dos
contenedores quedan `healthy`. Una versión nueva se prueba antes en el espejo con PDF
reales de domus.
