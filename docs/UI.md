# Spectre Studio — Specifica di stile e interfaccia

Riferimento visivo: `ex_blog`. **Solo stile e UI.** Nessuna funzione, nessun modulo di
dominio e nessuna dipendenza del blog entra in Studio: si portano il linguaggio visivo,
i token, il vocabolario dei componenti e le regole di composizione.

Studio è un control center: schermate dense, molti dati numerici, stati che cambiano in
tempo reale. Il linguaggio del blog regge bene questa densità proprio perché è
monocromatico e tabulare — ma va **esteso**, non piegato. Questo documento definisce sia
ciò che si porta identico, sia le estensioni nuove scritte nella stessa lingua.

---

## 1. I principi del linguaggio

Sono le regole che rendono il blog riconoscibile. Valgono in Studio senza eccezioni.

1. **Un solo font, monospazio, ovunque.** `--font-sans`, `--font-mono` e `--font-serif`
   puntano tutti allo stesso stack: `ui-monospace, "JetBrains Mono", "Fira Code",
   "SFMono-Regular", Menlo, Consolas, "Liberation Mono", monospace`.
   `font-variant-ligatures: none`. Non esiste un font di testo separato.
2. **Monocromatico.** La gerarchia nasce da tre leve, mai dal colore:
   contrasto del tono (`--fg-strong` → `--fg` → `--fg-dim` → `--fg-faint`),
   inversione (`--invert-bg`/`--invert-fg`) e peso del bordo (`--line` → `--line-strong`).
3. **Il colore ha due soli usi**: l'esito di un controllo (`--state-ok`, `--state-fail`)
   e la sintassi dentro i blocchi di codice. Mai decorativo, mai per il branding.
4. **Il colore non porta mai da solo un significato.** Ogni stato colorato è sempre
   accompagnato da una parola e da un glifo, così sopravvive in monocromia e per chi non
   distingue i toni.
5. **Nessun valore cromatico nel markup.** Sempre token:
   `class="border-[color:var(--line)] text-[color:var(--fg-dim)]"` o le utility di tono.
6. **Il vocabolario è il terminale.** Prompt `$ `, output `› `, commento `// `,
   checkbox `[ ]`/`[x]`, select `▾`, barra codice `● ● ●`, cursore lampeggiante,
   percorsi come etichette (`./connections`, `./lab`).
7. **Micro-interazioni sobrie.** Transizioni 140–200 ms su `background-color`,
   `border-color`, `color`. Solo le card cliccabili si sollevano
   (`translateY(-2px)` + ombra molto morbida). Niente scale, niente rimbalzi.
8. **Densità alta, ritmo regolare.** Corpi tra 0.66rem e 0.85rem; le etichette
   maiuscole hanno sempre `letter-spacing` ampio; i bordi tratteggiati separano,
   quelli pieni contengono.
9. **Il buio è il default**, la luce è opt-in: `<html data-theme="dark">` e toggle
   persistito in `localStorage`.
10. **Focus sempre visibile**: `outline: 1px dashed var(--fg-strong)`, `offset: 3px`.

---

## 2. Token

Si portano identici. Dark è il default; light ridefinisce gli stessi nomi.

