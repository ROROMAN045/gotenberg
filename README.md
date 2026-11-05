# gotenberg

Conversión HTML → PDF ([Gotenberg](https://gotenberg.dev)) para los proyectos de
MaterDev: un servicio propio del VPS. Hasta noviembre de 2026 vivía dentro de domus.
Diseño: `materdev-infra/docs/superpowers/specs/2026-11-05-aislar-n8n-gotenberg-design.md`.

| | |
|---|---|
| VPS | `/opt/materdev/gotenberg` (proyecto Compose `gotenberg`) |
| Contenedor | `gotenberg`, **sin puertos** y sin entrada pública |
| Datos | ninguno (no hay respaldo ni secretos) |

## Quién lo usa y cómo

Cada proyecto que lo usa tiene **su propia red de Docker**, creada por materdev-infra
(`vps/instalar.sh` y `mac/espejo/espejo.sh`). Gotenberg sólo ve a quien está en
sus redes: Chromium carga lo que diga el HTML, así que cuanto menos vea, mejor.

| Red | Quién | Cómo |
|---|---|---|
| `domus-gotenberg` | `domus-nginx` | `http://gotenberg:3000`, detrás de `/pdf-proxy/` de domus: sólo `forms/chromium/convert/html`, con límite por IP |

Un proyecto nuevo: red `<proyecto>-gotenberg` en materdev-infra y añadirla aquí en
`networks`.

## Publicar

Como todo: rama → Pull Request → «Compilar» en verde → merge → Actions → «Publicar».
El VPS lo recoge (`materdev-infra/vps/despliegue/desplegar.sh`) y ejecuta
`scripts/publicar-en-vps.sh`, que da la publicación por buena sólo si el
contenedor queda `healthy`. Una versión nueva se prueba antes en el espejo con PDF
reales de domus.
