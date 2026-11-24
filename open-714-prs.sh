#!/usr/bin/env bash
# Opens the five pull requests for #714 against GiroCrab/GiroCrab, in order.
# Each later PR names the PRs it builds on. Run from anywhere; needs `gh auth login`.
set -euo pipefail

REPO="GiroCrab/GiroCrab"
FORK="SJJaehn"
TMP="$(mktemp -d)"
trap 'rm -r "$TMP"' EXIT

FOOTER='
🤖 Generated with [Claude Code](https://claude.com/claude-code)

https://claude.ai/code/session_01DL7Jujv1jG19Krin4wi7A9'

# create <branch> <title> <body file>  -> prints the PR URL
create() {
  gh pr create -R "$REPO" --base main --head "$FORK:$1" --title "$2" --body-file "$3"
}

# fill <body file>: replaces @@P1@@ / @@P2@@ with the URLs created so far
fill() {
  sed -e "s|@@P1@@|${P1:-Teil 1}|g" -e "s|@@P2@@|${P2:-Teil 2}|g" "$1" > "$1.out"
  printf '%s\n' "$FOOTER" >> "$1.out"
  echo "$1.out"
}

# ---------------------------------------------------------------- Teil 1
cat > "$TMP/1.md" <<'EOF'
## Was sich ändert

Teil 1 von 5 für #714 (Erstattungen mit Ursprungsbuchungen verknüpfen), ersetzt zusammen mit den
Folge-PRs #1728. Dieser Teil enthält nur das Schema und die Split-Identitäten, damit parallele PRs
nicht um `STEPS`-Nummern kollidieren:

- **Schema-Schritt 39:** jeder Split-Teil bekommt eine stabile UUID und eine Anzeigeposition. Alte Teile
  erhalten eine deterministische UUIDv5 aus Buchungsidentität und Inhalt, damit zwei Geräte beim Upgrade
  dieselben IDs vergeben.
- **Schema-Schritt 40:** Tabelle `refund_links` (wird erst in Teil 2 benutzt).
- **Split-Editoren** (Mac, Linux, Windows) geben die UUIDs zurück; behaltene Teile behalten ihre Identität.
- **Sync:** der Split-Vektor (bei manuellen Buchungen zusammen mit dem Betrag) wird als Einheit gemerged.
- Betragsänderung an einer aufgeteilten manuellen Buchung verlangt eine passende neue Aufteilung.

Keine Auswertung ändert sich.

## Nachweis

| Prüfung | Ergebnis |
|---|---|
| `cargo test -q -p girocrab-core` | ok (1956 lib-Tests, Schema-Fixtures) |
| `cargo clippy -q --workspace --all-targets -- -D warnings` | ok |
| `scripts/verify-fast.sh --lint-only` | alle ok |
| `GiroCrabWindows`: `cargo test -q` | ok (303) |
| Swift-Tests (`SplitBookingTests`) | nicht gelaufen (kein Mac in der Sitzung) |
| `GiroCrabLinux` cargo test/clippy | nicht gelaufen (kein Qt), CI |

### 🤖 AI Process Reflection
- **Human-Steering:** Aufteilung der ursprünglichen PR in Schema/Core/Mac/Linux/Windows; Erstattungen sollen reine Dokumentation sein und keine Auswertung verändern.
- **AI-Agency:** Zusammenlegen der drei unveröffentlichten Schema-Schritte zu 39/40 nach dem Rebase auf main; Zuschnitt der Dateien je Teil.
- **Review-Focus:** UUIDv5-Backfill in `planning/split_ids.rs`; Merge des Split-Vektors in `sync_merge/bookings.rs`; `store_splits` (Ersetzungs-Vererbung).
- **Security-Check:** Keine neuen Netzwerk-, Prozess- oder Dateizugriffe, keine neuen Abhängigkeiten; keine neuen Logfelder.
- **Perf-Check:** Backfill läuft einmal in der Migration; `store_splits` liest nur die Teile der einen Buchung.
EOF

# ---------------------------------------------------------------- Teil 2
cat > "$TMP/2.md" <<'EOF'
## Was sich ändert

Teil 2 von 5 für #714, baut auf @@P1@@ auf (bitte zuerst mergen; bis dahin enthält der Diff dessen Commit).

Erstattungen lassen sich mit Ursprungsbuchungen oder einzelnen Split-Teilen verknüpfen, **als reine
Dokumentation**: Kategorien, Budgets, Cashflow, Insights und die lokale Schnittstelle bleiben unverändert.
Wer eine Erstattung gegen die Ausgabe verrechnen will, vergibt dieselbe Kategorie (wie heute). Die in
#1728 enthaltene Auswertungs-Projektion ist entfernt und liegt auf `archive/714-refunds-with-projection`.

- `refunds` im Core: Verknüpfen/Aufheben/Wiederherstellen (Undo per Compare-and-Set-Token), zugeordnete
  Beträge in Sync-Identitäts-Reihenfolge, Vorschläge (gleicher Betrag/Händler/Referenz, 62 Tage), Suche.
- `link_refund` meldet, ob es die Verknüpfung angelegt hat; `unlink_refund` nimmt die angezeigte
  Revision und entfernt nichts, was sich inzwischen geändert hat (CodeRabbit-Hinweise aus #1728).
- Markierungen an Buchungen (`refund_marker`, `refund_cents`, `refunded_cents`, `split_count`).
- Sync: vollständige Zeilen, Last-Writer-Wins; Import-Übernahmen, Kontenzusammenführung und Zwillinge.
- ADR 0003, `docs/ARCHITECTURE.md`, `docs/ERSTATTUNGEN_UI.md`.

## Nachweis

| Prüfung | Ergebnis |
|---|---|
| `cargo test -q -p girocrab-core` | ok (2051 lib-Tests) |
| `cargo clippy -q --workspace --all-targets -- -D warnings` | ok |
| `cargo check -q -p girocrab-core --features serde` | ok |
| `scripts/verify-fast.sh --lint-only` | alle ok |
| `GiroCrabWindows`: `cargo check --tests` | ok |

### 🤖 AI Process Reflection
- **Human-Steering:** Verknüpfungen dokumentieren nur und verändern keine Auswertung; Projektion entfernen, aber archivieren.
- **AI-Agency:** Umsetzung der CodeRabbit-Hinweise (created-Flag, CAS beim Aufheben, indizierte Verschiebeketten, Zeilen nur der betroffenen Buchung beim Kontenzusammenführen, Referenz-Tokens einmal je Buchung, strengere Tests).
- **Review-Focus:** `refunds/store.rs` (Merge, Verschiebungen, Kollisionen); `refunds/api.rs` (CAS); Markierungen in `vault/bookings.rs`.
- **Security-Check:** Keine neuen Netzwerk-, Prozess- oder Dateizugriffe, keine neuen Abhängigkeiten; Fehlertexte enthalten keine Buchungsdaten.
- **Perf-Check:** Zuordnung wird pro Datenrevision gecacht (`ChangeCache`); keine Summen über `list_transactions`; Auswertungen unberührt, daher `category_perf` unverändert.
EOF

# ---------------------------------------------------------------- Teil 3–5
cat > "$TMP/3.md" <<'EOF'
## Was sich ändert

Teil 3 von 5 für #714 (macOS/iOS), baut auf @@P1@@ und @@P2@@ auf.

- Zuordnungsblatt in beide Richtungen: eigenen Teil wählen, Vorschläge, Suche, erschöpfte Kandidaten deaktiviert, Rückgängig.
- Erstattungskarte im Inspektor (im Layout-Editor ein-/ausblendbar), Markierung in der Buchungsliste.
- Eine Verknüpfung invalidiert keine Summen mehr: nur `refundRevision` und die Listenmarkierungen laden neu.
- Aufheben übergibt die angezeigte Revision; ein Undo wird nur für selbst angelegte Verknüpfungen registriert.
- Manuelle Buchungen mit Aufteilung: Betrag und Richtung sind im Formular gesperrt.

## Nachweis

| Prüfung | Ergebnis |
|---|---|
| `swift test -q --filter RefundLinkTests` | **vor dem Öffnen auf dem Mac ausführen und hier eintragen** |
| `scripts/verify-fast.sh --lint-only` (inkl. report-dialogs, fonts, vault-access, xcstrings) | alle ok |

### 🤖 AI Process Reflection
- **Human-Steering:** Aufteilung je Plattform; keine Auswirkung auf Auswertungen.
- **AI-Agency:** Entfernen der Diagramm-/Summen-Invalidierung; Tests auf „Summen bleiben gleich“ umgestellt; CAS-Parameter beim Aufheben.
- **Review-Focus:** `AppModel+Refunds.swift` (Undo-Historie, `pinVault`, Generationen); `RefundsUI.swift` (`.sensitive()`).
- **Security-Check:** Gegenpartei, Zweck und Beträge sind mit `.sensitive()` bzw. `.sensitive(.amounts)` markiert; Blatt über `.capturableSheet`.
- **Perf-Check:** Alle Core-Aufrufe über `pin.run`/`vaultOffMain`; keine Summen über `list_transactions`.
EOF

cat > "$TMP/4.md" <<'EOF'
## Was sich ändert

Teil 4 von 5 für #714 (Linux), baut auf @@P1@@ und @@P2@@ auf.

- `RefundSheet.qml` / `RefundLinksCard.qml`: Zuordnung in beide Richtungen, Karte im Inspektor, Markierung im Buchungsstrom.
- `edit_refund` nutzt das created-Flag des Cores (kein Undo für fremde Verknüpfungen) und gibt beim Aufheben `changed_ms` mit.
- Nach einer Änderung lädt nur die Buchungsliste (Markierungen) neu; Kategorien, Dashboard und Planung bleiben.
- Startsaldo-Änderung wartet, solange eine Erstattungsänderung läuft (Undo-Reihenfolge).

## Nachweis

| Prüfung | Ergebnis |
|---|---|
| `node --test GiroCrabLinux/scripts/test-refund-navigation.mjs` | ok (19) |
| `python3 -I GiroCrabLinux/scripts/i18n-report.py` | ok |
| `(cd GiroCrabLinux && cargo fmt -- --check)` | ok |
| `GiroCrabLinux` cargo test/clippy | nicht gelaufen (kein Qt), CI |

### 🤖 AI Process Reflection
- **Human-Steering:** Aufteilung je Plattform; keine Auswirkung auf Auswertungen.
- **AI-Agency:** Ersatz der Vorab-Prüfung durch das created-Flag; Entfernen der Auswertungs-Reloads und zugehöriger Tests.
- **Review-Focus:** `src/refunds.rs` (`edit`, `sheet`, `card`); Generationsprüfungen in `AppModel.qml`.
- **Security-Check:** Keine neuen Netzwerk-, Prozess- oder Dateizugriffe; Datenschutzmodus über `Sensitive` in Blatt und Karte.
- **Perf-Check:** Laden über `loadOffMain`; die Karte liest die Gegenbuchungen tageweise (`bookings_for`), keine Summen über `list_transactions`.
EOF

cat > "$TMP/5.md" <<'EOF'
## Was sich ändert

Teil 5 von 5 für #714 (Windows), baut auf @@P1@@ und @@P2@@ auf.

- Zuordnungsdialog (`refunds_dialog.slint`), Erstattungskarte, Markierung und Betrag in der Buchungsliste.
- Die Karte lädt nur für eine andere Buchung, einen anderen Tresor oder neu geladene Daten neu, nicht bei Filter/Suche (CodeRabbit).
- Ein veraltetes Undo-Token (Kern lehnt die Wiederherstellung ab) entfernt das Rückgängig.
- Aufheben übergibt die angezeigte Revision; Verknüpfen nutzt das created-Flag.
- Analyse-Beschriftungen folgen dem Datenschutzmodus.

## Nachweis

| Prüfung | Ergebnis |
|---|---|
| `GiroCrabWindows`: `cargo test -q` | ok (328) |
| `GiroCrabWindows`: `cargo clippy -q --all-targets -- -D warnings` | ok |
| Native Windows-Ausführung | nicht gelaufen (Linux-Host) |

### 🤖 AI Process Reflection
- **Human-Steering:** Aufteilung je Plattform; keine Auswirkung auf Auswertungen.
- **AI-Agency:** Analyse und Dashboard auf den Stand von main zurückgesetzt (sie hingen an der entfernten Projektion); Karten-Reload an Auswahl/Generation gebunden.
- **Review-Focus:** `refunds_ui.rs` (Edit/Undo-Zustand); `render_bookings` in `main.rs`.
- **Security-Check:** Keine neuen Netzwerk-, Prozess- oder Dateizugriffe; Beträge und Namen über `daily::mask` im Datenschutzmodus.
- **Perf-Check:** Laden in Hintergrund-Threads mit Generationsprüfung; keine Summen über `list_transactions`.
EOF

P1=$(create feat/714-1-split-ids "feat: stabile IDs für Split-Teile und Schema für Erstattungen (#714, Teil 1)" "$(fill "$TMP/1.md")")
echo "Teil 1: $P1"
P2=$(create feat/714-2-refund-core "feat: Erstattungen mit Ursprungsbuchungen verknüpfen – Core (#714, Teil 2)" "$(fill "$TMP/2.md")")
echo "Teil 2: $P2"
P3=$(create feat/714-3-mac "feat(mac): Erstattungen zuordnen (#714, Teil 3)" "$(fill "$TMP/3.md")")
echo "Teil 3: $P3"
P4=$(create feat/714-4-linux "feat(linux): Erstattungen zuordnen (#714, Teil 4)" "$(fill "$TMP/4.md")")
echo "Teil 4: $P4"
P5=$(create feat/714-5-windows "feat(windows): Erstattungen zuordnen (#714, Teil 5)" "$(fill "$TMP/5.md")")
echo "Teil 5: $P5"

# Optional: replace #1728 by the five parts (remove the leading '#' to run it).
# gh pr close 1728 -R "$REPO" --comment "Aufgeteilt in $P1, $P2, $P3, $P4, $P5. Die Auswertungs-Projektion ist entfernt (Verknüpfungen dokumentieren nur) und liegt auf archive/714-refunds-with-projection."
