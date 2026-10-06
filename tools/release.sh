#!/usr/bin/env bash
# Release-verktyg för workshopledningen: granska, merga och deploya teamens PR:ar.
# Kräver gh (inloggad) och ssh till servern. Repot läses ur origin, ingenting är inskrivet här.
#
#   tools/release.sh list                 öppna PR:ar: team, filer, ålder, och vem som väntat längst
#   tools/release.sh glomda [minuter]     PR:ar som varit öppna längre än så (default 60), äldst först
#   tools/release.sh check <nr>           regelkoll av en PR: tillåtna sökvägar, hemligheter, tester om servern rörs. Exit 0 = ok
#   tools/release.sh diff <nr>            visa diffen
#   tools/release.sh merge <nr>           squash-merga (kör check först)
#   tools/release.sh varv                 hela varvet: check + riskskanning + merge + en deploy + rapport
#   tools/release.sh deploy               git pull på main + deploy/deploy.sh + hälsokoll
#   tools/release.sh announce <text>      posta i #bygge som release-agenten
#
# FLERA BÖR KÖRA DEN. Mergekön får inte hänga på en enda människa: förra gången blev två PR:ar aldrig
# mergade för att den som körde release hade fullt upp.
#
# Men var ärlig om vad låset gör: LÅSET I TMPDIR SKYDDAR BARA MOT TVÅ VARV PÅ SAMMA DATOR. Sitter ni
# vid var sin laptop ser ni aldrig varandras lås. Därför tar varvet också ett kortlivat anspråk där
# PR:arna redan finns: den tilldelar sig själv PR:en på GitHub (assignee) medan den håller på, hoppar
# över det någon annan just håller i, och släpper anspråket så fort PR:en är avklarad — oavsett utfall.
# Ett anspråk som ligger kvar (varv som dött halvvägs) syns i glomda, ta bort det för hand.
# Kan skriptet inte tilldela (saknad rättighet) mergar den ändå, och då gäller den enkla regeln:
# dela upp på PR-nummer, jämna och udda, och säg vem som tar vilka i #bygge.
#
# Person nummer två behöver tre saker i sin egen klon: merge-rätt i repot, en ssh-nyckel som servern
# släpper in, och filen .deploy-host (se deploy/README.md). Utan .deploy-host avbryts deployen.
#
# Regler: en PR får bara röra projects/<team>/**, board/plugins/<team>/** (backend)
# och board/public/staden/kvarter/<team>.html eller board/public/staden/kvarter/<team>/** (frontend).
# Allt annat (board/server.js, tools/, .claude/, .github/, README …) kräver att en människa säger ja: check svarar exit 2.
set -euo pipefail
cd "$(dirname "$0")/.."
REPO="${REPO:-$(git remote get-url origin 2>/dev/null | sed -E 's#^git@github\.com:##; s#^https://github\.com/##; s#\.git$##')}"
case "$REPO" in */*) ;; *) echo "Hittar inte vilket GitHub-repo origin pekar på. Sätt REPO=<konto>/<repo>." >&2; exit 2;; esac

# Kör ALLTID i en egen klon. PR-utcheckningar och grenbyten får aldrig röra arbetskatalogen där ledaren eller hens
# agenter har ocommittade ändringar, och en deploy härifrån blir exakt det som ligger på origin/main.
if [ -z "${RELEASE_KLON:-}" ]; then
  KLON="${RELEASE_KLON_DIR:-$HOME/.cache/${REPO#*/}-release}"
  [ -d "$KLON/.git" ] || { mkdir -p "$(dirname "$KLON")"; git clone -q "https://github.com/$REPO.git" "$KLON"; }
  git -C "$KLON" checkout -q main 2>/dev/null || true
  git -C "$KLON" reset -q --hard 2>/dev/null || true
  git -C "$KLON" pull -q --ff-only origin main
  for f in .board-name .board-url .deploy-host; do [ -f "$f" ] && cp "$f" "$KLON/$f"; done
  RELEASE_KLON=1 exec "$KLON/tools/release.sh" "$@"
fi
cmd="${1:-list}"; shift || true

