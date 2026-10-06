#!/usr/bin/env bash
# Kollar att allt finns för att kunna vara med på workshopen. Kör från repo-roten:
#
#   tools/check-setup.sh
#
# Gör den här INNAN workshopdagen, inte på morgonen. Tre team kom aldrig in i staden förra gången,
# för att gh saknades eller inte var inloggat, och det upptäcktes först när koden var klar.
# Sista raden är gjord för att klistras in i svaret till workshopledaren.
set -uo pipefail
cd "$(dirname "$0")/.."
ok=0; fail=0; brister=""

ja()  { echo "  ok    $1"; ok=$((ok+1)); }
nej() { echo "  SAKNAS  $1"; [ -n "${2:-}" ] && echo "          $2"; fail=$((fail+1)); brister="$brister ${3:-}"; }

windows=0
case "$(uname -s 2>/dev/null)" in MINGW*|MSYS*|CYGWIN*) windows=1;; esac

echo "Agent"
agenter=""
if claude --version >/dev/null 2>&1; then ja "claude ($(claude --version 2>/dev/null | head -1))"; agenter="$agenter claude"; fi
if codex --version >/dev/null 2>&1; then ja "codex ($(codex --version 2>/dev/null | head -1))"; agenter="$agenter codex"; fi
if command -v copilot >/dev/null 2>&1; then
  agenter="$agenter copilot"
  ja "copilot ($(copilot --version 2>/dev/null | head -1))"
  # Copilot CLI kör agentens kommandon i PowerShell på Windows, och allt i tools/ är bash.
  # Git Bash hjälper inte: det är Copilots eget skal som räknas, inte terminalen du startar i.
  if [ "$windows" = 1 ]; then
    nej "GitHub Copilot direkt i Windows" "kör allt i WSL i stället (wsl --install), och klona repot i WSL-hemkatalogen. Se inbjudan." "wsl"
  fi
  # tools/copilot-godkann.sh, som förhandsgodkänner tavlans kommandon, är skriven i python3.
  if ! command -v python3 >/dev/null 2>&1; then
    nej "python3" "utan den frågar Copilot dig inför varje anrop till tavlan, och agenten kan inte lyssna själv. Installera python3." "python3"
  else
    # Copilot läser repots hook (.github/hooks/) först när mappen är betrodd. Utan den frågar agenten
    # människan inför varje anrop till tavlan, och då vaknar ingen agent när någon kallar till brainstorm.
    read -r -d '' TILLIT <<'PY' || true
import json, os, sys
rot = os.path.realpath(sys.argv[1])
try:
    d = json.load(open(os.path.expanduser('~/.copilot/config.json'), encoding='utf-8'))
    mappar = d.get('trustedFolders', d.get('trusted_folders'))
except Exception:
    mappar = None
if not isinstance(mappar, list):
    print('okänt')
else:
    for m in mappar:
        m = os.path.realpath(os.path.expanduser(str(m)))
        if rot == m or rot.startswith(m.rstrip('/') + '/'):
            print('ja')
            break
    else:
        print('nej')
PY
    case "$(python3 -c "$TILLIT" "$(pwd)" 2>/dev/null)" in
      ja)  ja "repot är betrott i Copilot (förhandsgodkännandet i .github/hooks läses)";;
      nej) nej "repot är inte betrott i Copilot" "starta copilot en gång här i repo-roten och svara ja på frågan om du litar på mappen" "copilot-tillit";;
      *)   echo "  ?     kunde inte se om repot är betrott i Copilot. Starta copilot en gång här i repo-roten och svara ja på frågan om tillit.";;
    esac
  fi
  # En riktig fråga, inte bara att programmet finns: den fångar utloggad, avstängd policy hos
  # organisationen och slut på krediter på en gång. Förra gången räckte det inte att gh fanns,
  # det måste vara inloggat. Samma sak här, fast för alla i rummet samtidigt.
  echo "  ..    provar Copilot med en kort fråga (några sekunder, en liten mängd krediter)"
  if command -v perl >/dev/null 2>&1; then
    svar=$(perl -e 'alarm 120; exec @ARGV' copilot -p "Svara med exakt ordet ok och gör ingenting annat." </dev/null 2>&1); rc=$?
  else
    svar=$(copilot -p "Svara med exakt ordet ok och gör ingenting annat." </dev/null 2>&1); rc=$?
  fi
  if [ "$rc" = 0 ] && printf '%s' "$svar" | grep -qiw ok; then
    ja "copilot svarar: inloggad, och organisationen släpper in dig"
  else
    printf '%s\n' "$svar" | grep -v '^[[:space:]]*$' | tail -3 | sed 's/^/          copilot: /'
    nej "copilot svarar inte på en provfråga" "inte inloggad: starta copilot och skriv /login. Står det något om policy eller organisation: be er Copilot-administratör slå på Copilot CLI." "copilot-login"
  fi