| Token | Dark | Light | Ruolo in Studio |
| --- | --- | --- | --- |
| `--page-bg` | `#050506` | `#f4f4f2` | Fondo pagina, sotto la griglia |
| `--surface` | `#0b0b0d` | `#fbfbfa` | Corpo dei pannelli |
| `--surface-raised` | `#101013` | `#ffffff` | Pannello in primo piano, dettaglio selezionato |
| `--surface-bar` | `#131317` | `#ececea` | Barra titolo, `th`, hover di riga |
| `--surface-translucent` | `rgba(5,5,6,.86)` | `rgba(244,244,242,.88)` | Header sticky con `backdrop-blur` |
| `--line` | `#22222a` | `#d9d9d4` | Bordo normale, separatori tratteggiati |
| `--line-strong` | `#3b3b46` | `#a8a8a2` | Bordo di elemento attivo o interattivo |
| `--fg-strong` | `#f5f5f7` | `#0a0a09` | Valori, titoli, numeri delle metriche |
| `--fg` | `#c9c9d1` | `#33332f` | Testo corrente |
| `--fg-dim` | `#7d7d89` | `#6f6f69` | Etichette, unità di misura, testo secondario |
| `--fg-faint` | `#4b4b55` | `#9a9a94` | Glifi del prompt, timestamp, chiavi |
| `--grid` | `rgba(255,255,255,.028)` | `rgba(0,0,0,.035)` | Reticolo 46 px della shell |
| `--state-ok` | `#8fcf9a` | `#2f6b3c` | Connesso, verifica superata, alive |
| `--state-fail` | `#e08a8a` | `#9c3a3a` | Disconnesso, errore, verifica fallita |
| `--invert-bg` / `--invert-fg` | `#f5f5f7` / `#050506` | `#0a0a09` / `#f7f7f5` | Bottone primario, chip attivo, tab selezionata |
| `--field-bg` | `#08080a` | `#ffffff` | Fondo degli input |
| `--code-bg` / `--code-bar` | `#08080a` / `#141419` | **restano scuri** | Payload JSON, sempre su fondo scuro nei due temi |
| `--hl-*` | fissi nei due temi | idem | Sintassi: keyword, atom, string, number, sigil, comment |

**Uno stato in più rispetto al blog.** Un control center ha un terzo esito, l'attesa. Si
introduce `--state-wait` (dark `#d9c48a`, light `#7a6320`) usato **solo** per
`:connecting`, `:authenticating`, `degraded`. Resta dentro la regola 4: sempre con parola
e glifo.

---

## 3. Scala tipografica

Le dimensioni non sono libere: sono quelle del blog, riusate per gli stessi ruoli.

| Dimensione | `letter-spacing` | Uso in Studio |
| --- | --- | --- |
| `0.55rem` | `0.3em` | Puntini `● ● ●` sopra i blocchi di codice |
| `0.66rem` | `0.12em`, maiuscolo | Intestazioni di tabella |
| `0.68rem` | `0.04em`–`0.12em` | Barra del pannello, chip, label dei campi (maiuscole) |
| `0.72rem` | — | Navigazione, testo di supporto, timestamp |
| `0.78rem` | `0.08em` sulle chiavi | Celle di tabella, liste chiave/valore |
| `0.80rem` | `0.02em` | Testo dei bottoni, peso 600 |
| `0.85rem` | — | Input, corpo dei paragrafi |
| `1.25–1.5rem` | `tracking-tight` | Titolo di sezione, peso 700 |
| `1.75–2.25rem` | `tracking-tight`, tabular | **Nuovo:** numero della metrica |

Per ogni numero che cambia nel tempo: `font-variant-numeric: tabular-nums`. Senza questo,
una metrica che si aggiorna ogni secondo balla in larghezza — inaccettabile in un pannello
live.

---

## 4. Componenti portati identici

Dal foglio di stile del blog, senza modifiche se non l'eliminazione di ciò che riguarda
gli articoli.

| Classe / componente | Ruolo in Studio |
| --- | --- |
| `.site-shell` | Fondo a reticolo 46 px dell'intera app |
| `.term-window`, `--raised`, `--link` | Il contenitore di **ogni** riquadro |
| `.term-bar`, `.term-dots`, `.term-dot`, `.term-title` | Barra titolo con i tre puntini |
| `.term-body` | Corpo del riquadro |
| `.term-prompt`, `.term-out`, `.term-comment` | Prefissi `$ `, `› `, `// ` |
| `.term-cursor` | Cursore lampeggiante nel brand e negli stati di attesa |
| `.term-chip`, `--active` | Filtri, scope, capacità, tab |
| `.term-rule` | Separatore tratteggiato |
| `.term-btn`, `--primary` | Azioni |
| `.term-field`, `.term-select`, `.term-label`, `.term-check` | Form |
| `.term-code` | Payload JSON, envelope, snapshot |
| `.term-table` | Elenchi tabulari |
| `.term-list`, `__key`, `__value` | Coppie chiave/valore |
| `.term-flash` | Notifiche |
| `.t-strong`, `.t-body`, `.t-dim`, `.t-faint`, `.t-invert`, `.t-ok`, `.t-fail` | Utility di tono |
| Componenti funzione | `term_window/1`, `cursor/1`, `flash/1`, `button/1`, `input/1`, `header/1`, `table/1`, `list/1`, `icon/1` |

