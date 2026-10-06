#!/usr/bin/env bash
# Leverera ert kvarter: fork, gren, commit, push och pull request i ett kommando.
#
#   tools/pr.sh <team-namn> "<en rad om vad ni gjort>"
#
# Kör från repo-roten. Går att köra om: nästa gång pushas bara det nya, och PR:en uppdateras av sig själv.
# Tar bara med ert teams filer: projects/<team>/, board/plugins/<team>/ och board/public/staden/kvarter/<team>/ (eller <team>.html).
# Kräver GitHub CLI: https://cli.github.com  och att du är inloggad: gh auth login
#
# Ingen deltagare har push-rätt till workshopens repo, så vägen är alltid fork + PR. Det är därför det här
# skriptet finns från början: förra gången skrevs det mitt under dagen, och fram till dess fastnade leveranserna.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

# Uppströms är repot ni klonade. Ingen adress är inskriven här: den läses ur origin.
UPSTREAM="${UPSTREAM:-$(git remote get-url origin 2>/dev/null | sed -E 's#^git@github\.com:##; s#^https://github\.com/##; s#\.git$##')}"
case "$UPSTREAM" in */*) ;; *) echo "Hittar inte vilket GitHub-repo origin pekar på. Sätt UPSTREAM=<konto>/<repo> och kör igen." >&2; exit 2;; esac
REPONAMN="${UPSTREAM#*/}"
# Omdirigeringen måste testas först: "< .board-url" misslyckas i skalet innan tr startar, och
# 2>/dev/null på tr fångar inte det. Utan [ -f ] blev första raden ett rått skalfel för deltagaren.
BOARD=$( [ -f .board-url ] && tr -d '[:space:]' < .board-url || echo "" )

team="${1:-}"; vad="${2:-}"
[ -n "$team" ] && [ -n "$vad" ] || { echo "användning: tools/pr.sh <team-namn> \"<vad ni gjort>\"" >&2; ls projects 2>/dev/null | grep -v README | sed 's/^/  team: /' >&2; exit 2; }
team=$(printf %s "$team" | tr 'A-ZÅÄÖ' 'a-zåäö' | tr -cs 'a-zåäö0-9' '-' | sed 's/^-//; s/-$//')
# Samma lista som new-team.sh och check-setup.sh läser, så att de tre inte går isär.
if grep -v '^[[:space:]]*#' tools/upptagna-namn.txt 2>/dev/null | grep -qxF "$team"; then
  echo "\"$team\" står som exempel i dokumentationen och delas därför av flera. Döp om er mapp först:" >&2
  echo "  mv projects/$team projects/<eget-namn>   (och board/plugins/$team, board/public/staden/kvarter/$team om de finns)" >&2
  echo "  och byt rad i .board-name, annars postar ni fortfarande under det gamla namnet." >&2
  exit 2
fi

command -v gh >/dev/null 2>&1 || { cat >&2 <<TXT
GitHub CLI (gh) saknas. Installera från https://cli.github.com och kör: gh auth login
Utan gh, för hand:
  1. Forka https://github.com/$UPSTREAM i webbläsaren (knappen Fork).
  2. git remote add fork https://github.com/<ditt-github-namn>/$REPONAMN.git
  3. git checkout -b team/$team && git add projects/$team board/plugins/$team board/public/staden/kvarter/$team* && git commit -m "$team: $vad"
  4. git push -u fork team/$team
  5. Öppna https://github.com/$UPSTREAM/compare och välj "compare across forks", er gren team/$team mot main.
TXT
exit 1; }
gh auth status >/dev/null 2>&1 || { echo "Du är inte inloggad i GitHub CLI. Kör: gh auth login   (välj GitHub.com, HTTPS, logga in via webbläsaren)" >&2; exit 1; }
me=$(gh api user -q .login)

