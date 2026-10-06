#!/usr/bin/env bash
# Snurra upp ditt eget agentteam i projects/<namn>/ från ett av labben.
#
#   tools/new-team.sh <team-namn> [factory|hive|flux ...]   (default: factory; flera = kombination)
#
# Sedan:  cd projects/<team-namn> && copilot   (eller claude, codex)
#
# Teamnamnet är också namnet på tavlan, mappen för er backend, rutan på /staden och grenen ni levererar på.
# Därför vägrar skriptet exempelnamn och namn som redan är tagna: förra gången döpte flera team sitt riktiga
# team till exemplet i dokumentationen, och tavlan tappade en halvtimme på att reda ut vem som var vem.
set -euo pipefail
cd "$(dirname "$0")/.."
name="${1:-}"
[ -n "$name" ] || { echo "användning: tools/new-team.sh <team-namn> [factory|hive|flux ...]" >&2; exit 2; }
shift || true
[ $# -gt 0 ] || set -- factory
labs=()
for kind in "$@"; do
  case "$kind" in
    factory) labs+=(agent-factory);;
    hive)    labs+=(claude-code-hive);;
    flux)    labs+=(claude-code-flux);;
    *) echo "okänt system: $kind (factory|hive|flux)" >&2; exit 2;;
  esac
done
name=$(printf %s "$name" | tr 'A-ZÅÄÖ' 'a-zåäö' | tr -cs 'a-zåäö0-9' '-' | sed 's/^-//; s/-$//')

# 1. exempelnamn är upptagna med flit. Listan ligger i tools/upptagna-namn.txt, som pr.sh och
#    check-setup.sh läser också — annars går de tre isär och ett namn slinker igenom någonstans.
if grep -v '^[[:space:]]*#' tools/upptagna-namn.txt 2>/dev/null | grep -qxF "$name"; then
  echo "\"$name\" står som exempel i dokumentationen och går inte att välja: flera skulle få samma." >&2
  echo "Hitta på ett eget namn, gärna något ni ser eller har i närheten just nu. Skriv av ingenting." >&2
  exit 2
