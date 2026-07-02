# redmine_ticket_reply

Aus einem Redmine-Ticket heraus E-Mails an frei wählbare Empfänger (To/CC/BCC)
senden – mit eigener Vorlage für interne und externe Empfänger. Die gesendete
Mail wird als Notiz im Ticket protokolliert.

> English version: see [README.md](README.md).

## Funktionsweise

- Button **"Per E-Mail antworten"** auf der Ticketseite (unter den Details).
- Compose-Formular mit To / CC / BCC, Betreff, Text, Vorlagenwahl und Auswahl
  vorhandener Ticket-Anhänge.
- Vorlage wird automatisch vorgewählt: gehören **alle** Empfänger zur internen
  Domäne → "Intern", sonst → "Extern". Manuell übersteuerbar.
- Versand über die in `config/configuration.yml` konfigurierte SMTP-Verbindung
  (dieselbe wie für normale Redmine-Mails).
- From/Reply-To kommen aus den Plugin-Einstellungen (Default: globale
  Redmine-Absenderadresse).
- Antworten der Empfänger landen über die `#ID` im Betreff wieder am Ticket
  (Standard-Redmine-Mailhandler).

## Voraussetzungen

**Bevor das Plugin senden kann, muss in Redmine ein funktionierender
Ausgangs-Mailer konfiguriert sein.** Das Plugin nutzt Redmines eigenen
Mailversand (`config/configuration.yml` → `email_delivery` / SMTP). Kann
Redmine keine Mails verschicken (z. B. kein SMTP-Host hinterlegt, Relay nicht
erreichbar), schlägt auch die Antwort fehl. Prüfe das zuerst unter
**Administration → Konfiguration → E-Mail-Benachrichtigungen → „Eine Test-E-Mail
senden"**. Erst wenn diese Testmail ankommt, funktioniert das Plugin.

## Installation

1. Ordner nach `plugins/redmine_ticket_reply` legen (im gemounteten
   `redmine_plugins`-Volume).
2. Redmine neu starten. Eine DB-Migration ist **nicht** nötig (das Plugin legt
   keine Tabellen an). `bundle exec rake redmine:plugins:migrate` schadet aber
   nicht.
3. **Administration → Plugins → Konfigurieren:**
   - Absenderadresse (From): `absender@mail-adresse.com`
   - Reply-To: `antwort@mail-adresse.com` (das per IMAP abgeholte Postfach)
   - Interne Domäne: `mail-adresse.com` (User im System)
   - Antwort-Trennzeile: z. B. `----- Bitte oberhalb dieser Linie antworten -----`
4. **Projekt → Einstellungen → Module:** "Ticket-Antwort (E-Mail)" aktivieren.
5. **Administration → Rollen und Rechte:** der gewünschten Rolle das Recht
   "Ticket-Antwort per E-Mail senden" geben.
6. **Administration → Konfiguration → Eingehende E-Mails →** "E-Mails nach einer
   dieser Zeilen abschneiden": dieselbe Trennzeile eintragen, damit zitierte
   Verläufe bei eingehenden Antworten abgeschnitten werden.
7. Empfehlung bei Ein-Postfach-Betrieb: Redmine-Emissionsadresse
   (Administration → Konfiguration → E-Mail-Benachrichtigungen) ebenfalls auf
   `absender@mail-adresse.com` setzen, und IMAP-Abruf (`fetchMails.sh`) auf
   `absender@` umstellen.

## Anpassen

- Templates: `app/views/ticket_reply_mailer/{external,internal}_reply.{text,html}.erb`
- Der eingegebene Text wird als reiner Text behandelt (Zeilenumbrüche werden im
  HTML zu `<br>`).

## Erweiterungsideen

- Datei-Upload direkt im Formular (derzeit nur Auswahl vorhandener
  Ticket-Anhänge).
- Textbausteine / Signaturen pro Benutzer oder Projekt.
- Statusänderung beim Senden (z. B. "warten auf Kunde").

## Textbausteine (Vorlagen)

