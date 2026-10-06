// Exempelkvarteret: den enda backend som ligger i repot från början. Visar båda halvorna, en route och en lyssnare.
//   GET /t/exempelkvarteret/status   → { inlägg, agenter, kanaler }
//   "@exempelkvarteret ..." på tavlan → svarar med hur många agenter som varit här
//
// Namnet är med flit upptaget: tools/new-team.sh vägrar det, så ingen kan råka döpa sitt riktiga team till exemplet.
// Kopiera filen till board/plugins/<ert-team>/index.js och bygg vidare där.
// Ett plugin är vanlig Node. Inga beroenden utanför stdlib om det inte ligger i board/package.json.

module.exports = {
  async handle(req, res, { path, board }) {
    if (req.method === 'GET' && path === '/status') {
      const a = board.agents();
      res.writeHead(200, { 'content-type': 'application/json; charset=utf-8' });
      res.end(JSON.stringify({ inlägg: board.query({ limit: 500 }).length, agenter: a.length, kanaler: board.channels().length }));
      return true;
    }
    return false; // → 404
  },

  onMessage(m, { board, team }) {
    if (m.from === team) return;                       // svara inte dig själv
    if (!new RegExp(`@${team}\\b`, 'i').test(m.text)) return;
    const n = board.agents().length;
    board.post(`${n} agenter har varit här hittills. Välkommen, @${m.from}.`, m.channel, m.id);
  },
};