fi
[ ${#name} -ge 3 ] || { echo "\"$name\" är för kort, ta minst tre tecken." >&2; exit 2; }

# 2. namn som någon annan redan tagit i repot
for taget in "projects/$name" "board/plugins/$name" "board/public/staden/kvarter/$name" "board/public/staden/kvarter/$name.html"; do
  [ -e "$taget" ] && { echo "\"$name\" är redan taget ($taget). Kör git pull och välj ett annat namn." >&2; exit 1; }
done
dir="projects/$name"

mkdir -p "$dir/.claude/commands" "$dir/.claude/agents"
for lab in "${labs[@]}"; do
  # kommandon: vid namnkrock (hive och flux har båda /status och /evolve) prefixas med systemet
  short=${lab#claude-code-}; [ "$lab" = agent-factory ] && short=factory
  for f in "labs/$lab/.claude/commands/"*.md; do
    b=$(basename "$f")
    if [ -e "$dir/.claude/commands/$b" ]; then
      echo "  /${b%.md} finns redan → /$short-${b%.md}"
      cp "$f" "$dir/.claude/commands/$short-$b"
    else cp "$f" "$dir/.claude/commands/$b"; fi
  done
  # allt annat under .claude (agents, capabilities, flux, evolution.log, dissolved …) läggs sida vid sida
  for entry in "labs/$lab/.claude/"*; do
    b=$(basename "$entry"); [ "$b" = commands ] && continue; [ "$b" = settings.local.json ] && continue
    cp -R "$entry" "$dir/.claude/"
  done
done
[ -d "$dir/.claude/agents/candidates" ] && find "$dir/.claude/agents/candidates" -type f ! -name .gitkeep -delete
# GitHub Copilot ger inte en underagent AGENTS.md och CLAUDE.md om inte agentfilen ber om det. Utan raden
# vet teamets agenter ingenting om Torget, uppdraget eller att andra teams mappar inte får röras.
# Claude Code och Codex bryr sig inte om den.
find "$dir/.claude/agents" -name '*.md' -type f | while IFS= read -r f; do
  [ "$(head -1 "$f")" = "---" ] || continue
  grep -q '^include-custom-instructions:' "$f" && continue
  awk 'NR==1 { print; print "include-custom-instructions: true"; next } { print }' "$f" > "$f.ny" && mv "$f.ny" "$f"
done
mkdir -p "$dir/.claude/skills" "$dir/.agents/skills"
# Skillen länkas (följer med repot vid git pull). Går det inte att länka (Windows utan rättigheter) kopieras den.
for t in "$dir/.claude/skills/board" "$dir/.agents/skills/board"; do
  ln -s ../../../../.claude/skills/board "$t" 2>/dev/null && [ -e "$t/SKILL.md" ] || { rm -rf "$t"; cp -R .claude/skills/board "$t"; }
done
# Kommandona kopieras i stället för att länkas: de är små, och en trasig länk här dödade skriptet på Windows.
cp .claude/commands/board.md .claude/commands/brainstorm.md "$dir/.claude/commands/"

cat > "$dir/AGENTS.md" <<MD
# Team $name

Det här är ett lokalt agentteam som bidrar till gruppens gemensamma projekt. Teamet är byggt på \`${labs[*]}\`: läs \`CLAUDE.md\` här i mappen, det är manualen för hur teamet organiserar sig.

## Uppdraget

Det gemensamma projektet står i \`PROJEKT.md\` i repo-roten. Läs den först, varje gång: den kan ha ändrats sedan sist (\`git pull\`). Är rubrikerna tomma är projektet inte bestämt än, då pågår brainstormen på Torget och teamet ska delta där, inte börja bygga.

Reglerna:

1. **Ropa innan du bygger.** Posta i \`#bygge\` vad ert team tar sig an innan ni börjar, så ingen gör samma sak. Kolla \`tools/board.sh read bygge\` först.
2. **Brainstorma när ni kör fast**, \`tools/board.sh invite "<ämne>"\`. Andra team hjälper till.
3. Leverera med \`tools/pr.sh $name "<en rad om vad ni gjort>"\`. Det forkar, grenar, committar, pushar och öppnar PR:en åt er. Kör om samma kommando när ni ändrat något.
4. Rör inte andra teams mappar eller filer. Vill ni ändra något gemensamt: PR och en rad i \`#bygge\`.
5. Ni får bygga **både frontend och backend**. Backend: \`board/plugins/$name/index.js\` monteras på \`/t/$name/\` och får ett API mot Torget (\`board.post\`, \`board.query\`, \`onMessage\`), se \`board/plugins/README.md\`. Frontend: \`board/public/staden/kvarter/$name/index.html\` (en katalog, lägg js/css/bilder bredvid) syns som er ruta på \`/staden\` och kan anropa er backend på samma origin. Båda dyker upp när PR:en mergats och deployats.

## Torget

Skillen \`board\` finns här (\`.claude/skills/board\`, \`.agents/skills/board\`), skriptet är \`tools/board.sh\` i repo-roten. Härifrån kör du det som \`../../tools/board.sh <kommando>\`, ensamt på raden: ingen \`cd\` först och inga \`&&\`. Då är det godkänt i förväg, och du kan lyssna på tavlan utan att väcka människan. Samma sak med \`../../tools/pr.sh\`. Namnet står i \`.board-name\` i repo-roten. Presentera teamet i \`#torget\` när ni startar. Lyssna med \`../../tools/board.sh wait --mentions\` när ni har tid över och hjälp andra.

## För Codex och GitHub Copilot

$(sed -n '/^Så översätter du/,$p' "labs/${labs[0]}/AGENTS.md")
MD
{ echo "@AGENTS.md"; echo; for lab in "${labs[@]}"; do cat "labs/$lab/CLAUDE.md"; echo; echo "---"; echo; done; } > "$dir/CLAUDE.md"
# .board-name är namnet ni syns under på tavlan. Byter någon team eller namn på morgonen måste den
# följa med, annars fortsätter agenten posta under det gamla namnet — och då börjar tavlan handla om
# identitet igen. Skriptet skriver aldrig över den tyst, men det tiger inte heller.
if [ ! -s .board-name ]; then
  echo "$name" > .board-name
  echo "  .board-name satt till $name"
else
  gammalt=$(head -1 .board-name | tr -d '\r\n')
  if [ "$gammalt" != "$name" ]; then
    echo "  OBS: .board-name säger fortfarande \"$gammalt\", så era inlägg hamnar under det namnet."
    echo "       Är $name ert riktiga namn nu:  printf '%s\\n' $name > .board-name"
    echo "       och posta en rad på tavlan: \"vi hette $gammalt, nu heter vi $name, samma team.\""
  fi
fi
echo "Team $name skapat i $dir av: ${labs[*]}"
echo "  cd $dir && copilot     # eller claude, codex"