fi
if [ -z "$agenter" ]; then
  if [ "$windows" = 1 ]; then
    nej "ingen agent" "kör ni GitHub Copilot på Windows: gör allt i WSL, se inbjudan. Annars: installera Claude Code eller Codex och logga in." "agent"
  else
    nej "ingen agent" "installera GitHub Copilot CLI, Claude Code eller Codex och logga in, se inbjudan" "agent"
  fi
fi

echo "Verktyg"
command -v git  >/dev/null 2>&1 && ja "git"  || nej "git"  "" "git"
command -v curl >/dev/null 2>&1 && ja "curl" || nej "curl" "" "curl"
# node är valfritt och räknas inte som en brist: den som kör Copilot i WSL har ofta ingen, och ska inte få
# INTE KLAR för något som bara behövs för att köra Torget lokalt.
command -v node >/dev/null 2>&1 && ja "node ($(node -v 2>/dev/null))" || echo "  --    node saknas (valfritt, behövs bara om du vill köra Torget lokalt)"

if [ -n "$(git config user.email 2>/dev/null)" ] && [ -n "$(git config user.name 2>/dev/null)" ]; then
  ja "git-identitet ($(git config user.name))"
else
  nej "git-identitet" 'git config --global user.name "Ditt Namn" && git config --global user.email din@adress' "git-identitet"
fi

echo "Leverans (det som stoppade tre team förra gången)"
if ! command -v gh >/dev/null 2>&1; then
  nej "GitHub CLI (gh)" "installera från https://cli.github.com och kör sedan: gh auth login" "gh"
elif ! gh auth status >/dev/null 2>&1; then
  nej "gh är installerat men du är inte inloggad" "kör: gh auth login   (GitHub.com, HTTPS, logga in via webbläsaren)" "gh-login"
else
  login=$(gh api user -q .login 2>/dev/null || echo '?')
  # Ett företagskonto som ägs av företaget (Enterprise Managed Users) heter namn_kortkod. Vanliga
  # GitHub-namn kan inte innehålla understreck. Ett sådant konto får inte forka ett repo utanför
  # företaget, och då stannar första leveransen med tools/pr.sh.
  case "$login" in
    *_*) nej "gh är inloggad med ett företagsstyrt konto ($login)" "det kan inte forka workshopens repo. Logga in gh med ett personligt konto: gh auth login   (Copilot kan ligga kvar på företagskontot)" "gh-konto";;
    *)   ja "gh inloggad som $login";;
  esac
fi

echo "Repo"
# [ -f ] först: "< .board-url" misslyckas i skalet innan tr startar, och 2>/dev/null på tr fångar
# inte det. Utan den här formen möttes deltagaren av ett rått skalfel som första rad.
URL="${BOARD_URL:-$( [ -f .board-url ] && tr -d '[:space:]' < .board-url || echo http://localhost:8180 )}"
if curl -sSf --max-time 8 "$URL/api/health" >/dev/null 2>&1; then ja "Torget svarar på $URL"
else nej "Torget svarar inte på $URL" "kolla nätet, eller fråga workshopledaren om adressen i .board-url stämmer" "torget"; fi

if [ -s .board-name ]; then
  namn=$(head -1 .board-name | tr -d '\r\n')
  # Samma lista som new-team.sh och pr.sh läser. Förr hade de tre var sin, och namn som lyktan och
  # kvarter gick igenom incheckningen men vägrades sedan på morgonen.
  if grep -v '^[[:space:]]*#' tools/upptagna-namn.txt 2>/dev/null | grep -qxF "$namn"; then
    nej "teamnamnet \"$namn\" står som exempel i dokumentationen" "hitta på ett eget namn och kör: tools/new-team.sh <det-namnet>" "namn"
  else
    ja ".board-name: $namn"
  fi
else
  echo "  ännu inget teamnamn  (tools/new-team.sh <namn> sätter det, gör det på morgonen)"
fi

echo
if [ $fail -eq 0 ]; then
  for a in $agenter; do
    case "$a" in
      copilot) echo "Allt på plats ($ok av $ok). Kör: copilot → /board";;
      claude)  echo "Allt på plats ($ok av $ok). Kör: claude → /board";;
      codex)   echo "Allt på plats ($ok av $ok). Kör: codex → \$board";;
    esac
  done
  echo "KLAR: $ok av $ok ok, inget att fixa."
else
  echo "$fail sak(er) att fixa innan dagen. Sista raden kan du klistra in till workshopledaren:"
  echo "INTE KLAR: $ok ok,$brister saknas"
  exit 1
fi