**Non si porta**: `.article-prose`, lo stile di CookieConsent, i meta OG/Twitter/JSON-LD,
il selettore di lingua, i link a feed e sitemap. Sono funzioni del blog, non stile.

---

## 5. Estensioni Studio

Otto componenti nuovi. Ognuno è scritto nel vocabolario esistente: nessun elemento
introduce un colore, un raggio o una scala che il blog non abbia già.

### `.term-led` — stato di connessione

Cerchio da 0.5rem con bordo, riempito dal token di stato, sempre seguito dalla parola.

```text
● ready          ← --state-ok
◐ connecting     ← --state-wait, animazione di pulsazione 1.05s (stessa cadenza del cursore)
○ closed         ← --fg-faint
● error          ← --state-fail
```

Il glifo cambia con lo stato, non solo il colore. `prefers-reduced-motion` ferma la
pulsazione.

### `.term-metric` — numero osservato

```text
┌──────────────────────┐
│ MEMORY               │  0.68rem, maiuscolo, 0.12em, --fg-dim
│ 42.2 kB              │  1.75rem, 700, tabular, --fg-strong
│ // +536 B in 3s      │  0.68rem, --fg-faint
└──────────────────────┘
```

Unità sempre separata dal numero e in `--fg-dim`: il valore resta leggibile a colpo
d'occhio anche in una griglia di sei metriche.

### `.term-spark` — serie temporale

SVG inline, `polyline` a `stroke-width: 1`, colore `--fg-dim`, nessun riempimento,
nessun gradiente, nessuna curva. Il campione corrente è un quadrato di 2 px in
`--fg-strong`. Le **lacune di osservazione** (salti di `sequence`, `dropped_updates > 0`)
sono rese come segmento tratteggiato in `--fg-faint`, mai interpolate: la linea si
interrompe visibilmente.

### `.term-gauge` — saturazione

Per mailbox e backpressure, dove serve un rapporto e non una serie. Disegnata con
caratteri a blocchi, non con una barra arrotondata:

```text
mailbox  ▓▓▓▓▓▓▒▒░░░░░░░░  6/16
```

`▓` in `--fg-strong`, `▒` in `--fg-dim`, `░` in `--fg-faint`. Quando supera la soglia,
i pieni passano a `--state-fail` e compare la parola `saturated`.

### `.term-rail` — navigazione sinistra

Colonna fissa da 13rem, bordo destro `--line`, voci come percorsi. La voce attiva usa
la sottolineatura tratteggiata del blog, non un fondo pieno.

```text
./connections
  ● prod-eu        ← LED + etichetta, indentato
  ○ staging
./lab
./events
```

Sotto i 1024 px il rail collassa in una riga di `.term-chip` orizzontale scorrevole.

### `.term-tabs` — sezioni di un Agent

Idioma a parentesi quadre, coerente col selettore di lingua del blog:

```text
[ overview | live | messages | lab | events ]
```

Separatori `|` in `--fg-faint`, voce attiva in `t-strong` con sottolineatura tratteggiata.
Una voce non autorizzata **non compare**: nessun elemento disabilitato nel DOM.

### `.term-stream` — flusso di eventi

Log a tre colonne: timestamp `--fg-faint`, glifo, testo. Riusa i prefissi esistenti:
`$ ` per un comando inviato da Studio, `› ` per una risposta, `// ` per una nota di
sistema. Bordo tratteggiato tra le righe come `.term-list`. Autoscroll con hook
colocato, sospeso quando l'operatore scorre indietro.

