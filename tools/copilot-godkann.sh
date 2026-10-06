#!/usr/bin/env bash
# Förhandsgodkännande för GitHub Copilot CLI. Anropas av .github/hooks/torget.json före varje verktygsanrop.
#
# Copilot läser inte .claude/settings.json. Utan den här frågar agenten människan inför varje anrop till
# tavlan, och då vaknar ingen agent av sig själv när någon kallar till brainstorm.
#
# Godkänner samma kommandon som .claude/settings.json tillåter, och bara när kommandot står ensamt:
# ingen kedja, inget rör, ingen omdirigering, ingen kommandosubstitution. Allt annat lämnas åt Copilot,
# som frågar människan som vanligt. Skriptet säger aldrig nej och avslutar alltid med 0, för Copilot
# tolkar exit 2 eller en krasch som ett nej, och då stoppas varenda skalkommando i hela sessionen.
#
# Copilot läser hooken först när mappen är betrodd: starta copilot en gång i repo-roten och svara ja.
# Prova själv:  printf '%s' '{"toolName":"bash","toolArgs":"{\"command\":\"tools/board.sh read\"}"}' | tools/copilot-godkann.sh
set -u

# read -d '' i stället för PROG=$(cat <<'PY' ...): bash 3.2 letar efter citattecken inuti en
# heredoc i $(...), snubblar på bakåtcitatet i regexen och dör med exit 2, alltså ett nej till allt.
read -r -d '' PROG <<'PY' || true
import json, re, sys

try:
    d = json.load(sys.stdin)
    namn = d.get('toolName') or d.get('tool_name') or ''
    if namn.lower() not in ('bash', 'shell'):
        sys.exit(0)
    a = d.get('toolArgs', d.get('tool_input', {}))
    if isinstance(a, str):
        a = json.loads(a)
    cmd = (a or {}).get('command', '').strip()
except Exception:
    sys.exit(0)

# Tecken som kan starta ett andra kommando, skriva till en fil eller köra kod inne i argumenten.
# Står något av dem med, även inom citattecken, får människan avgöra.
if not cmd or re.search(r'[;&|<>`$\\\n\r]', cmd):
    sys.exit(0)

# Från en teammapp (projects/<namn>/) heter skripten ../../tools/..., från repo-roten tools/...
P = r'(?:bash |sh )?(?:\./|(?:\.\./)+)?'
TILLATNA = [
    P + r'tools/board\.sh(?: .*)?',
    P + r'tools/check-setup\.sh',
    P + r'tools/new-team\.sh(?: .*)?',
    P + r'tools/pr\.sh(?: .*)?',
    P + r'tools/release\.sh (?:list|glomda.*|check .*|diff .*)',
    r'node (?:\./|(?:\.\./)+)?board/(?:server\.js|test\.mjs)',
    r'gh pr (?:list|view|diff)(?: .*)?',
    r'git (?:status|log|diff|pull)(?: .*)?',
]
if not any(re.fullmatch(m, cmd) for m in TILLATNA):
    sys.exit(0)

# git kan köra program och skriva filer via flaggor. Sådant godkänns aldrig i förväg.
if re.search(r'--(?:upload-pack|receive-pack|exec|output|ext-diff|config)', cmd):
    sys.exit(0)

# board.sh --fil postar innehållet i en fil på tavlan, som alla i rummet ser. Godkänns bara för
# filer i /tmp eller en .txt/.md-fil i arbetskatalogen, aldrig något med .. eller en hemkatalog.
m = re.search(r'--fil\s+(\S+)', cmd)
if m:
    fil = m.group(1).strip('\'"')
    if '..' in fil or not re.fullmatch(r'/tmp/[A-Za-z0-9._-]+|[A-Za-z0-9._-]+\.(?:txt|md)', fil):
        sys.exit(0)

print(json.dumps({'permissionDecision': 'allow',
                  'permissionDecisionReason': 'workshopens verktyg, samma lista som .claude/settings.json'}))
PY

indata=$(cat)
if command -v python3 >/dev/null 2>&1; then
  printf '%s' "$indata" | python3 -c "$PROG" 2>/dev/null || true
fi
exit 0
