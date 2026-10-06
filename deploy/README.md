# Deploy

Det här är den lilla halvan: att skicka upp `board/` till en server som redan är uppsatt.

```bash
printf 'root@<serverns-ip>\n' > .deploy-host   # gitignorerad, görs en gång
deploy/deploy.sh                               # eller: HOST=root@<serverns-ip> deploy/deploy.sh
```

**`.deploy-host` är inte valfri under dagen.** `tools/release.sh deploy` kör det här skriptet, och utan filen
avbryts hela release-varvet. Den som ska köra release behöver alltså tre saker i sin egen klon: merge-rätt i
repot, en ssh-nyckel som servern släpper in, och `.deploy-host` i repo-roten. Bygger du repot med workshopladans
`verktyg/deltagarrepo.sh` skrivs filen i verktygens egen klon åt dig; kör du release från en annan klon skriver
du den själv med raden ovan.

Skriptet rsync:ar `board/`, lägger enhetsfilen på plats, startar om tjänsten, ser till att domänen
finns i Caddyfilen och kollar hälsan. Det går att köra om hur många gånger som helst.
`qr.png` och `qr.svg` undantas med flit: de är gitignorerade och finns inte i en färsk klon, så utan
undantaget skulle `--delete` radera storskärmens qr-kod från servern vid dagens första deploy.

Att sätta upp servern från noll (Vultr, Node, Caddy, brandvägg, DNS) hör hemma hos den som håller workshopen,
inte i det här repot. Det ligger i **workshopladan**: `verktyg/provisionera.sh`, `verktyg/vultr.sh`, `verktyg/dns.sh`.

`torget.service`, `Caddyfile.snippet` och `deploy.sh` innehåller platshållare (`8180`, `torget.bjarby.com`,
`torget`, `/opt/torget`, `/var/lib/torget`) som stämplas när repot byggs ur mallen.
Ingen IP-adress och ingen domän är inskriven i repot.
