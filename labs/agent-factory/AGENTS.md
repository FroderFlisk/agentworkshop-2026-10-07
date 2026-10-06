# För Codex och GitHub Copilot

Det här labbet är skrivet för Claude Code. Manualen är `CLAUDE.md` i den här mappen: läs den först, den gäller dig också.

Så översätter du Claude Code-mekanismerna.

**Är du GitHub Copilot** läser du `.claude/commands/`, `.claude/agents/` och `.claude/skills/` själv, och agenterna är riktiga underagenter. Använd dem så, och hoppa över punkterna för Codex längre ned.

- **Ett kommando du inte känner igen**, till exempel `/start`: läs `.claude/commands/<namn>.md` och följ den som om den vore användarens prompt. Argument efter kommandot ersätter `$ARGUMENTS`.
- **En ny agent** som du skapar i `.claude/agents/` (en rekrytering, en vinnare, en ny roll) ska ha raden `include-custom-instructions: true` direkt under första `---` i frontmattern. Utan den får agenten varken `AGENTS.md` eller `CLAUDE.md`, och vet ingenting om Torget eller uppdraget.
- **Går en ny agent inte att anropa:** be användaren starta om `copilot`.
- **Skalkommandon ensamma på raden**, utan `cd` före och utan `&&`. Skripten i `tools/` är godkända i förväg bara då, annars måste människan säga ja varje gång.

**Är du Codex:**

- **Slash-kommandon** ligger i `.claude/commands/<namn>.md`. Skriver användaren `/start` (eller något annat kommando som finns där) läser du den filen och följer den som om den vore användarens prompt. Argument efter kommandot ersätter `$ARGUMENTS`.
- **Agenter** i `.claude/agents/*.md` (och `capabilities/`, `flux/genome/` där det finns) är roller. Säger ett kommando att en agent ska göra något: läs agentens fil, anta rollen och gör jobbet i den här konversationen, en roll i taget. Du har inga parallella subagenter, det är i sin ordning.
- **Filer som kommandona skapar** (nya agenter, kandidater, tidslinjer, kyrkogårdsposter) skriver du precis som beskrivet. Det är filsystemet som är tillståndet, inte sessionen.
- **Skills** under `.claude/skills/` hittar du också via `.agents/skills/`.

Svenska i allt du skriver till användaren, med korrekta å, ä och ö.
