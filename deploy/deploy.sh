#!/usr/bin/env bash
# Deploy av Torget till servern. Kör från repo-roten: deploy/deploy.sh
#
# Servern anges i den här ordningen:  HOST=root@<ip>  →  filen .deploy-host (gitignorerad)  →  avbryt.
# Domänen läses ur .board-url. Port, tjänstenamn och kataloger är instämplade när repot byggdes ur
# workshopladans mall, och går att åsidosätta med en miljövariabel för en enskild körning.
# Ingen adress och ingen nyckel ligger i repot: det här skriptet är en mall, inte en konfiguration.
#
# Förutsätter: ssh fungerar mot servern, node och Caddy finns där (workshopladan: verktyg/provisionera.sh).
# DNS (domänen -> serverns IP) måste finnas innan Caddy kan hämta certifikat.
set -euo pipefail
cd "$(dirname "$0")/.."

HOST="${HOST:-$( [ -f .deploy-host ] && tr -d '[:space:]' < .deploy-host || echo '' )}"
[ -n "$HOST" ] || { cat >&2 <<'TXT'
Ingen server angiven. Två vägar:
  HOST=root@<ip> deploy/deploy.sh
  printf 'root@<ip>\n' > .deploy-host      (gitignorerad, ligger kvar till nästa gång)
Kör du release-varv under dagen måste .deploy-host finnas i repo-roten du kör dem från.
TXT
exit 2; }
BOARD_URL="$(tr -d '[:space:]' < .board-url 2>/dev/null || echo '')"
DOMAN="${DOMAN:-$(printf %s "$BOARD_URL" | sed -E 's#^https?://##; s#/.*##')}"
# Värdena nedan stämplas in av workshopladans verktyg/deltagarrepo.sh. Står platshållaren kvar är
# repot inte byggt ur mallen, och då gäller samma reservvärden som provisioneringen använder.
PORT="${PORT:-8180}";                            case "$PORT"          in *[!0-9]*|'') PORT=8180;; esac
TJANST="${TJANST:-torget}";                      case "$TJANST"        in *_*|'')     TJANST=torget;; esac
SERVERKATALOG="${SERVERKATALOG:-/opt/torget}"; case "$SERVERKATALOG" in /*) ;; *)   SERVERKATALOG=/opt/torget;; esac
DATAKATALOG="${DATAKATALOG:-/var/lib/torget}";       case "$DATAKATALOG"   in /*) ;; *)   DATAKATALOG=/var/lib/torget;; esac
[ -n "$DOMAN" ] || { echo "Ingen domän i .board-url. Skriv adressen till Torget där, till exempel https://torget.example.com" >&2; exit 2; }

echo "→ $HOST  ($DOMAN, port $PORT, tjänst $TJANST)"
# Qr-koden är gitignorerad och finns alltså inte i en färsk klon. Utan undantaget nedan raderar
# --delete den från servern vid dagens första release-deploy, och storskärmen tappar sin qr-kod.
rsync -az --delete --exclude data --exclude qr.png --exclude qr.svg board/ "$HOST:$SERVERKATALOG/"
# Enhetsfilen är redan stämplad. Sed:a inte om den här. Förr stod portens platshållare som sökmönster
# på den här raden, blev själv instämplad, och skrev sedan över porten med ett annat värde.
scp -q deploy/torget.service "$HOST:/etc/systemd/system/$TJANST.service"
ssh "$HOST" "set -e
  mkdir -p $DATAKATALOG && chown www-data:www-data $DATAKATALOG
  systemctl daemon-reload && systemctl enable --now $TJANST && systemctl restart $TJANST
  if ! grep -q '$DOMAN' /etc/caddy/Caddyfile 2>/dev/null; then
    cat >> /etc/caddy/Caddyfile <<CADDY

$DOMAN {
        reverse_proxy localhost:$PORT {
                flush_interval -1
        }
}
CADDY
    systemctl reload caddy
  fi
  sleep 1; curl -s localhost:$PORT/api/health"
echo
echo "Klart: $HOST"