files_of() { gh pr view "$1" -R "$REPO" --json files -q '.files[].path'; }
team_of()  { gh pr view "$1" -R "$REPO" --json headRefName -q '.headRefName' | sed -E 's|^team/||; s|[^a-zåäö0-9-].*||'; }
alder()    { # minuter sedan tidsstämpeln i $1 (ISO 8601)
  python3 -c "import datetime,sys; t=datetime.datetime.fromisoformat(sys.argv[1].replace('Z','+00:00')); print(int((datetime.datetime.now(datetime.timezone.utc)-t).total_seconds()//60))" "$1" 2>/dev/null || echo 0
}
# Anspråk på en enskild PR, delat mellan datorer: assignee på GitHub. Svar: 0 = din, 1 = någon annans.
# Misslyckas anropet (ingen rättighet, nätet nere) svarar den 0: kön får inte stanna av ett lås.
ta_pr() { # ta_pr <nr>
  local nr="$1" agare
  JAG="${JAG:-$(gh api user -q .login 2>/dev/null || echo "")}"
  [ -n "$JAG" ] || return 0
  agare=$(gh pr view "$nr" -R "$REPO" --json assignees -q '.assignees[].login' 2>/dev/null | head -1 || echo "")
  if [ -n "$agare" ] && [ "$agare" != "$JAG" ]; then
    echo "  #$nr hanteras just nu av $agare, hoppar över den här gången"; return 1
  fi
  [ -n "$agare" ] || gh pr edit "$nr" -R "$REPO" --add-assignee "$JAG" >/dev/null 2>&1 || true
  return 0
}
# Släpp anspråket så fort PR:en är avklarad, oavsett utfall. Ett anspråk som ligger kvar skulle låsa
# ute den andra release-personen för alltid, och det vore värre än inget anspråk alls.
slapp_pr() { [ -n "${JAG:-}" ] && gh pr edit "$1" -R "$REPO" --remove-assignee "$JAG" >/dev/null 2>&1 || true; }
# Märk en PR som bortlagd, på GitHub så att den överlever varvet och syns för alla som kör release.
markera() {
  gh pr edit "$1" -R "$REPO" --add-label vantar-pa-ledaren >/dev/null 2>&1 && return 0
  gh label create vantar-pa-ledaren -R "$REPO" -c FFB454 \
     -d "Släppt åt sidan av release-varvet, en människa måste titta" >/dev/null 2>&1 || true
  gh pr edit "$1" -R "$REPO" --add-label vantar-pa-ledaren >/dev/null 2>&1 || true
}
las_ta() {   # lokalt lås: skyddar mot två varv på SAMMA dator, inte mot två datorer
  LAS="${TMPDIR:-/tmp}/release-${REPO#*/}.las"
  if mkdir "$LAS" 2>/dev/null; then echo "${RELEASE_VEM:-$(whoami)} $(date +%s)" > "$LAS/vem"; trap 'rm -rf "$LAS"' EXIT; return 0; fi
  vem=$(cut -d' ' -f1 "$LAS/vem" 2>/dev/null || echo "någon")
  nar=$(cut -d' ' -f2 "$LAS/vem" 2>/dev/null || echo 0)
  min=$(( ( $(date +%s) - ${nar:-0} ) / 60 ))
  if [ "$min" -gt 15 ]; then echo "(bryter ett $min minuter gammalt lås från $vem)"; rm -rf "$LAS"; las_ta; return $?; fi
  echo "Ett release-varv pågår redan: $vem började för $min minut(er) sedan. Vänta, eller ta en annan PR för hand." >&2
  exit 3
}