```text
12:04:31  $ agent.runtime.monitor.enable  researcher  1000ms
12:04:31  › enabled  sub 019a…3f  seq 0
12:04:32  › update   seq 1  mem 42.2 kB  mbox 0
12:04:35  // 2 samples coalesced — observation gap
12:04:40  › error    routing/instance_not_found
```

### `.term-diff` — confronto

Righe con marcatore `+` / `-` / `~` in prima colonna. Il colore sta **solo sul glifo**
(`--state-ok`, `--state-fail`, `--fg-dim`); il testo resta nei toni normali e il fondo
non si colora mai. Così un diff lungo non diventa una parete di verde e rosso.

---

## 6. Impianto delle schermate

Larghezza massima del contenuto `max-w-6xl` come nel blog, tranne le viste dense
(dashboard live, Lab) che usano `max-w-[110rem]` per sfruttare i monitor larghi.

### Shell

```text
┌───────────────────────────────────────────────────────────────────────────┐
│ ●●●  spectre@studio:~$ █          ./connections  ./lab  ./events    [☾]   │  header sticky,
├──────────────┬────────────────────────────────────────────────────────────┤  blur, --surface-translucent
│              │                                                            │
│ ./connections│   contenuto                                                │
│   ● prod-eu  │                                                            │
│   ○ staging  │                                                            │
│ ./lab        │                                                            │
│ ./events     │                                                            │
│              │                                                            │
├──────────────┴────────────────────────────────────────────────────────────┤
│ $ echo "spectre studio — 2 connections, 7 agents"          exit status 0   │  footer, --fg-faint
└───────────────────────────────────────────────────────────────────────────┘
```

Il fondo è `.site-shell`, quindi il reticolo attraversa tutta l'app.

### `/` — la dashboard

Studio non ha una schermata di accesso: si lancia e si è già dentro. La prima
cosa che appare è l'elenco delle connessioni.

Griglia di `.term-window--link`, una per connessione. Card cliccabile: al passaggio si
solleva di 2 px e il primo puntino della barra si accende, esattamente come le card
del blog.

```text
┌─ prod-eu ───────────────────────── wss ─┐  ┌─ staging ──────────────── wss ─┐
│ ● ready                                  │  │ ◐ connecting                   │
│ › agents        4                        │  │ › agents        —              │
│ › scopes        runtime.read, stream     │  │ › scopes        —              │
│ › connected     12:01:44 (3m ago)        │  │ › attempt       2 of ∞         │
│ [ open ]  [ disconnect ]                 │  │ [ cancel ]                     │
└──────────────────────────────────────────┘  └────────────────────────────────┘
```

Stato vuoto scritto come output di terminale, non come illustrazione:

```text
// no connections configured
$ ./new-connection
```

### `/connections/:id`

```text
┌─ manifest ────────────────────────────────────── spectre.studio/1 ─┐
│ › principal     operator-42  ·  spectre://studio/operator-42       │
│ › transport     websocket · listen                                 │
│ › granted       [agent.runtime.read] [agent.runtime.stream]        │  chip
│ › withheld      [lab.read] [ledger.read]                           │  chip tratteggiata, --fg-faint
└────────────────────────────────────────────────────────────────────┘

┌─ exposed agents ──────────────────────────────────────── 4 agents ─┐
│ ADDRESS                     DISPLAY        CAPABILITIES     PROTO  │  .term-table
│ spectre://acme/researcher   Researcher     research         1      │
│ spectre://acme/coordinator  Coordinator    delegate, plan   1      │
└────────────────────────────────────────────────────────────────────┘
```

Gli scope concessi sono chip normali; quelli non concessi sono chip con bordo
tratteggiato in `--fg-faint`, così l'operatore vede subito **cosa manca e perché** una
funzione non è disponibile.

### Agent — i quattro pannelli