Textbausteine sind einfache Dateien (`.txt` oder `.md`). Jede Datei = ein
Eintrag im Dropdown "Textbaustein" im Antwortformular. Beim Auswählen werden
Betreff und Text vorbefüllt (danach frei editierbar).

**Format einer Datei:**

```
Betreff: [Eingangsbestätigung] {{subject}}

Guten Tag,

vielen Dank für Ihre Nachricht (Vorgang #{{id}}) ...

Mit freundlichen Grüßen
{{agent}}
```

- Die erste Zeile `Betreff:` (oder `Subject:`) ist optional und setzt den Betreff.
- Der Rest ist der Text.
- Der Dateiname bestimmt Reihenfolge und Beschriftung: `01_eingangsbestaetigung.md`
  → Label "eingangsbestaetigung" (führende Ziffern + `_` werden entfernt,
  `_` wird zu Leerzeichen).

**Platzhalter** (werden beim Öffnen des Formulars ersetzt):

| Platzhalter            | Inhalt                          |
|------------------------|---------------------------------|
| `{{id}}`               | Vorgangsnummer                  |
| `{{subject}}`          | Ticket-Betreff                  |
| `{{status}}`           | Status                          |
| `{{author}}`           | Name des Melders                |
| `{{author_firstname}}` | Vorname des Melders             |
| `{{assignee}}`         | Name des Bearbeiters            |
| `{{agent}}`            | Vorname des angemeldeten Agenten|
| `{{agent_name}}`       | Voller Name des Agenten         |

### Wo liegen die Bausteine? Zwei Möglichkeiten

**A) Im Plugin-Ordner (einfachste Variante).** Ablage unter
`canned/` im Plugin. Da dein Plugins-Ordner ohnehin als Volume gemountet ist,
editierst du die Dateien direkt auf dem Host:

```
./redmine_plugins/redmine_ticket_reply/canned/05_meine_vorlage.md
```

Nachteil: bei einem Plugin-Update/Überschreiben können sie verloren gehen.

**B) Eigenes Volume (empfohlen für eigene Bausteine).** Lege die Vorlagen außerhalb
des Plugins ab und mounte sie. In der `docker-compose.yml` beim `redmine`-Service:

```yaml
    volumes:
      # ... bestehende Mounts ...
      - ./redmine_templates:/redmine_templates
```

Dann in Administration → Plugins → "Ticket Reply (E-Mail)" konfigurieren:
"Vorlagen-Verzeichnis" = `/redmine_templates`. Die Dateien liegen jetzt auf dem
Host unter `./redmine_templates/*.md` und überleben Plugin-Updates.

### In Betrieb nehmen

- **Baustein hinzufügen/ändern:** Datei anlegen/bearbeiten – **kein Neustart nötig**,
  die Bausteine werden bei jedem Öffnen des Formulars frisch eingelesen. (Bei
  Variante B mit neuem Volume einmalig `docker compose up -d` zum Einhängen.)
- **ERB-Templates ändern** (`app/views/ticket_reply_mailer/*.erb`, also die Hülle
  mit Grußrahmen/Footer): Diese werden in Produktion zwischengespeichert, daher
  danach den Container neu starten: `docker compose restart redmine`.

## Verfügbare Platzhalter (Variablen)

In Bausteinen, Betreff und Signatur verwendbar. Werden beim Öffnen des
Formulars für das jeweilige Ticket/den angemeldeten Agenten ersetzt:

| Platzhalter            | Inhalt                              |
|------------------------|-------------------------------------|
| `{{id}}`               | Vorgangsnummer                      |
| `{{subject}}`          | Ticket-Betreff                      |
| `{{status}}`           | Status                              |
| `{{author}}`           | Name des Melders                    |
| `{{author_firstname}}` | Vorname des Melders                 |
| `{{assignee}}`         | Name des Bearbeiters                |
| `{{agent}}`            | Vorname des angemeldeten Agenten    |
| `{{agent_name}}`       | Voller Name des angemeldeten Agenten|
| `{{signature}}`        | Signatur des angemeldeten Agenten   |

## Signaturen (pro Benutzer)

Jeder Agent pflegt seine eigene Signatur in seinem Redmine-Profil:

1. **Administration → Benutzerdefinierte Felder → Benutzer → Neues Feld:**
   Format "Langer Text", Name z. B. `E-Mail-Signatur`. Für die Rollen
   sichtbar/bearbeitbar machen.
2. Der Feldname muss mit der Plugin-Einstellung **"Signatur-Feld (Benutzer)"**
   übereinstimmen (Default: `E-Mail-Signatur`).
3. Jeder Agent trägt seine Signatur unter **"Mein Konto"** ein.

Verhalten:

- Ist **"Signatur automatisch anhängen"** aktiv (Default), wird die Signatur des
  angemeldeten Agenten ans Ende der Mail gehängt – außer der Text enthält sie
  bereits (z. B. weil ein Baustein `{{signature}}` verwendet). So gibt es keine
  doppelte Signatur.
- Mit `{{signature}}` platzierst du die Signatur in einem Baustein an einer
  bestimmten Stelle selbst.
- Hat ein Agent keine eigene Signatur hinterlegt, greift die **"Standard-Signatur"**
  aus den Plugin-Einstellungen (falls gesetzt).

Signaturen und Bausteine brauchen **keinen Neustart** – sie werden bei jedem
Öffnen des Formulars frisch gelesen.

## Ticket beim Senden schließen

Im Antwortformular gibt es den Haken "Ticket nach dem Senden schließen".
Ablauf: Die Mail wird zuerst versendet, danach wird der Status auf einen
geschlossenen Status gesetzt.

- Welcher Status: Plugin-Einstellung "Status beim Schließen" (Name). Leer =
  erster laut Workflow erlaubter geschlossener Status.
- **Abhängigkeiten werden abgefangen:** Lässt sich das Ticket nicht schließen
  (z. B. weil es durch ein offenes anderes Ticket blockiert ist, offene
  Unteraufgaben hat oder der Workflow den Übergang nicht erlaubt), bleibt die
  Notiz erhalten, das Ticket bleibt offen, und im Formular erscheint eine
  Warnung mit dem konkreten Grund. Die Mail ist in jedem Fall raus.

## Editor (Formatierung) und Vorschau

Das Textfeld nutzt die normale Redmine-Wiki-Symbolleiste (Fett, Kursiv,
Durchgestrichen, Listen, Links, Code …) – abhängig von der eingestellten
Textauszeichnung (Markdown/Textile). Unterstreichen ist in Markdown nicht
vorgesehen und daher nicht in der Leiste.

Über die Tabs "Bearbeiten" / "Vorschau" siehst du das gerenderte Ergebnis. Der
Text wird in der E-Mail genauso gerendert wie ein Ticket-Kommentar: Der
HTML-Teil enthält die formatierte Fassung, der Text-Teil die Markup-Quelle.

## Versionen

- **1.3.0** – Sicherheitshärtung: Ticket-Sichtbarkeit wird erzwungen
  (`@issue.visible?`), alle Empfängeradressen werden validiert (Format +
  Steuerzeichen), CR/LF wird aus dem Betreff entfernt, und Fehlermeldungen
  zeigen dem Benutzer keine internen Details mehr (nur noch im Server-Log).
  Englische `README.md` ergänzt, diese Datei als `README_de.md`.

- **1.2.x** – Zwischenstände (An/CC/BCC-Feinschliff, Detailkorrekturen); nicht
  einzeln dokumentiert.

- **1.1.3** – Anzeige der erfassten Adressen zusaetzlich als sichtbarer
  Server-Kasten (theme-unabhaengig); JS schiebt sie an die Autorenzeile und
  blendet den Kasten bei Erfolg aus.

- **1.1.2** – Fix: MailHandler-Patch wird jetzt direkt beim Plugin-Laden
  eingehängt (das fruehere config.to_prepare feuerte in Produktion nicht,
  weil Redmine Plugins bereits in einem to_prepare-Lauf laedt).

- **1.1.1** – Erfasster Absender + weitere Adressaten werden direkt an der
  Autorenzeile des Tickets angezeigt (per View-Hook + JS, keine Migration).