case "$cmd" in
  list)
    # Åldern räknas från createdAt: en PR som teamet putsar på ser annars färsk ut hur länge den än väntat.
    gh pr list -R "$REPO" --json number,title,headRefName,author,files,createdAt \
      -q '.[] | [.number, .title, .headRefName, .author.login, (.files|length), .createdAt] | @tsv' |
    while IFS=$'\t' read -r nr titel gren vem antal uppdaterad; do
      m=$(alder "$uppdaterad")
      flagga=""; [ "$m" -ge 60 ] && flagga="   ← öppen i $m min"
      printf '#%-4s %-52s [%s] %s  %s filer  %s min%s\n' "$nr" "$(printf %.52s "$titel")" "$gren" "$vem" "$antal" "$m" "$flagga"
    done
    ;;
  glomda)
    # Åldern räknas från createdAt, inte updatedAt. Ett team som putsar på sin PR medan de väntar
    # gör den "färsk" varje gång, och då listas den aldrig. Precis så försvann PR #43 förra gången:
    # teamet uppdaterade den fyra gånger mellan 11:51 och 13:09 och den kom ändå aldrig in i main.
    # Märkta PR:ar (vantar-pa-ledaren) listas alltid, oavsett ålder: de är per definition bortlagda.
    # Etiketter och innehavare kan vara tomma, och tabb är ett IFS-blanktecken: två tabbar i rad
    # räknas som EN avgränsare, så tomma fält mitt i raden skulle förskjuta resten. Därför "-".
    grans="${1:-60}"; hittade=0
    while IFS=$'\t' read -r nr titel gren skapad etiketter innehavare; do
      m=$(alder "$skapad")
      case "$etiketter" in *vantar-pa-ledaren*) markt=" · VÄNTAR PÅ LEDAREN";; *) markt="";; esac
      [ "$innehavare" = "-" ] || markt="$markt · anspråk kvar hos $innehavare"
      [ "$m" -lt "$grans" ] && [ -z "$markt" ] && continue
      hittade=$((hittade+1)); printf '#%-4s %-52s [%s]  öppen i %s min%s\n' "$nr" "$(printf %.52s "$titel")" "$gren" "$m" "$markt"
    done < <(gh pr list -R "$REPO" --json number,title,headRefName,createdAt,labels,assignees \
               -q '.[] | [.number, .title, .headRefName, .createdAt,
                          (([.labels[].name] | join(",")) as $l | if $l == "" then "-" else $l end),
                          (([.assignees[].login] | join(",")) as $a | if $a == "" then "-" else $a end)] | @tsv' \
             | sort -t'	' -k4,4)
    # Sista kommandot får inte vara ett test: "[ x -eq 0 ] && echo" svarar 1 när något HITTATS, och
    # varv kör den i ett rör under set -e + pipefail. Ett lyckat varv slutade då med exit 1.
    [ "$hittade" -eq 0 ] && echo "Inga glömda PR:ar. Kön är tom eller färsk." || true
    ;;
  diff) gh pr diff "$1" -R "$REPO";;
  check)
    nr="${1:?pr-nummer}"; team=$(team_of "$nr"); bad=0; needs_ok=0
    echo "PR #$nr  team: ${team:-?}"
    while IFS= read -r f; do
      case "$f" in
        projects/"$team"/*|board/plugins/"$team"/*|board/public/staden/kvarter/"$team".html|board/public/staden/kvarter/"$team"/*) echo "  ok       $f";;
        projects/*|board/plugins/*|board/public/staden/kvarter/*) echo "  ANNAT TEAMS FIL  $f"; bad=1;;
        *) echo "  gemensam $f"; needs_ok=1;;
      esac
    done < <(files_of "$nr")
    # hemligheter i diffen
    if gh pr diff "$nr" -R "$REPO" | grep -E '^\+' | grep -qE 'sk-[A-Za-z0-9]{20,}|AKIA[0-9A-Z]{16}|ghp_[A-Za-z0-9]{30,}|xox[bp]-|-----BEGIN [A-Z ]*PRIVATE KEY|OPENROUTER_API_KEY=|ANTHROPIC_API_KEY='; then
      echo "  HEMLIGHET i diffen"; bad=1
    fi
    # servern rörd → tester
    if files_of "$nr" | grep -q '^board/'; then
      echo "  board/ rörs → kör tester mot PR-grenen (plugins laddas av servern)"
      gh pr checkout "$nr" -R "$REPO" >/dev/null 2>&1 || true
      # Hård tidsgräns och utdata till fil: en testserver som överlever ett fallerat test håller annars röret öppet för evigt.
      ut=$(mktemp); rc=0; (cd board && perl -e 'alarm 90; exec @ARGV' node test.mjs > "$ut" 2>&1) || rc=$?
      pkill -f "board/server.js" 2>/dev/null || true
      tail -1 "$ut"; [ $rc -eq 0 ] || { echo "  TESTERNA FALLERADE eller hängde (exit $rc):"; grep -E "✗|Error|error" "$ut" | head -5; bad=1; }
      git checkout -q main
    fi
    [ $bad -eq 1 ] && { echo "RESULTAT: stopp"; exit 1; }
    [ $needs_ok -eq 1 ] && { echo "RESULTAT: kräver ledarens ok (gemensamma filer)"; exit 2; }
    echo "RESULTAT: ok"
    ;;
  merge)
    nr="${1:?pr-nummer}"; las_ta
    tools/release.sh check "$nr" || { rc=$?; [ $rc -eq 2 ] && [ "${FORCE:-}" = 1 ] || exit $rc; }
    gh pr merge "$nr" -R "$REPO" --squash --delete-branch
    echo "mergad: #$nr"
    ;;
  deploy)
    git checkout -q main && git pull -q --ff-only origin main
    [ -f .deploy-host ] || [ -n "${HOST:-}" ] || {
      echo "Ingen .deploy-host i $(pwd). Deployen kan inte köras." >&2
      echo "Skriv den en gång:  printf 'root@<serverns-ip>\\n' > \$(git rev-parse --show-toplevel)/.deploy-host" >&2
      echo "i den klon du kör release från, så kopieras den hit automatiskt nästa varv." >&2
      exit 2; }
    deploy/deploy.sh 2>&1 | tail -2
    curl -sS --max-time 10 "$( [ -f .board-url ] && tr -d '[:space:]' < .board-url || echo '' )/api/health"; echo
    ;;
  varv)
    las_ta
    RISK='while ?\(true|for ?\(;;|process\.(exit|kill|abort)|child_process|eval\(|new Function|\.\./\.\.|unlinkSync|rmSync|rmdirSync|require\(.(http|https|net|dgram|cluster|worker_threads|vm).\)'
    mergade=(); vantar=(); stoppade=()
    for nr in $(gh pr list -R "$REPO" --json number -q '.[].number' | sort -n); do
      git checkout -q main 2>/dev/null; git pull -q --ff-only origin main 2>/dev/null || true
      titel=$(gh pr view "$nr" -R "$REPO" --json title -q .title | cut -c1-70)
      ta_pr "$nr" || continue        # någon annan har redan tagit den här PR:en
      rc=0; tools/release.sh check "$nr" > "${TMPDIR:-/tmp}/chk-$nr.txt" 2>&1 || rc=$?; git checkout -q main 2>/dev/null || true
      # Högen "väntar på ledaren" måste överleva varvet, annars faller en PR som en gång lagts åt
      # sidan ur bilden och ingen ser den igen. Etiketten sitter på PR:en, inte i det här skriptet.
      if [ $rc -eq 2 ]; then markera "$nr"; slapp_pr "$nr"; vantar+=("#$nr $titel — gemensamma filer, läs diffen själv"); continue; fi
      if [ $rc -ne 0 ]; then slapp_pr "$nr"; stoppade+=("#$nr $titel — $( (grep -E 'ANNAT|HEMLIGHET|FALLERADE' "${TMPDIR:-/tmp}/chk-$nr.txt" || true) | head -2 | tr '\n' ' ')"); continue; fi
      traff=$(gh pr diff "$nr" -R "$REPO" | awk '/^diff --git a\/board\//{p=1} /^diff --git a\/projects\//{p=0} p' | grep -E '^\+' | grep -nE "$RISK" | cut -c1-140 | head -3 || true)
      if [ -n "$traff" ]; then markera "$nr"; slapp_pr "$nr"; vantar+=("#$nr $titel — riskmönster, läs själv: $traff"); continue; fi
      if ! gh pr merge "$nr" -R "$REPO" --squash > "${TMPDIR:-/tmp}/m-$nr.txt" 2>&1; then
        if grep -qi conflict "${TMPDIR:-/tmp}/m-$nr.txt"; then
          gh pr checkout "$nr" -R "$REPO" >/dev/null 2>&1 && git fetch -q origin main && git merge -q -X ours --no-edit origin/main >/dev/null 2>&1 && git push -q 2>/dev/null
          git checkout -q main; sleep 5
          gh pr merge "$nr" -R "$REPO" --squash > "${TMPDIR:-/tmp}/m-$nr.txt" 2>&1 || { slapp_pr "$nr"; stoppade+=("#$nr $titel — konflikt som inte gick att synka"); continue; }
        else slapp_pr "$nr"; stoppade+=("#$nr $titel — $(tail -1 "${TMPDIR:-/tmp}/m-$nr.txt" | cut -c1-100)"); continue; fi
      fi
      gh pr edit "$nr" -R "$REPO" --remove-label vantar-pa-ledaren >/dev/null 2>&1 || true
      slapp_pr "$nr"
      mergade+=("#$nr $titel")
    done
    git checkout -q main 2>/dev/null
    # Deployen får inte döda varvet. Förr slutade hela varvet här med exit 2 när .deploy-host saknades,
    # och då skrevs rapporten nedan aldrig ut — den enda plats där GLÖMDA syns.
    if [ ${#mergade[@]} -gt 0 ]; then
      tools/release.sh deploy | tail -1 || echo "DEPLOY MISSLYCKADES, se ovan. Det som mergats ligger i main men inte på servern."
    fi
    echo "MERGADE (${#mergade[@]}):"; printf '  %s\n' "${mergade[@]:-inga}"
    echo "VÄNTAR PÅ LEDAREN (${#vantar[@]}):"; printf '  %s\n' "${vantar[@]:-inga}"
    echo "STOPPADE (${#stoppade[@]}):"; printf '  %s\n' "${stoppade[@]:-inga}"
    echo "GLÖMDA (öppna i en timme eller mer, och allt som är märkt vantar-pa-ledaren):"
    tools/release.sh glomda 60 | sed 's/^/  /'
    ;;
  announce)
    BOARD_NAME=release-agenten tools/board.sh post bygge "$*"
    ;;
  *) sed -n '2,28p' "$0"; exit 2;;
esac