Ogni tab è una pagina a sé: `overview`, `live`, `messages`, `events`. Il tab non
autorizzato non compare. L'intestazione e la striscia dei tab sono le stesse su
tutte e quattro.

### Agent — tab `live`

La schermata più densa. Tre fasce verticali dentro un solo `.term-window`.

```text
┌─ spectre://acme/researcher ──────────── ● alive · sub 019a…3f · seq 148 ─┐
│ [ overview | live | messages | lab | events ]                            │
├──────────────────────────────────────────────────────────────────────────┤
│  MEMORY        MAILBOX       REDUCTIONS      STATUS       HEAP           │  griglia 5 metriche
│  42.2 kB       0             18 291          waiting      2 584          │
│  ▁▂▂▃▂▁▁▂▄▃▂   ▁▁▁▁▂▁▁▁▁▁▁   ▁▂▃▄▅▆▇▇▇▇▇     —            ▁▁▂▂▂▂        │  .term-spark
├──────────────────────────────────────────────────────────────────────────┤
│  interval [1000 ms ▾]   duration [60 s ▾]   fields [4 selected ▾]        │
│  [ disable live ]                              // 2 observation gaps     │
├──────────────────────────────────────────────────────────────────────────┤
│  12:04:31  $ monitor.enable                                              │  .term-stream
│  12:04:32  › update  seq 1                                               │
└──────────────────────────────────────────────────────────────────────────┘
```

Regole di stato in questa vista:

- prima dell'attivazione le metriche mostrano `—` in `--fg-faint` e il bottone è
  `[ enable live ]` in variante primaria: **il pannello non parte da solo**;
- in attesa del primo campione, al posto del numero c'è un `.term-cursor`;
- alla scadenza compare `// subscription expired` e il bottone torna primario;
- su `monitor.error` il LED passa a `--state-fail` con `kind/code` in chiaro, ma le
  serie restano visibili: si è persa l'osservazione, non la storia.

### Lab — `/lab/:bundle_id`

Due riquadri affiancati, 40/60.

```text
┌─ runs ──────────────┐  ┌─ turn 4 · rev 12 ──────────────────────────────┐
│ ▸ run 019a…  3 turns│  │ › input       "research: otp supervision"      │
│   › turn 1  rev 4   │  │ › decision    route → :research (regex)        │
│   › turn 2  rev 7   │  │ › effects     1 inference · 0 external         │
│   ▪ turn 4  rev 12  │  │ ┌─ ● ● ● ────────────────────────────────────┐ │
│   ╎ gap rev 8–11    │  │ │ { "payload": { … } }                       │ │  .term-code
│ ▸ run 019b…  1 turn │  │ └────────────────────────────────────────────┘ │
└─────────────────────┘  └────────────────────────────────────────────────┘
// completeness: 9 of 12 revisions persisted — gaps are missing checkpoints,
// not missing history
```

I gap sono righe tratteggiate `╎` in `--fg-faint` dentro la timeline: visibili, non
nascosti e non riempiti.

---

### Errore — 404 e 500

Un URL sbagliato è un evento ordinario in uno strumento da operatore: i pannelli
si mettono nei preferiti, le connessioni si rimuovono. La pagina che lo riporta
deve sembrare parte dell'applicazione e offrire la via di ritorno, non leggersi
come un crash.

```text
┌─ exit 404 ─────────────────────── spectre studio ─┐
│ $ studio --status 404                             │
│ Not found                                         │
│ › nothing is served at this address               │
│ // una connessione rimossa, o un pannello il cui  │
│ // URL è cambiato, finisce qui                    │
│ [ ./dashboard ]  [ ./lab ]                        │
└───────────────────────────────────────────────────┘
```

La 500 dice dov'è il dettaglio (il log del server) e non lo stampa: una pagina
d'errore non è il posto dove far uscire gli interni.

## 7. Movimento e stati

