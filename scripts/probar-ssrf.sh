#!/bin/bash
# ── Prueba de seguridad: lo que llega por /pdf-proxy/ es HTML de cualquiera ──
#
# Levanta este docker-compose.yml tal cual (proyecto «prueba-ssrf», con otros
# nombres de contenedor y una red de prueba en lugar de domus-gotenberg) y una
# «víctima» interna (un nginx) a la que se intenta llegar por nombre, por IP,
# por IP con usuario y por un DNS que apunta a ella. Comprueba que:
#   · ningún intento llega a la víctima, ni desde Chromium ni a mano por el proxy;
#   · lo local del contenedor (API de Gotenberg, puerto de depuración de
#     Chromium) no sale en el PDF, ni en un iframe ni redirigiendo la página;
#   · Gotenberg no tiene salida directa a internet;
#   · ni file:///etc/passwd ni los listados de /tmp salen en el PDF;
#   · el JavaScript no corre;
#   · un PDF normal sí trae las fuentes de Google, el QR de api.qrserver.com
#     y una imagen data: (así van los logos de los PDF de reservas).
#
# Necesita Docker e internet. Lo corre «Compilar». En el Mac:
#   bash scripts/probar-ssrf.sh
set -euo pipefail
cd "$(dirname "$0")/.."
P=prueba-ssrf
# Víctima y lector de PDF: la misma imagen fijada que n8n-nginx.
NGINX=nginx:1.31.8-alpine@sha256:785835ea65db4bba6f021acc0f3be91b0fef76a53fe41f8588c6698d2aed0606
DIR="$(mktemp -d)"
COMPOSE=(docker compose -p "$P" -f docker-compose.yml -f "$DIR/prueba.yml")

limpiar() {
  "${COMPOSE[@]}" down -v --remove-orphans >/dev/null 2>&1 || true
  docker rm -f "$P-victima" "$P-texto" >/dev/null 2>&1 || true
  docker network rm "$P-par" >/dev/null 2>&1 || true
  rm -rf "$DIR"
}
trap limpiar EXIT
limpiar 2>/dev/null; mkdir -p "$DIR"

{
  echo "services:"
  echo "  gotenberg: {container_name: $P-gotenberg}"
  if docker compose -f docker-compose.yml config --services | grep -cx gotenberg-salida >/dev/null; then
    echo "  gotenberg-salida: {container_name: $P-salida}"
  fi
  echo "networks:"
  echo "  domus-gotenberg: {name: $P-par}"
} > "$DIR/prueba.yml"

# La red de la pareja, interna como la crea materdev-infra; la víctima hace de
# domus-nginx (está en ella) y responde también como «evil.prueba».
docker network create --internal "$P-par" >/dev/null
docker run -d --name "$P-victima" --network "$P-par" --network-alias evil.prueba "$NGINX" >/dev/null
docker run -d --name "$P-texto" -v "$DIR:/d:ro" --entrypoint sh "$NGINX" \
  -c 'apk add -q poppler-utils >/dev/null && touch /listo && sleep 600' >/dev/null