# 1. vart pushar vi? ägaren pushar till origin, alla andra till sin fork
if [ "$me" = "${UPSTREAM%%/*}" ]; then remote=origin
else
  remote=fork
  if ! git remote get-url fork >/dev/null 2>&1; then
    echo "→ skapar din fork $me/$REPONAMN (om den inte finns) och lägger till den som remote \"fork\""
    gh repo fork "$UPSTREAM" --clone=false >/dev/null 2>&1 || true
    git remote add fork "https://github.com/$me/$REPONAMN.git"
  fi
fi

# 2. gren
branch="team/$team"
if [ "$(git branch --show-current)" != "$branch" ]; then
  git show-ref --verify --quiet "refs/heads/$branch" && git checkout -q "$branch" || git checkout -q -b "$branch"
fi
echo "→ gren $branch"

# 3. bara era filer
paths=(); for p in "projects/$team" "board/plugins/$team" "board/public/staden/kvarter/$team" "board/public/staden/kvarter/$team.html"; do [ -e "$p" ] && paths+=("$p"); done
[ ${#paths[@]} -gt 0 ] || { echo "Hittar inga filer för team \"$team\". Finns projects/$team/ eller board/plugins/$team/? Teamnamnet ska vara mappens namn." >&2; exit 1; }
[ -e "board/plugins/$team/index.js" ] || echo "  obs: ingen backend ännu (board/plugins/$team/index.js). Går bra, men kvarteret kan inte lyssna på tavlan utan den."
[ -e "board/public/staden/kvarter/$team/index.html" ] || [ -e "board/public/staden/kvarter/$team.html" ] || echo "  obs: ingen frontend ännu (board/public/staden/kvarter/$team/index.html). Då syns ingen ruta på /staden."
git add -- "${paths[@]}"
if git diff --cached --quiet; then echo "→ inget nytt att committa"; else git commit -q -m "$team: $vad" && echo "→ committat"; fi
andra=$(git status --porcelain | grep -v "^?? \.board-name" | grep -vE " (projects/$team|board/plugins/$team|board/public/staden/kvarter/$team)" | head -5 || true)
[ -n "$andra" ] && { echo "  obs: de här ändringarna följer INTE med (utanför ert teams mappar):"; echo "$andra" | sed 's/^/    /'; }

# 3b. Synka med main. Era PR:ar squash-mergas, så grenen divergerar från main efter varje leverans och nästa PR
#     skulle krocka med er egen förra. Vid konflikt vinner ER version: ni är de enda som rör era filer.
if git fetch -q origin main 2>/dev/null; then
  if ! git merge -q -X ours --no-edit origin/main >/dev/null 2>&1; then
    git merge --abort 2>/dev/null || true
    echo "  obs: kunde inte synka med main automatiskt. Kör: git stash; git merge -X ours origin/main; git stash pop   och sedan det här kommandot igen."
  else echo "→ synkad med main"; fi
fi

# 4. push
echo "→ pushar till $remote"
git push -q -u "$remote" "$branch"

# 5. pull request (finns den redan uppdaterades den av pushen)
head="$me:$branch"; [ "$remote" = origin ] && head="$branch"
ut=$(gh pr create -R "$UPSTREAM" --base main --head "$head" --title "$team: $vad" --body "Team **$team**: $vad

Skapad med tools/pr.sh. Release-agenten granskar, mergar och deployar.${BOARD:+ Sedan syns kvarteret på $BOARD/staden}" 2>&1) && echo "→ PR skapad: $ut" || {
  url=$(printf %s "$ut" | grep -oE 'https://github.com/[^ ]+/pull/[0-9]+' | head -1)
  [ -n "$url" ] && echo "→ PR:en finns redan och är uppdaterad med det ni just pushade: $url" || { echo "$ut" >&2; exit 1; }
}
echo
echo "Klart. Säg till i #bygge:  tools/board.sh post bygge \"PR inne från $team: $vad\""
echo "Release-agenten mergar och deployar inom några minuter. Ändrar ni något: kör samma kommando igen."