| Situazione | Trattamento |
| --- | --- |
| Hover su card | `translateY(-2px)`, bordo → `--line-strong`, primo puntino acceso, 180 ms |
| Hover su bottone | Fondo → `--surface-bar`, bordo → `--fg-dim`, 160 ms |
| Bottone primario in hover | Si **svuota**: fondo trasparente, testo `--fg-strong` |
| Caricamento | `.term-cursor` al posto del valore. Nessuno spinner, nessuno skeleton grigio |
| Arrivo di un dato live | Nessuna animazione sul numero. Solo lo sparkline avanza |
| Flash | Entra da −0.6rem con fade, 200 ms |
| LiveView disconnessa | Flash fisso "connection lost" come nel blog, con `phx-disconnected` |
| Vuoto | Riga `// …` seguita da un `$ ` con l'azione suggerita |
| Errore | Parola + glifo + codice tecnico in `.term-code`, mai solo un colore |
| `prefers-reduced-motion` | Sospende cursore, pulsazione del LED e sollevamento delle card |

---

## 8. Accessibilità

- Contrasto: `--fg` su `--surface` e `--fg-dim` su `--surface-bar` restano sopra 4.5:1
  nei due temi. `--fg-faint` è riservato a glifi decorativi e timestamp, mai a testo
  che porta significato da solo.
- Ogni stato ha parola + glifo oltre al colore.
- Tabelle con `th` veri e `scope`; le liste chiave/valore usano `dl` quando sono
  descrizioni.
- Rail e tab navigabili da tastiera, `aria-current="page"` sulla voce attiva.
- Il flusso eventi è `aria-live="polite"` ma limitato: annuncia solo errori e cambi di
  stato, non ogni campione.
- Il toggle del tema espone `aria-pressed`.
- Skip link `.skip-link` verso `#main-content`, identico al blog.

---

## 9. Cosa fare, in pratica

1. Rimuovere daisyUI da `mix.exs` e dal blocco `@plugin` di `assets/css/app.css`.
2. Copiare da `../ex_blog/assets/css/app.css`: token, temi, `html`/`body`, selezione,
   scrollbar, focus, `.site-shell`, `.skip-link`, utility di tono, e tutte le `.term-*`
   della tabella §4, più il blocco di syntax highlighting. Scartare `.article-prose`,
   CookieConsent e `.term-media`.
3. Aggiungere in coda le otto estensioni §5 e il token `--state-wait`.
4. Portare i nove componenti funzione in `core_components.ex`, eliminando i residui daisyUI.
5. Scrivere `studio_components.ex` con: `led/1`, `metric/1`, `spark/1`, `gauge/1`,
   `rail/1`, `tabs/1`, `stream/1`, `diff_row/1`, `scope_badge/1`.
6. Shell in `layouts.ex` + `layouts/root.html.heex`: header sticky, brand
   `spectre@studio:~$` con puntini e cursore, rail, footer `exit status 0`,
   `flash_group/1`, `theme_toggle/1`.
7. `assets/js/app.js`: gestione tema come nel blog (chiave `spectre-studio:theme`,
   dark di default), `topbar`, hook colocati per sparkline e autoscroll.

## 10. Checklist di conformità

Da verificare su ogni schermata prima di considerarla finita.

- [ ] Nessun valore cromatico letterale nel markup: solo token e utility di tono.
- [ ] Nessun font diverso dal mono.
- [ ] Ogni riquadro è un `.term-window` con la sua barra.
- [ ] Ogni stato colorato ha parola e glifo.
- [ ] Ogni numero che cambia è `tabular-nums`.
- [ ] Nessun elemento non autorizzato presente nel DOM, nemmeno disabilitato.
- [ ] Stato vuoto, di caricamento ed errore progettati, non lasciati al default.
- [ ] Focus visibile su ogni elemento interattivo.
- [ ] Le lacune nei dati sono visibili come lacune, mai interpolate.
- [ ] La pagina regge il tema chiaro senza correzioni ad hoc.
- [ ] Anche le pagine che si vedono di rado — errori, notifiche, stati di
      caricamento — indossano la shell: sono quelle in cui una svista si nota di più.