"${COMPOSE[@]}" up -d --wait --quiet-pull
echo "▸ Gotenberg arranca con: $(docker inspect -f "{{range .Args}}{{.}} {{end}}" "$P-gotenberg")"
# Y en la red por la que sale el proxy, con el mismo nombre falso: así se
# prueba un DNS de fuera que apunta a una IP interna.
docker network connect --alias evil.prueba "${P}_default" "$P-victima" 2>/dev/null || true
VIP="$(docker inspect -f "{{(index .NetworkSettings.Networks \"$P-par\").IPAddress}}" "$P-victima")"
VIP_FUERA="$(docker inspect -f "{{with index .NetworkSettings.Networks \"${P}_default\"}}{{.IPAddress}}{{end}}" "$P-victima")"
for _ in $(seq 1 60); do docker exec "$P-texto" test -f /listo 2>/dev/null && break; sleep 1; done

fallos=0
bien() { echo "  ✓ $*"; }
mal() { echo "  ✗ $*"; fallos=$((fallos + 1)); }
# pdf NOMBRE < HTML: convierte como lo hace domus y deja el texto en $DIR/NOMBRE.txt.
# Con PUEDE_FALLAR=1, que Gotenberg rechace la conversión también vale.
pdf() {
  : > "$DIR/$1.txt"
  if ! docker exec -i "$P-gotenberg" curl -sf -F 'files=@-;filename=index.html' \
      http://127.0.0.1:3000/forms/chromium/convert/html > "$DIR/$1.pdf"; then
    [ -n "${PUEDE_FALLAR:-}" ] || mal "$1: Gotenberg no devolvió PDF"
    return 0
  fi
  docker exec "$P-texto" pdftotext "/d/$1.pdf" - > "$DIR/$1.txt"
}
golpes() { docker logs "$P-victima" 2>&1 | grep -cE '"(GET|POST|HEAD|CONNECT) ' || true; }

echo "▸ PDF normal (fuentes de Google y QR)"
pdf normal <<'HTML'
<html><head><link href="https://fonts.googleapis.com/css2?family=DM+Sans:wght@400;700&display=swap" rel="stylesheet">
<style>body{font-family:'DM Sans'}</style></head>
<body>FACTURA-DE-PRUEBA <img src="https://api.qrserver.com/v1/create-qr-code/?size=150x150&data=prueba">
<img src="data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAHgAAAB4CAIAAAC2BqGFAAAA60lEQVR4nO3QAQkAIBDAQLN8/yiGsoXCPFiAcWvP6ELr+cEngQbdCjToVqBBtwINuhVo0K1Ag24FGnQr0KBbgQbdCjToVqBBtwINuhVo0K1Ag24FGnQr0KBbgQbdCjToVqBBtwINuhVo0K1Ag24FGnQr0KBbgQbdCjToVqBBtwINuhVo0K1Ag24FGnQr0KBbgQbdCjToVqBBtwINuhVo0K1Ag24FGnQr0KBbgQbdCjToVqBBtwINuhVo0K1Ag24FGnQr0KBbgQbdCjToVqBBtwINuhVo0K1Ag24FGnQr0KBbgQbdCjToVqBBtzrSP8d202hkaAAAAABJRU5ErkJggg=="></body></html>
HTML
grep -q FACTURA-DE-PRUEBA "$DIR/normal.txt" && bien "sale el PDF" || mal "no sale el texto del PDF"
docker exec "$P-texto" pdffonts "/d/normal.pdf" | grep -ci DMSans >/dev/null && bien "con la fuente de Google" || mal "sin la fuente de Google"
# El QR pedido es de 150×150 (el icono de imagen rota no lo es).
docker exec "$P-texto" pdfimages -list "/d/normal.pdf" | awk '$4 == 150 && $5 == 150 { ok = 1 } END { exit !ok }' \
  && bien "con el QR" || mal "sin el QR"
docker exec "$P-texto" pdfimages -list "/d/normal.pdf" | awk '$4 == 120 && $5 == 120 { ok = 1 } END { exit !ok }' \
  && bien "con la imagen data:" || mal "sin la imagen data:"

echo "▸ Lo local del contenedor (API de Gotenberg y depuración de Chromium)"
# Chromium ya está en marcha: su puerto de depuración (aleatorio) escucha en 127.0.0.1.
DEPURA="$(docker exec "$P-gotenberg" awk 'NR > 1 && $4 == "0A" && $2 ~ /^0100007F:/ { split($2, a, ":"); print a[2]; exit }' /proc/net/tcp)"
DEPURA="$((16#${DEPURA:-0}))"
locales=""
for u in "http://127.0.0.1:3000/health" "http://localhost:3000/health" "http://x@127.0.0.1:3000/health" \
         "http://[::1]:3000/health" "http://0.0.0.0:3000/health" "http://a.localhost:3000/health" \
         "http://127.0.0.1:$DEPURA/json/list"; do
  locales="$locales<iframe src=\"$u\" width=\"900\" height=\"300\"></iframe>"
done
pdf locales <<<"<html><body>LOCALES $locales</body></html>"
grep -qiE 'status|webSocketDebuggerUrl|devtools' "$DIR/locales.txt" && mal "sale algo local en el PDF" || bien "en un iframe, nada"
for u in "http://127.0.0.1:3000/health" "http://x@localhost:3000/health" "http://127.0.0.1:$DEPURA/json/list"; do
  PUEDE_FALLAR=1 pdf salto <<<"<html><head><meta http-equiv=\"refresh\" content=\"0;url=$u\"></head><body>SALTO</body></html>"
  grep -qiE 'status|webSocketDebuggerUrl|devtools' "$DIR/salto.txt" && mal "redirigiendo a $u sale en el PDF" || bien "redirigiendo a $u, nada"
done

echo "▸ JavaScript"
pdf js <<'HTML'
<html><body>SIN-JS<script>document.body.innerHTML += ' JS-ACTIVO'</script></body></html>
HTML
grep -q JS-ACTIVO "$DIR/js.txt" && mal "el JavaScript corre" || bien "no corre"

echo "▸ Ficheros locales"
pdf ficheros <<'HTML'
<html><body>FICHEROS
<iframe src="file:///etc/passwd"></iframe><iframe src="file:///tmp/"></iframe>
<iframe src="./"></iframe><iframe src="../"></iframe><iframe src="./?x"></iframe></body></html>
HTML
grep -q 'root:' "$DIR/ficheros.txt" && mal "se lee /etc/passwd" || bien "/etc/passwd no sale"
grep -qiE 'Index of|[0-9a-f]{8}-[0-9a-f]{4}-' "$DIR/ficheros.txt" && mal "sale un listado de /tmp" || bien "no sale ningún listado de /tmp"

echo "▸ Víctima interna (como domus-nginx), desde el HTML"
antes="$(golpes)"
pdf victima <<HTML
<html><body>VICTIMA
<iframe src="http://evil.prueba/"></iframe><iframe src="http://evil.prueba./"></iframe>
<iframe src="http://$VIP/"></iframe><iframe src="http://x@$VIP/"></iframe>
<iframe src="http://$P-victima/"></iframe><img src="http://evil.prueba/img.png">
<link rel="stylesheet" href="https://evil.prueba/x.css"></body></html>
HTML
[ "$(golpes)" = "$antes" ] && bien "no le llega nada" || mal "le llegan $(( $(golpes) - antes )) peticiones"
grep -qi 'Welcome to nginx' "$DIR/victima.txt" && mal "su página sale en el PDF" || bien "su página no sale en el PDF"

echo "▸ La red, a mano desde el contenedor de Gotenberg"
if docker exec "$P-gotenberg" curl -s -o /dev/null -m 8 https://example.com; then
  mal "sale a internet sin el proxy"
else
  bien "sin salida directa a internet"
fi
if docker compose -f docker-compose.yml config --services | grep -cx gotenberg-salida >/dev/null; then
  por_proxy() { docker exec "$P-gotenberg" curl -s -o /dev/null -m 15 -w '%{http_code}' -x http://gotenberg-salida:3128 "$1" || true; }
  [ "$(por_proxy https://example.com)" = 200 ] && bien "por el proxy, internet sí" || mal "por el proxy no llega a internet"
  for u in http://evil.prueba/ "http://$VIP_FUERA/" http://127.0.0.1:3128/ http://169.254.169.254/; do
    c="$(por_proxy "$u")"; [ "$c" = 403 ] && bien "por el proxy, $u: 403" || mal "por el proxy, $u: $c (debe ser 403)"
  done
else
  mal "no hay proxy de salida (gotenberg-salida)"
fi

echo
if [ "$fallos" = 0 ]; then echo "Todo bien."; else echo "$fallos fallos."; exit 1; fi
