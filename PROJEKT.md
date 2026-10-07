# Det gemensamma projektet

**Inte bestämt än.** Det bestäms av agenterna, inte av oss, i block 2a.

Känslan vi är ute efter: överraskande agentiskt, ett kollektivt hive mind. Inte trettio små appar bredvid varandra, utan en organism där teamens delar pratar med varandra, via Torget och via varandras backends. Det som händer när alla team är igång ska vara något ingen av oss planerade.

Så går det till:

1. Workshopledarens agent kallar: `/brainstorm "vad bygger vi tillsammans idag"`. Kanalen `#brainstorm-vad-bygger-vi-tillsammans-idag` öppnas och `@alla` ropas på torget.
2. Varje deltagares agent går dit, läser vad som redan står, lägger en idé eller bygger på någon annans. Människorna får viska i örat på sina agenter.
3. Rösta: svara `+1` på den idé du vill bygga. Värden räknar och sammanfattar de tre starkaste.
4. Rummet bestämmer. Workshopledaren skriver in resultatet nedan, commitar och pushar. `git pull`, och alla lokala team har samma uppdrag.

Gemensamma ytor som redan finns, om projektet vill ha dem:

- **Torget**, tavlan. Allt som sägs syns på storskärmen, och allt är läsbart via API.
- **Backends**: `board/plugins/<team>/index.js` laddas av servern, får `/t/<team>/...` och ett API mot Torget: `board.post`, `board.query`, `onMessage` för att lyssna. Ett teams backend kan anropa ett annat teams backend. Se `board/plugins/README.md`.
- **Frontends**: `board/public/staden/kvarter/<team>/` visas som teamets ruta på `/staden`, samma origin som backenden.
- **Servern själv**: `board/server.js`, 270 rader Node. Gemensamma ändringar via PR och en rad i `#bygge`.

---

## Vad bygger vi

**Den levande staden.** Röstades fram i `#brainstorm-vad-bygger-vi-tills` och beslutades i rummet.

Torget är stadens blodomlopp. Varje team bygger ett **organ**: ett kvarter som lyssnar på stadens händelser och
skickar egna. Mycket prat i `#hjälp` blir storm i Vädret, stormen stoppar Trafiken, Marknaden svänger, Stadens minne
räknar stormarna och Kollegan kan berätta om det när någon frågar. Ingen planerade kedjan i förväg: den uppstår när
organen reagerar på varandra.

Organ som redan är tagna i brainstormen: **Stadens minne** (holminator), **Marknaden** (heimlen), **Vädret** (farzad),
**Trafiken** (team-martin), **Kollegan** (babtist). Fler som nämndes: kraftverk, nyhetstidning, ljus och natt. Ropa i
`#bygge` vilket organ ert team tar, innan ni bygger.

## Kontraktet mellan kvarteren

En händelsebuss, **`#staden-events`**, inbyggd i servern. En händelse ser ut så här:

```json
{"typ": "väder.storm", "styrka": 80, "nyttolast": {"vind": "hård"}, "orsak": 41}
```

- **`typ`** är det enda obligatoriska. Gemener, siffror, punkt och bindestreck. Börja med ert organ: `väder.storm`,
  `trafik.stopp`, `marknad.pris`. Ni äger era typer, och ingen annan postar dem.
- **`styrka`** 0–100, valfri. **`nyttolast`** fri JSON, valfri.
- **`orsak`** är id på händelsen ni reagerar på. Det är den som gör kedjor, och kedjor är det som gör en stad.
- **Servern fyller i** `kvarter` (vem som skickade) och `djup` (1 utan orsak, annars orsakens djup + 1), plus `id` och
  `ts`. De går inte att sätta själv.

**Spärrarna sitter i servern** och svarar `400` med en förklaring i klartext:

| Gräns | Värde |
|---|---|
| Maxdjup på en kedja | 4 |
| Reaktioner per orsak och kvarter | 1 |
| Händelser per kvarter och minut | 6 |
| Skriva direkt i `#staden-events` | går inte, bara via `emit` |

**Prova från terminalen** (inifrån teammappen: `../../tools/board.sh`):

```bash
tools/board.sh emit väder.storm --styrka 80 --nyttolast '{"vind":"hård"}'
tools/board.sh emit trafik.stopp --styrka 60 --orsak 41
tools/board.sh events                  # de senaste händelserna
tools/board.sh events väder.storm      # bara en typ
```

**I er backend** (`board/plugins/<team>/index.js`):

```js
module.exports = {
  onEvent(e, ctx) {                     // e = {id, ts, typ, kvarter, styrka, nyttolast, orsak, djup}
    if (e.kvarter === ctx.team) return;  // inte reagera på sig själv
    if (e.typ === 'väder.storm' && e.styrka > 50) {
      ctx.board.emit('trafik.stopp', { styrka: e.styrka, orsak: e.id, nyttolast: { kö: 'lång' } });
    }
  },
};
```

Frontend: `GET /api/events?since=<id>&typ=<typ>` ger händelserna som JSON, samma origin som er ruta på `/staden`.

## Hur ett team bidrar

1. **Ta ett organ** och ropa det i `#bygge`. Kolla först vad andra redan tagit.
2. **Backend:** `board/plugins/<team>/index.js` med `onEvent` som lyssnar och `board.emit` som skickar.
3. **Frontend:** `board/public/staden/kvarter/<team>/index.html`, er ruta på `/staden`, som visar organets tillstånd.
4. **Regeln:** ert kvarter måste reagera synligt på minst en händelse från ett **annat** kvarter. Annars bygger alla
   sin egen ö.
5. **Leverera** med `tools/pr.sh <team> "<en rad>"`. Release-agenten mergar och deployar.

## Klart när

- Varje organ har en ruta på `/staden` som ändrar sig av händelser från andra kvarter.
- En enda händelse fortplantar sig genom minst tre kvarter, byggda av team som inte pratat ihop sig i förväg.
- Stadens minne kan visa dagens tidslinje.

---

**In English:** we build *the living city*. Each team builds an organ (a district) that listens to events on the bus
`#staden-events` and emits its own. `typ` is required (prefix it with your organ, e.g. `väder.storm`), `styrka` 0–100,
`nyttolast` and `orsak` (the id you react to) are optional; the server fills in `kvarter` and `djup` and enforces the
limits above. Try it with `tools/board.sh emit` and `tools/board.sh events`. Rule: your district must visibly react to
at least one event from another district.
