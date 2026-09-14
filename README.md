🇬🇧 [English](README.en.md) | 🇩🇪 Deutsch

# gelkao CLI

[![CI](https://github.com/gelkao/cli/actions/workflows/ci.yml/badge.svg?branch=master)](https://github.com/gelkao/cli/actions/workflows/ci.yml)
[![integration](https://img.shields.io/endpoint?url=https://gist.githubusercontent.com/dominikzalewski/696b0e161d53e5b752b2c6bc7c0fbf74/raw/gelkao-cli-integration.json)](https://gist.github.com/dominikzalewski/696b0e161d53e5b752b2c6bc7c0fbf74)

**Ein Schweizer Zero-Trust-Taschenmesser für alles, was Hetzner dir über deinen Account nicht verrät.**

Kein Account, kein Login, nichts wird hochgeladen - es liest, was du ohnehin schon
hast, rechnet auf deinem Rechner und ist fertig. Grep durch den Quellcode und
überzeug dich selbst.

**Fragen? [Discussions](https://github.com/gelkao/cli/discussions) oder [private Nachricht im Hetzner-Forum](https://forum.hetzner.com/wcf/index.php?conversation-add/&userID=41011).**

[Website](https://gelkao.com) |
[Dokumentation](https://gelkao.com/docs/latest/)

| Befehl | Frage | Handbuch |
|---|---|---|
| `gelkao volume` | Was fällt gemeinsam aus? | [gelkao volume](https://gelkao.com/docs/latest/volume/) |
| `gelkao invoice` | Was zahlst du zu viel? | [gelkao invoice](https://gelkao.com/docs/latest/invoice/) |

## Schnellstart

### gelkao volume

Die Platzierungstabelle, die dir der Hetzner-Support auf Anfrage schickt, sagt dir,
welche deiner Volumes am selben Netzwerk-Switch hängen. Auch dafür liegt ein
Beispiel im Repo:

```
./gelkao volume draw < examples/example-volumes-real-fleet.tsv
./gelkao volume show < examples/example-volumes-real-fleet.tsv
```

<p align="center"><img src="img/volume-demo.webp" alt="Beispielausgabe von gelkao volume draw"></p>

<p align="center">🟥 zu viele Volumes auf einem Leaf · 🟧 Achtung · 🟩 unkritisch</p>

### gelkao invoice

Probier es erst ohne Account aus – das Repo bringt eine kleine synthetische
Server-Flotte mit, die du direkt nach dem Klonen auditieren kannst:

```
./gelkao invoice audit -q -d examples
```

Dann lass es auf deine eigene Rechnung los.

- Öffne: https://accounts.hetzner.com/invoice
- Speichere die Seite als HTML im Verzeichnis `data/`

<p align="center"><img src="img/hetzner-invoice.de.png" alt="Seite als HTML speichern"></p>

- Führe `cat data/*.html | ./gelkao invoice audit -` aus

<p align="center"><img src="img/audit-demo.svg" alt="Beispielausgabe der Cloud Inefficiency Audit"></p>

<p align="center">🟥 ≥ 50 % · 🟧 20–49 % · 🟩 unter 20 %</p>

Für Power-User: `cat data/*.html | ./gelkao invoice list | ./gelkao invoice fetch && ./gelkao invoice audit`

## Beispiel aus der Praxis

[Kann man auf der Hetzner Cloud ein ausfallsicheres System mit kleinem Budget bauen?](https://gelkao.com/blog/is-it-possible-to-build-fault-tolerant-budget-system-on-hetzner-cloud/)
kartiert eine echte Flotte mit 199 Volumes: sechs Switches tragen mehr als die
Hälfte davon, einer davon allein 24.

[Du bist wahrscheinlich auf der falschen Cloud-Box](https://gelkao.com/blog/how-cost-efficient-is-mytimeplan-com-cloud/) (englisch)
ist eine Fallstudie über die echte Hetzner-Flotte von [mytimeplan.com](https://mytimeplan.com).
Exakte Zahlen: 14 Monate, 193 Server, 1.878 €/Monat, **23 % zu viel gezahlt.**

## Teile dein Ergebnis

Audit durchgelaufen? Poste dein Ergebnis in den [Discussions](https://github.com/gelkao/cli/discussions/11) – keine E-Mail, nichts wird hochgeladen, nur das, was du selbst einfügst.

## Voraussetzungen

`gelkao` ist ein kleines Shell-Tool mit ein paar Standard-Abhängigkeiten:

- **bash** 3.2+ - die mitgelieferte bash von macOS reicht.
- **sqlite3** 3.8.3+ - die Audit-Engine.
- **curl** - um Rechnungen herunterzuladen (`fetch`) und, falls du die optionale Preisaktualisierung zulässt, die Preistabellen; lehnst du die Abfrage ab oder übergibst `-q`, bleibt das Audit vollständig offline.
- **rsvg-convert** und **cwebp** - nur für `gelkao volume draw`, das die Karte als WebP rendert. `gelkao volume show` und alles unter `invoice` brauchen sie nicht.
- Standard-POSIX-Tools (`grep`, `sed`, `head`), auf jedem Unix vorhanden.
- **Windows:** in WSL (Windows Subsystem for Linux) ausführen; dann verhält es sich genau wie unter Linux oben.

## Deine Daten bleiben auf deiner Platte

`gelkao` läuft komplett auf deinem Rechner – ein lokales Command-Line-Tool, kein SaaS-Dashboard. Kein Account, kein Login, nichts wird hochgeladen.

- **Nur Download:** jeder Request ist ein simpler HTTP-GET – es lädt deine Rechnungen von
Hetzner und, wenn du es zulässt, die öffentlichen Hetzner-Preistabellen von `gelkao.com`, und lädt
nichts hoch. Diese Preisaktualisierung ist eine interaktive Abfrage (`[Y/n]`); lehne mit `n` ab oder
überspring sie ganz mit `-q` oder jedem nicht-interaktiven Lauf (Pipe, CI).
- **Abrechnungsdaten bleiben in `data/`**, das per gitignore ausgeschlossen ist – halte sie aus der
Versionsverwaltung, aus Tickets und aus geteilten Ablagen heraus.
- **Kein gelkao-Account, kein Passwort:** eine Rechnung wird mit zwei Geheimnissen abgerufen, die du
schon hast – ihrem `usage.hetzner.com/<uuid>`-Link und deiner Kundennummer (`K…`) – die zusammen wie
ein zweiter Faktor wirken.

Sicherheitsproblem gefunden oder willst du diese Aussagen selbst überprüfen? Siehe [SECURITY.md](SECURITY.md).

## Tests

Die Unit- und Report-Tests sind hermetisch – kein Netzwerk, keine Zugangsdaten –
und laufen bei jedem Push in der CI (Linux und macOS). Der Integrationstest
braucht eine echte Kundennummer und eine gespeicherte Rechnungsseite –
Geheimnisse, die niemals auf einen öffentlichen CI-Runner gelangen dürfen –,
deshalb läuft er nur auf deinem Rechner:

```
INVOICE_HTML=data/your-invoices.html bats tests/*.bats
```

- `gelkao` teilt sich seine Logik mit `lib.sh`.
- `tests/unit.bats` deckt diese Funktionen ohne Netzwerk und ohne Zugangsdaten ab.
- `tests/volume.bats` deckt das Einlesen der Platzierungstabelle, den Baum und die Farb- und Flächenlogik der Treemap ab.
- `tests/report.bats` deckt die Feldstatistiken und die zusammengesetzte Ausgabe des Audit-Reports ab.
- `tests/badge.bats` deckt die reine Logik des Badge-Builders ab.
- `tests/integration.bats` benötigt eine echte Kundennummer und eine echte Rechnungs-HTML-Seite.

### Integrations-Badge

Weil der Integrationstest nicht in der Cloud-CI laufen kann, führt `./badge.sh`
ihn lokal aus und veröffentlicht die Anzahl bestandener Tests in einem Gist, das
das Integrations-Badge im README speist – so spiegelt das Badge einen echten Lauf
gegen echte Rechnungen wider, nicht die CI:

```
INVOICE_HTML=data/your-invoices.html ./badge.sh
```

## Referenzen

- [Hetzner 2024-10 Billing System Changes](https://docs.hetzner.com/general/billing-and-account-management/billing-at-hetzner/billing-system-hetzner/)
- [Hetzner Cloud API — Rate Limiting (3600 requests/hour)](https://docs.hetzner.cloud/#rate-limiting)

## Lizenz

Lizenziert unter der Apache License 2.0 – siehe [LICENSE](LICENSE) und [NOTICE](NOTICE).
