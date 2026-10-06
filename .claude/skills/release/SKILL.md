---
name: release
description: Workshopledningens release-agent. Granskar, mergar och deployar teamens PR:ar och berättar på Torget. Använd när användaren säger "release", "merga", "deploya", "kolla PR:arna", "/release" eller "$release".
---

# Release: merga och deploya teamens PR:ar

Du är release-agent för workshopen. Trettio team skickar PR:ar under dagen. Ditt jobb är att få in det som är ofarligt snabbt, stoppa det som är farligt, och fråga om resten.

Verktyget är `tools/release.sh` (kräver `gh` inloggad och ssh till servern). Det kör alltid i en egen klon, så din arbetskatalog rörs aldrig.

**Ni är flera.** Mergekön får inte hänga på en enda människa: förra gången blev två PR:ar aldrig mergade, och ett team fick skriva "Koden är klar; det enda som fattas är trycket på knappen".

Var noga med vad låset faktiskt gör: **låset ligger i en temp-katalog och skyddar bara mot två varv på SAMMA dator.** Sitter ni vid var sin laptop ser ni aldrig varandras lås. Det som håller över datorgränsen är i stället att varvet tilldelar sig själv varje PR på GitHub (assignee) och hoppar över dem någon annan redan tagit. Går inte det (saknad rättighet): dela upp på PR-nummer, jämna och udda, och säg vem som tar vilka i `#bygge`.

Person nummer två behöver tre saker i sin egen klon innan hen kan köra: **merge-rätt i repot**, en **ssh-nyckel som servern släpper in**, och filen **`.deploy-host`** i repo-roten (se `deploy/README.md`). Utan den sista avbryts deployen, och bara deployen — varvet rapporterar ändå.

## Varvet

1. `tools/release.sh list` — vad ligger öppet och hur länge det varit öppet (räknat från när PR:en skapades, inte från senaste ändringen: ett team som putsar på sin PR medan de väntar ska inte se färskt ut).
2. För varje PR: `tools/release.sh check <nr>`.
   - **exit 0** (bara egna filer, inga hemligheter, tester gröna): `tools/release.sh diff <nr>`, ögna igenom diffen i 20 sekunder (är det rimligt? ett plugin i `board/plugins/<team>/` får lyssna och svara på Torget och ha egna routes, men inte `while(true)`, inte `process.exit`, inte läsa andras `dataDir`, inga nya npm-beroenden), sedan `tools/release.sh merge <nr>`.
   - **exit 2** (gemensamma filer, t.ex. servern, tools, README): visa användaren vilka filer och en sammanfattning av diffen, och **fråga** innan du mergar. Ja → `FORCE=1 tools/release.sh merge <nr>`.
   - **exit 1** (annat teams filer eller hemlighet): merga inte. Skriv en kommentar på PR:en med `gh pr comment <nr> -b "..."` som säger exakt vad som stoppar, vänligt. Berätta för användaren.
3. Efter minst en merge: `tools/release.sh deploy`. Kolla att hälsokollen svarar ok.
4. `tools/release.sh announce "Mergat och deployat: #12 och #14. Kolla /staden."` — en rad, alla PR:ar i samma.
5. Rapportera till användaren i fyra rader: mergat, stoppat (och varför), väntar på ok, glömda.

Hela varvet på en gång: `tools/release.sh varv`. Den mergar det ofarliga, deployar en gång på slutet och skriver ut fyra listor, inklusive **GLÖMDA**: PR:ar som varit öppna i en timme eller mer, plus allt som något varv lagt åt sidan. Det som läggs åt sidan märks med etiketten `vantar-pa-ledaren` på GitHub, så att högen överlever varvet och syns även för den andra release-personen. En PR som tas in får etiketten borttagen. Går en PR inte att merga på grund av konflikt synkar den grenen med main och försöker igen.

**Den märkta högen är ditt jobb, inte verktygets.** Gå igenom den varje varv och säg något till teamet på tavlan. Förra gången hamnade PR #48 i den högen på ett riskmönster, teamet räknade själv ut varför, och den kom ändå aldrig in.

## Regler

- Merga aldrig något som rör `board/server.js`, `tools/`, `.claude/` eller `.github/` utan att användaren sagt ja till just den PR:en.
- Deploya aldrig om testerna är röda.
- Skriv aldrig ut hemligheter du ser i en diff, inte ens i kommentaren. Säg bara var de finns.
- Ett varv tar under två minuter. Är det inga PR:ar: säg det med en rad och sluta.
- En PR som stått orörd i en timme är alltid värd en rad till teamet på Torget: `@team` säg vad som fattas.

Vill användaren att det rullar av sig självt: föreslå `/loop 10m /release` i Claude Code.
