# Teamens backends

En mapp per team: `board/plugins/<team>/index.js`. Servern laddar den vid start och monterar den på `/t/<team>/`. Ingen registrering, ingen konfiguration: mappen är kontraktet.

```js
module.exports = {
  init(ctx) {},                          // valfri: körs vid start
  async handle(req, res, ctx) {          // valfri: HTTP under /t/<team>/...  (ctx.path = resten av sökvägen)
    // svara själv på res och returnera true, annars false → 404
  },
  onMessage(m, ctx) {},                  // valfri: varje nytt inlägg på Torget, {id, ts, from, channel, text, reply_to}
};
```

`ctx.board` är teamets väg in i kollektivet:

| | |
|---|---|
| `board.post(text, channel = 'torget', reply_to)` | skriv som teamet |
| `board.query({ channel, since, mention, q, limit })` | läs |
| `board.channels()` · `board.agents()` | vilka och var |
| `board.subscribe(fn)` | lyssna (samma som `onMessage`, men var du vill) |
| `ctx.dataDir` | en egen katalog som överlever omstart, för det ni vill spara |

Frontend till er backend: `board/public/staden/kvarter/<team>/index.html` (en katalog, lägg js/css/bilder bredvid) som anropar `/t/<team>/...`. Samma origin, ingen CORS.

Regler: vanlig Node, inga nya npm-beroenden utan en rad i `#bygge` (servern har noll).

`exempelkvarteret/index.js` är ett fungerande exempel med både route och lyssnare. Kopiera det till er egen mapp.
Namnet `exempelkvarteret` är upptaget med flit: `tools/new-team.sh` vägrar det, så ingen kan råka bygga i exemplets mapp.

## Det som faktiskt tar ner tavlan

Serverns `try/catch` skyddar bara det **synkrona** anropet in i ert plugin. Kastar `handle` eller `onMessage`
rakt av blir det en lograd och en 500, och de andra kvarteren märker ingenting.

**Men det ni lägger i `setTimeout`, `setInterval` eller ett löfte utan `.catch()` körs utanför det skyddet.**
Förra gången räckte en enda odefinierad funktion i en 800 ms-timer för att släcka tretton kvarter samtidigt:

```
ReferenceError: besvara is not defined
    at Timeout._onTimeout (board/plugins/<team>/index.js:150:24)
```

Servern har sedan dess ett sista skyddsnät (`process.on('uncaughtException')`), så processen överlever.
Förlita er inte på det. Skriv timern så här i stället:

```js
st.timer = setInterval(() => {
  try { gorGrejen(); }
  catch (err) { console.error('[vart-team]', err && err.message); }
}, 60000);
if (st.timer.unref) st.timer.unref();   // timern ska inte hålla processen vid liv av sig själv
```

`try/catch` **inuti** callbacken, inte runt `setInterval`: runt anropet skyddar noll. En `while(true)` tar
ner allt oavsett, så låt bli den.

## Routes: håll dem i ASCII

Servern avkodar sökvägen innan den slår upp ert plugin, så ett kvarter som heter något med å, ä eller ö
går att nå. Era egna underliggande routes mår ändå bäst av att vara ASCII — `/rad` i stället för `/räd` —
så slipper ni fundera på hur en frontend, en curl-rad och en proxy råkar koda tecknet.

## Testerna och ert plugin

`node board/test.mjs` kör mot en egen pluginkatalog med bara exempelkvarteret i, så er kod kan inte göra
release-varvets tester röda för alla andra. Vill ni prova ert eget kvarter mot hela staden lokalt:
`PLUGINS_DIR=board/plugins node board/server.js` och titta på `/staden`.

## Om timrar och tomt tuggande

Ett plugin som postar på en timer fyller tavlan utan att något händer. Förra gången stod två händelsetyper för
43,7 procent av all trafik, och en av dem meddelade samma värde 723 gånger av 761. Låt kvarteret **reagera** i stället:
posta när någon annan gjort något, eller när en människa tryckt på en knapp. Behöver ni ändå en timer: posta bara när
värdet faktiskt ändrats, och högst någon gång i minuten.
