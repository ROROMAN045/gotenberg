#!/bin/bash
# ── Publicar Gotenberg en el VPS: el commit que ya tiene este directorio ─────
#
# Lo ejecuta el desplegador del VPS (materdev-infra/vps/despliegue/desplegar.sh)
# después de poner /opt/materdev/gotenberg en el commit nuevo de main, y sólo si
# GitHub lo compiló bien. Se publica con el botón de GitHub (Actions → «Publicar»).
# Gotenberg no guarda datos: no hay secretos ni copia previa.
#
# La primera vez hace además el RELEVO: hasta 2026-11, Gotenberg vivía dentro
# del proyecto Compose de domus. Si ese contenedor sigue ahí, se para y se
# renombra a gotenberg-viejo para dejar libre el nombre. Si el nuevo no queda
# sano, se quita y el viejo vuelve con su nombre: la publicación se da por fallida.
#
# ESPEJO=1 (sólo para probar en el Mac): sin sudo. MATERDEV cambia la raíz.
set -euo pipefail
cd "$(dirname "$0")/.."
MATERDEV="${MATERDEV:-/opt/materdev}"
if [ -n "${ESPEJO:-}" ]; then SUDO=""; else SUDO="sudo"; fi

docker network inspect domus-gotenberg >/dev/null 2>&1 \
  || { echo "Falta la red domus-gotenberg: publica antes materdev-infra (vps/instalar.sh la crea)." >&2; exit 1; }

# Mientras dura, el vigilante no "cura" contenedores que se están sustituyendo.
$SUDO touch "$MATERDEV/MANTENIMIENTO"
trap '$SUDO rm -f "$MATERDEV/MANTENIMIENTO"' EXIT

proyecto_de() { docker inspect -f '{{index .Config.Labels "com.docker.compose.project"}}' "$1" 2>/dev/null || true; }

relevo=0
volver_atras() {
  # Sin trampa ni -e: aquí cada paso se intenta aunque falle el anterior. Lo
  # que importa es que el Gotenberg viejo vuelva a estar en marcha.
  trap - ERR
  set +e
  echo "✗ $1. Vuelvo al Gotenberg de domus." >&2
  docker compose down >/dev/null 2>&1
  local c
  for c in gotenberg gotenberg-salida; do
    [ "$(proyecto_de "$c")" = gotenberg ] && docker rm -f "$c" >/dev/null 2>&1
  done
  docker inspect gotenberg-viejo >/dev/null 2>&1 && docker rename gotenberg-viejo gotenberg
  docker start gotenberg >/dev/null || echo "  ¡OJO! El Gotenberg viejo no arranca: mira «docker ps -a» en el VPS." >&2
  echo "  Gotenberg de domus en marcha otra vez." >&2
  exit 1
}

# ponytail: el relevo sólo actúa una vez (la noche del corte); se puede borrar después.
if [ "$(proyecto_de gotenberg)" = domus ]; then
  echo "▸ relevo: el Gotenberg del proyecto domus pasa a este proyecto"
  docker stop gotenberg >/dev/null
  relevo=1
  trap 'volver_atras "falló la línea $LINENO"' ERR
  docker rename gotenberg gotenberg-viejo
fi

if ! docker compose up -d --remove-orphans; then
  [ "$relevo" = 1 ] && volver_atras "docker compose up falló"
  exit 1
fi

# Sano = su propio healthcheck (curl a /health dentro del contenedor). Su
# salida (gotenberg-salida) ya está sana: compose no lo arranca antes.
sano=0
for _ in $(seq 1 45); do
  [ "$(docker inspect -f '{{.State.Health.Status}}' gotenberg 2>/dev/null || true)" = healthy ] && { sano=1; break; }
  sleep 2
done
if [ "$sano" = 0 ]; then
  [ "$relevo" = 1 ] && volver_atras "Gotenberg no queda sano en 90 s"
  echo "Gotenberg no queda sano en 90 s." >&2
  exit 1
fi
trap - ERR
[ "$relevo" = 1 ] && echo "relevo hecho: gotenberg-viejo queda parado hasta que domus se publique sin Gotenberg."
docker compose ps --format 'table {{.Name}}\t{{.Status}}'
