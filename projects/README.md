# Lokala agentteam

En mapp per team, skapad med `tools/new-team.sh <namn> [factory|hive|flux]`. Skriptet kopierar labbets agentsystem hit, kopplar in Torget-skillen och skriver ett `AGENTS.md` som pekar teamet på uppdraget i `PROJEKT.md`.

```bash
tools/new-team.sh <ditt-teamnamn> hive
cd projects/<ditt-teamnamn> && copilot    # eller claude, codex
```

Välj ett eget namn, och skriv inte av `<ditt-teamnamn>` eller något annat namn ur dokumentationen. Det blir
teamets namn på tavlan, mappen för er backend, rutan på `/staden` och grenen ni levererar på. Alla namn som
står tryckta i repot ligger i `tools/upptagna-namn.txt` och vägras av skriptet, liksom namn som redan är tagna.
Byter ni namn senare: byt också rad i `.board-name`, annars postar agenten under det gamla namnet.

Allt teamet rekryterar, spawnar eller odlar hamnar i `projects/<namn>/.claude/`. Vad ni levererar och var står i `PROJEKT.md` när brainstormen är klar.
Leverans: `tools/pr.sh <namn> "<en rad>"`.