- **1.1.0** – Adress-Erfassung anonymer Mails (From/To/Cc) für An/CC-Vorbefüllung
  und Reply-All; Anzeige des letzten Absenders am Ticket; MailHandler-Patch.
- **1.0.0** – Editor-Toolbar + Vorschau, Ticket-Abschluss beim Senden (mit
  Abhängigkeits-Abfangung), Signaturen pro Benutzer, Textbausteine, Verlauf-Anhang.

## Absender/Empfänger anonymer Mails (Adress-Erfassung)

Mit `unknown_user=accept` ist der Autor anonymer Mails der Anonymous-Benutzer
(ohne Mail-Adresse). Damit man trotzdem antworten kann, schneidet das Plugin
beim IMAP-Empfang `From`, `To` und `Cc` jeder eingehenden Mail mit und speichert
sie pro Ticket (Tabelle `ticket_reply_contacts`) – bei jeder Folge-Mail neu, also
immer die Adressen der **zuletzt** eingegangenen Mail.

Im Antwortformular wird dann:

- **An** = letzter Absender,
- **CC** = übrige Empfänger der letzten Mail (To + Cc), ohne eure eigenen
  Postfächer (Reply-All).

Eigene Postfächer/Aliase, die aus dem CC entfernt werden sollen, trägst du in der
Plugin-Einstellung "Eigene Postfächer/Aliase" ein (From/Reply-To/globale
Absenderadresse sind automatisch dabei). Der letzte Absender wird zusätzlich am
Ticket angezeigt.

**Hinweis:** Die Erfassung greift für Mails, die **nach** der Installation dieser
Version eingehen. Für Alt-Tickets ist das Feld einmalig leer und wird beim
nächsten Maileingang gefüllt.

### Migration nötig

Diese Version legt eine Tabelle an:

```
docker exec hitredmine bash -lc 'cd /usr/src/redmine && RAILS_ENV=production bin/rails redmine:plugins:migrate'
docker compose restart redmine
```

## Der MailHandler-Patch und Redmine-Updates

Die Adress-Erfassung hängt sich an zwei Methoden von Redmines `MailHandler`:
`receive_issue` (neues Ticket aus Mail) und `receive_issue_reply` (Folgeantwort).

Technik: Es wird **kein** Redmine-Kernfile verändert. Der Patch ist ein
`Module#prepend` (Datei `lib/redmine_ticket_reply/mail_handler_patch.rb`), das
beim Laden des Plugins aktiviert wird (direkter Prepend) und die
Originalmethode per `super` aufruft.

Folgen für ein Redmine-Update:

- **Keine Merge-Konflikte:** Da keine Kerndateien angefasst werden, überlebt der
  Patch ein Redmine-Update unverändert – er wird beim Start automatisch neu
  aktiviert.
- **Einzige Kopplung:** die Methodennamen `receive_issue` / `receive_issue_reply`.
  Diese sind in Redmine seit vielen Versionen stabil.
- **Robust gegen Wegfall:** Sollte eine künftige Redmine-Version diese Methoden
  umbenennen oder entfernen, fällt die Adress-Erfassung **still** aus – kein
  Absturz, da der Aufruf dann an unserem Wrapper vorbeiläuft. Das Antworten
  funktioniert weiter (man muss die Adresse dann ggf. von Hand eintragen), nur
  die automatische Vorbefüllung würde fehlen.

**Nach einem Redmine-Upgrade prüfen:** Eine Testmail ans System schicken und am
Ticket kontrollieren, ob "Letzter Mail-Absender" gefüllt wird (bzw. im
`production.log` nach `[TicketReply] ContactCapture` schauen). Erscheint nichts,
müssen nur die zwei Methodennamen in `mail_handler_patch.rb` an die neue
Redmine-Version angepasst werden – eine Ein-Zeilen-Änderung pro Methode.

Hinweis: Die übrigen Bausteine (Mailer, Controller, Views, Textbausteine,
Signaturen, Schließen-Logik) nutzen ausschließlich öffentliche Redmine-/Rails-APIs
und sind von Redmine-Updates praktisch nicht betroffen. Der MailHandler-Patch ist
die einzige Stelle, die an Redmine-Interna andockt.
