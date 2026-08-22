# Piano di completamento — Spectre Studio

Stato del documento: piano operativo, revisione 2
Baseline verificata il 2026-08-22 sul checkout locale (`main`, commit `8f99704 init`)
Implementazione in corso su `feature/studio-foundation`

Spectre Studio è l'interfaccia LiveView che osserva, controlla e analizza uno o più
sistemi Spectre. Non contiene logica di Agent: usa **Pulse** come canale sicuro e
realtime, **Lab** come strumento di analisi offline, e le altre estensioni
(Ledger, Morph, cache semantica) tramite integrazioni dedicate.

Riferimento visivo: `ex_blog`, **solo per stile e UI**. Da lì si prendono linguaggio
visivo, token, vocabolario dei componenti e regole di composizione. Nessuna funzione,
nessun modulo di dominio e nessuna dipendenza del blog entra in Studio. La specifica
completa è in [`docs/UI.md`](docs/UI.md); questo piano la assume e non la ripete.

---

## Stato dell'implementazione

Aggiornato il 2026-08-22, branch `feature/studio-foundation`, nessun commit.

| Milestone | Stato | Note |
| --- | --- | --- |
| M0 — fondazione visiva | **fatto** | daisyUI rimosso; `assets/css/app.css` portato dal riferimento più le otto estensioni; `core_components.ex` + `studio_components.ex`; shell, rail, footer, toggle tema |
| M1 — client Pulse WSS | **fatto** | `Pulse.Socket` (Mint), `Pulse.Connection`, `Vault` cifrato, backoff, riconnessione, stati terminali |
| M2 — manifest e scope | **fatto** | `Manifest`, `Agent`, `Scopes`; azioni non autorizzate assenti dal DOM, scope negati mostrati |
| M3 — dashboard e monitoraggio | **fatto** | `AgentLive` con OTP + Work/Vigil, metriche, snapshot, lacune e ciclo enable/disable completo |
| M4 — messaggi | **fatto** | invio envelope validato lato Studio, receipt correlate |
| M5 — Lab | **parziale** | upload + verifica + timeline + diff funzionanti; il bridge remoto è specificato ma non implementato |
| M6 — Ledger/estensioni | **parziale** | bridge cache/Skill/Morph e pannelli Agent implementati; Ledger e Lab remoto ancora mancanti |
| M7 — sicurezza | **rivisto** | nessun login, per scelta esplicita: si lancia Studio e si è nella dashboard. Restano CSP, `noindex`, redazione dei token, vault cifrato, e l'ascolto legato a loopback |
| M8 — test e qualità | **fatto** | 98 test verdi, `FakePulse` completo, `credo --strict` pulito, formattato |

### Deviazioni dal piano, con motivo

1. **Studio non dipende da `spectre_pulse` per il protocollo.** Il piano
   prevedeva di riusare `Envelope` e `Codec.JSON`. Farlo significa compilare
   l'intero runtime Spectre dentro l'osservatore e legarlo alla *sua* versione:
   Studio non potrebbe più parlare con host su versioni diverse. Le frame sono
   piccole, versionate e stabili, quindi `SpectreStudio.Pulse.Frame` le parla
   direttamente. Spectre entra comunque come dipendenza, ma solo perché Lab lo
   richiede.
2. **L'indirizzo Agent viaggia in base64url**, non come lista di segmenti. Plug
   scarta il segmento vuoto di `spectre://`, quindi l'indirizzo tornava come
   `spectre:/acme/researcher`. La codifica lo mantiene esatto.
3. **Il socket non è linkato alla connessione.** Un guasto di trasporto deve
   degradare la connessione, non uccidere il processo che possiede manifest,
   sottoscrizioni e serie. Il socket monitora il proprio owner, quindi muore
   comunque quando la connessione se ne va.
4. **La vista Run/Turn di Lab è una timeline di revisioni.** Come anticipato in
   §0, il dettaglio di Input, decisione ed Effect vive nelle boundary receipt,
   che Ledger tiene fuori dal bundle. Il pannello lo dichiara e rimanda al
   bridge invece di simulare un dato che non ha.

### Pagine d'errore

`render_errors` usava `layout: false`: un 404 arrivava come testo nudo nel font
di default del browser, cioè l'unica schermata che fa sembrare rotto lo
strumento invece dell'URL. Ora 404 e 500 indossano la stessa shell e offrono la
via di ritorno. `/connections` è tornata a rispondere, così i link salvati alla
vecchia dashboard non finiscono lì.

### Bug trovato e corretto durante l'implementazione

Un host che invia subito dopo l'upgrade — Pulse manda il manifest appena
autentica — può far arrivare la prima frame nello stesso pacchetto del 101.
Quei byte venivano scartati silenziosamente perché il websocket non esisteva
ancora. Sintomo: connessione ferma in `:authenticating`, in modo intermittente.
Ora vengono messi da parte e decodificati subito dopo l'upgrade
(`lib/spectre_studio/pulse/socket.ex`).

### Estensioni aggiunte dopo la fondazione

- protocollo Pulse aggiornato al branch Work/Vigil: frame
  `agent.operations.monitor.*`, scope pair e cleanup condiviso;
- review per-Agent della cache semantica, con verifica/promozione esplicita;
- mount di nuove runtime Skill via definizione dichiarativa;
- proposta Morph governata, limitata a creazione + valutazione;
- gating delle rotte oltre che dei tab: un pannello senza scope non è
  raggiungibile nemmeno digitandone direttamente l'URL.

### Cosa manca per considerare Studio completo

- i consumer Ledger/Lab remoto del bridge e un host che li implementi;
- i pannelli Ledger che ne dipendono;
- verifica browser con Spectre Lens sulle rotte principali;
- `Dockerfile` e release.

---

## 0. Stato di partenza, verificato

`spectre_studio` è oggi uno **scaffold Phoenix 1.8 vuoto**. Non esiste ancora nulla del
concept.

| Area | Stato reale |
| --- | --- |
| LiveView | Nessuna. Solo `PageController` con `home.html.heex` generato |
| Router | Solo `get "/"`. Nessun `live_session`, nessuna autenticazione |
| Design | `assets/css/app.css` è quello generato, con **daisyUI** e temi oklch: opposto al linguaggio visivo di `ex_blog` |
| Dipendenze | Nessuna `spectre*`. Nessun client WebSocket. Nessuna persistenza |
| Supervisione | `Telemetry`, `DNSCluster`, `PubSub`, `Endpoint`. Nulla di Studio |
| Test | Solo i test generati di `error_html`/`page_controller` |

Quindi il lavoro è **costruzione completa**, non rifinitura.

### Cosa forniscono davvero le librerie satellite

Verificato leggendo il sorgente, non solo i README:

- **Pulse è il lato server**. `Spectre.Pulse.Phoenix` monta un `Phoenix.Socket.Transport`
  grezzo (non canali) sull'app che ospita gli Agent. Il modulo
  `Spectre.Pulse.Transports.WebSocket` dichiara esplicitamente: *"Pulse does not own
  connection processes"*. **Non esiste un client WSS in Pulse.**
  → Studio deve portare il proprio client WebSocket. È il primo pezzo mancante.
- **Il protocollo di connessione è già definito e stabile**
  (`lib/spectre/pulse/phoenix/frame.ex`, `docs/STUDIO_MONITORING.md`):
  `manifest`, `receipt`, `error`, `agent.runtime.monitor.{enable,enabled,disable,disabled,update,expired,error}`.
  Tutte le frame sono `{"pulse":"connection","version":1,"type":...}`.
- **Il manifest ha una forma nota**: `connection` (con `principal`, `granted_scopes`,
  `granted_profiles`, `status`, `connected_at`), `spec` (`transport`, `mode`, `profiles`,
  `scopes`), `agents` (lista di `AgentDescriptor.to_wire/1`: `address`, `display_name`,
  `protocol_versions`, `capabilities`, `metadata`).
- **Pulse impone due coppie di scope**: `agent.runtime.read/stream` per OTP e
  `agent.operations.read/stream` per Work/Vigil. Lab, Ledger, controllo,
  promozione cache, Skill e Morph restano **scope applicativi**: Studio li
  tratta come grant dichiarati nel manifest e l'host deve imporli di nuovo.
- **Lab non ha il concetto di "Run/Turn" pronto all'uso.** L'API pubblica è minima:
  `Spectre.Lab.load/2`, `load_receipts/2`, `diff/2`, più `Playback.revisions/fetch/completeness`
  e `ReceiptPlayback.sequences/by_kind`. La vista "Runs e Turns" del concept va
  **proiettata in Studio** da revisioni di checkpoint + catena di receipt.
- **Lab lavora offline su bundle**. Non parla con Pulse e non ha una sorgente remota.
  Serve un ponte: o upload di file, o un'operazione applicativa trasportata da Pulse.
- **Pulse come dipendenza è leggero**: la sua application avvia solo due registry,
  un DynamicSupervisor e `Fabric`. Si può includere per riusare `Envelope`, `Codec.JSON`,
  `Validator` senza dichiarare connessioni.

---

## 1. Architettura target

```text
                  browser (LiveView)
                          │
┌─────────────────────────┼──────────────────────────────────┐
│ Spectre Studio          │                                  │
│                         ▼                                  │
│   SpectreStudioWeb.*Live  ── PubSub ──┐                     │
│                                       │                     │
│   SpectreStudio.Pulse.Supervisor      │                     │
│     └── Connection (GenServer)  ──────┘                     │
│           └── Socket (Mint.WebSocket)                       │
│                                                             │
│   SpectreStudio.Lab.*   (Spectre.Lab in-process, offline)   │
│   SpectreStudio.Vault   (spec connessioni + segreti)        │
└───────────────────────────┬─────────────────────────────────┘
                            │ WSS + token
                            ▼
                    app host  →  Spectre.Pulse.Phoenix
                            ├── Agent A
                            ├── Agent B
                            └── Agent C
```

Regola invariante: **una LiveView non parla mai al socket**. Parla al processo
`Connection`, che possiede lo stato di connessione, il manifest, le sottoscrizioni e
i buffer, e fa broadcast su PubSub. Se una LiveView muore, `Connection` se ne accorge
via `Process.monitor` e disabilita le sue sottoscrizioni — stessa garanzia che Pulse dà
lato server, applicata lato Studio.

### Albero moduli

```text
lib/spectre_studio/
  application.ex             # + Vault, Pulse.Supervisor, Lab.Registry
  config.ex                  # config tipata, segreti fuori dalle proiezioni
  vault.ex                   # DETS: spec connessioni; token cifrati a riposo
  pulse/
    supervisor.ex            # DynamicSupervisor delle connessioni
    connection.ex            # API pubblica + GenServer proprietario dello stato
    connection/state.ex      # struct: manifest, agenti, scope, subs, buffer
    socket.ex                # Mint.WebSocket: handshake, frame, ping, backoff
    manifest.ex              # normalizzazione wire → struct Studio
    agent.ex                 # struct AgentDescriptor lato Studio
    scopes.ex                # can?/2, gating dichiarativo della UI
    monitor.ex               # request_id ↔ subscription_id, ring buffer campioni
    messaging.ex             # costruzione/invio envelope, correlazione receipt
    events.ex                # topic PubSub e broadcast tipizzati
  lab/
    library.ex               # bundle caricati, per operatore
    source.ex                # behaviour: :upload | :pulse_bridge
    projection.ex            # revisioni + receipt → view model Run/Turn
    diff.ex                  # wrapper su Spectre.Lab.diff/2
  ledger/client.ex           # opzionale, via bridge applicativo
lib/spectre_studio_web/
  components/
    core_components.ex       # design system terminale portato da ex_blog
    studio_components.ex     # widget di dominio Studio
    layouts.ex + layouts/root.html.heex
  live/
    connections_live.ex      # /connections (indice + form)
    connection_live/show.ex  # /connections/:id
    agent_live/show.ex       # /connections/:id/agents/:address
    agent_live/monitor.ex    # LiveComponent, ciclo enable/disable
    agent_live/messaging.ex  # LiveComponent, invio envelope
    lab_live/{index,run,diff}.ex
docs/
  STUDIO_BRIDGE.md           # contratto che l'app host implementa per Lab/Ledger
```

### Rotte

```text
/                                             ConnectionLive.Index  (la dashboard)
/connections                                  idem, per i vecchi link
/connections/new                              ConnectionLive.Form
/connections/:id                              ConnectionLive.Show
/connections/:id/edit                         ConnectionLive.Form
/connections/:id/agents/:address              AgentLive.Overview  (address in base64url)
/connections/:id/agents/:address/monitor      AgentLive.Monitor
/connections/:id/agents/:address/messages     AgentLive.Messages
/connections/:id/agents/:address/events       AgentLive.Events
/lab                                          LabLive.Index
/lab/:id                                      LabLive.Show
/lab/:id/diff/:other                          LabLive.Diff
```

Ogni tab di un Agent è una LiveView a sé, non un ramo dentro una sola. È questo
che rende onesto il ciclo del monitoraggio: la subscription vive esattamente
quanto il processo che possiede il pannello, quindi uscire dal tab chiude lo
stream senza contabilità, e nessun altro pannello paga il costo di un socket che
non sta usando.

Le liste che crescono sono `stream`: endpoint, log eventi, envelope inviate,
bundle, timeline. Il lavoro che può durare — verifica di un bundle, diff di due
catene — passa da `start_async`/`assign_async` e si dichiara in corso con
`<.async_result>` invece di bloccare la LiveView.

Tutte dentro un unico `live_session :studio`, così la navigazione tra pannelli
non ricrea il socket LiveView.

---

## 2. Milestone

Ordine pensato per avere qualcosa di visibile e verificabile presto: prima la pelle,
poi la connessione, poi il resto.

### M0 — Fondazione visiva (S/M)

Obiettivo: Studio deve **sembrare** ex_blog dal primo giorno — terminale monocromatico,
mono ovunque, densità alta — pur essendo un control center e non un blog.

La specifica normativa è [`docs/UI.md`](docs/UI.md): principi, token, scala tipografica,
componenti portati identici, otto estensioni nuove (`term-led`, `term-metric`,
`term-spark`, `term-gauge`, `term-rail`, `term-tabs`, `term-stream`, `term-diff`),
wireframe di ogni schermata, regole di movimento, accessibilità e checklist.

Lavoro di questa milestone, nell'ordine:

1. `mix.exs`: rimuovere `daisyui`; aggiungere `credo` e `dialyxir` `only: [:dev, :test]`.
2. `assets/css/app.css`: sostituire con il foglio del blog, tenendo token, temi,
   `.site-shell`, `.skip-link`, utility di tono, tutte le `.term-*` e il syntax
   highlighting. Scartare `.article-prose`, CookieConsent, `.term-media`.
3. Aggiungere in coda le estensioni Studio e il token `--state-wait`.
4. `core_components.ex`: portare `term_window/1`, `cursor/1`, `flash/1`, `button/1`,
   `input/1`, `header/1`, `table/1`, `list/1`, `icon/1`; eliminare i residui daisyUI.
5. `studio_components.ex`: `led/1`, `metric/1`, `spark/1`, `gauge/1`, `rail/1`,
   `tabs/1`, `stream/1`, `diff_row/1`, `scope_badge/1`.
6. `layouts.ex` + `layouts/root.html.heex`: shell con header sticky, brand
   `spectre@studio:~$`, rail sinistra, footer `exit status 0`, `flash_group/1`,
   `theme_toggle/1`. Nessun meta OG/SEO: Studio è `noindex`.
7. `assets/js/app.js`: tema (`spectre-studio:theme`, dark di default), `topbar`,
   hook colocati per sparkline e autoscroll dello stream.

Criterio di accettazione: la shell e una pagina di esempio superano la checklist §10 di
`docs/UI.md`; `mix assets.build` pulito; nessun riferimento a daisyUI nel repo; il tema
chiaro regge senza correzioni ad hoc.

### M1 — Client Pulse: connessione WSS (L)

Il pezzo tecnicamente più delicato, perché non esiste a monte.

1. Dipendenze: `{:mint_web_socket, "~> 1.0"}`, `{:castore, "~> 1.0"}`,
   `{:spectre_pulse, github: "elchemista/spectre_pulse", branch: "main"}`,
   `{:spectre, "~> 0.3.2"}`.
   *(Alternativa: `websockex`, già usato da `spectre_lens`. Preferisco Mint per controllo
   esplicito su header di autenticazione, opzioni TLS, ping e backpressure.)*
2. `SpectreStudio.Pulse.Socket`: GenServer che apre `wss://host/pulse/websocket?token=…`,
   gestisce upgrade, frame text/binary, `ping`/`pong`, chiusura, e riconnessione con
   backoff esponenziale + jitter. Verifica certificati con CAStore per default;
   `verify: :verify_none` solo se esplicitamente abilitato per un endpoint locale,
   e la UI lo segnala con un badge di rischio.
3. `SpectreStudio.Pulse.Connection`: GenServer che possiede il socket, decodifica le frame
   e mantiene lo stato. Distingue i due piani:
   - frame di **controllo** (`"pulse" => "connection"`): manifest, receipt, error, monitoring;
   - **envelope Pulse** ordinari, decodificati con `Spectre.Pulse.Codec.JSON`.
4. Macchina a stati esplicita e mostrata in UI:
   `:configured → :connecting → :authenticating → :manifest_pending → :ready → :degraded → :closed`.
   Ogni transizione è un evento PubSub e una riga nello stream eventi della connessione.
5. `SpectreStudio.Vault`: DETS in `priv/studio/` (path configurabile) con le spec di
   connessione; i token cifrati con `:crypto.crypto_one_time_aead` e una chiave derivata da
   `STUDIO_VAULT_KEY`. I token **non compaiono mai** nelle proiezioni verso LiveView,
   log o assign.
6. UI `/connections`: elenco a `.term-window`, LED di stato, host, ultimo errore,
   pulsanti Connect/Disconnect/Edit; form di creazione con url, token, etichetta,
   `verify_tls`, timeout.

Criterio di accettazione: dato un host Phoenix con `use Spectre.Pulse.Phoenix`, Studio
si connette, resta connesso, sopravvive al riavvio dell'host riconnettendosi da solo, e
mostra correttamente la disconnessione. Errori di autenticazione producono uno stato
terminale leggibile, non un loop di riconnessione.

### M2 — Manifest, capacità e permessi (M)

1. `Pulse.Manifest.normalize/1`: da wire a struct Studio, con default difensivi
   (mappe assenti, chiavi mancanti, atomi mai creati da input remoto).
2. `Pulse.Scopes`: `can?(connection, :monitor_stream)`, `:runtime_read`, `:message_send`,
   `:lab_read`, `:ledger_read`, `:control`. Mappa nome logico → scope del manifest.
   Gli scope oltre i due runtime sono **dichiarativi**: se il manifest non li elenca, la
   funzione corrispondente è nascosta, non semplicemente disabilitata.
3. Componente `<.scope_badge>` e `<.capability_list>`: mostrano ciò che è concesso e,
   in tooltip, lo scope esatto richiesto da ogni azione.
4. `/connections/:id`: intestazione con principal, peer, transport, profili concessi,
   `connected_at`; tabella degli Agent esposti con address, display name, capacità,
   versioni di protocollo.

Criterio di accettazione: due connessioni con grant diversi verso lo stesso host
mostrano set di azioni diversi. Nessun pulsante non autorizzato è presente nel DOM.

### M3 — Dashboard Agent e monitoraggio realtime (L)

Il cuore del concept.

1. `/connections/:id/agents/:address` con tab: **Overview**, **Live**, **Messaggi**,
   **Lab**, **Eventi**.
2. **Overview** — snapshot singolo via `agent.runtime.read`: identità, Subject attivo,
   `instance_ref`, `node`, `pid`, `alive`, campi processo, `truncated_fields`, `limits`.
   Nota onesta in UI: sono campi `Process.info/2` selezionati, non stato dell'Agent.
3. **Live** — ciclo esattamente come raccomandato da `docs/STUDIO_MONITORING.md`:
   - `enable` **solo** su azione esplicita dell'operatore, mai al mount;
   - `request_id` generato da Studio, `subscription_id` **sempre** dal server;
   - routing degli update per `subscription_id`;
   - `disable` su chiusura pannello, cambio tab, `terminate/2`, navigazione;
   - `Connection` monitora il pid della LiveView e disabilita se muore;
   - perdita socket ⇒ tutte le subscription di quella connessione sono terminali,
     e la UI chiede un re-enable esplicito, senza tentare di riprendere id vecchi.
4. Controlli esposti: `interval_ms` (250–60000, default 1000), `duration_ms`, selezione
   campi dal vocabolario sicuro. La UI **non** offre campi fuori vocabolario.
5. Visualizzazione: `.term-metric` per memoria / mailbox / reductions / status,
   `.term-spark` con ring buffer di 120 campioni tenuto nel processo `Connection`
   (così due schede sullo stesso Agent condividono la serie e non moltiplicano il traffico).
6. Gestione onesta delle lacune: `dropped_updates > 0` e i salti di `sequence` sono
   marcati nello sparkline come **lacune di osservazione**, mai interpolati.
   `monitor.error` mostra `kind`/`code` e lascia il pannello aperto con stato degradato;
   `monitor.expired` propone il rinnovo.

Criterio di accettazione: aprendo il tab Live parte esattamente una subscription;
chiudendo la scheda del browser, l'host non ha subscription residue (verificabile con
`Spectre.Pulse.monitoring_subscriptions/1`); un riavvio dell'host produce
`monitor.error` gestito, non un crash della LiveView.

### M4 — Messaggi verso gli Agent (M)

1. `Pulse.Messaging.send/3`: costruisce l'envelope con `Spectre.Pulse.Envelope.new/2`
   (validazione lato Studio prima dell'invio), `act` tra `:inform | :query | :request`,
   `payload.type` + `payload.data` JSON, `metadata` opzionale.
2. Correlazione: `message_id` → receipt; timeout configurabile; le risposte in arrivo
   correlate via `relates_to` appaiono nel thread della richiesta.
3. UI: editor JSON con validazione live, selettore `act`, contatto destinatario preso
   dal manifest, storico invii per Agent con receipt (`status`, `via`, `route_id`,
   `accepted_at`) e ricevute d'errore (`kind`, `outcome`, `code`).
4. Gating: visibile solo con lo scope di messaggistica concesso.
5. Guardrail: conferma esplicita per `act: :request` verso Agent marcati come produttivi
   nel manifest (`metadata`), perché è l'unico canale che può innescare effetti reali.

Criterio di accettazione: un envelope malformato è rifiutato da Studio prima della rete,
con l'errore del `Validator` mostrato in chiaro; un envelope valido produce un receipt
visibile e correlato.

### M5 — Lab: Runs, Turns, playback e diff (L)

Qui il concept chiede più di quanto Lab esponga oggi. Il piano lo dice apertamente e
costruisce la proiezione in Studio.

1. Dipendenze: `{:spectre_ledger, github: …}`, `{:spectre_lab, github: …}`.
   **Nota**: Lab si installa `only: [:dev, :test]` nel suo README. Studio è uno strumento
   operativo e ha bisogno di Lab anche in `:prod`. Va incluso in tutti gli ambienti,
   documentando il confine di sicurezza qui sotto.
2. **Sicurezza del bundle, non negoziabile.** Lab dichiara Bundle v1 come artefatto
   *fidato/locale*: la decodifica Foundation può caricare un modulo esistente nominato
   dal checkpoint. Quindi:
   - i bundle caricati sono trattati come input privilegiato;
   - upload consentito solo a operatore autenticato, con limite di dimensione;
   - banner permanente nel pannello Lab che dichiara il confine;
   - `docs/STUDIO_BRIDGE.md` ripete il vincolo per chi integra.
3. `Lab.Source`: due implementazioni.
   - `:upload` — file dall'operatore. È la v1, e basta a rendere il pannello utile.
   - `:pulse_bridge` — l'app host espone un'operazione applicativa (es. payload
     `studio.ledger.bundle.export`) trasportata da Pulse come envelope ordinario.
     Pulse **non** implementa `lab.playback`/`lab.diff`: trasporta soltanto.
4. `Lab.Projection`: da `Playback.revisions/1` + `Playback.fetch/2` +
   `ReceiptPlayback.sequences/1` + `by_kind/2` costruisce il view model
   **Run → Turn → Input / decisione / Effect / risultato**, seguendo `correlation` e
   `causation` dalle receipt. Le revisioni assenti sono rese come **gap espliciti**:
   Spectre può coalescere le scritture, quindi un buco non è storia perduta ma
   assenza di checkpoint persistiti. La UI non deve mai suggerire il contrario.
5. `/lab/:bundle_id`: timeline verticale dei Turn in `.term-window`, con dettaglio a
   destra (payload in `.term-code` con highlight), catena di receipt, `completeness`
   e report di verifica del bundle in evidenza.
6. `/lab/diff`: `Spectre.Lab.diff/2` tra due playback dello stesso stream, con
   evidenziazione della prima revisione divergente — la risposta a *"dove è cambiata la
   decisione"*.

Criterio di accettazione: caricati due bundle dello stesso stream, Studio mostra Run e
Turn navigabili, la prima divergenza, e dichiara esplicitamente gap e limiti di
completezza.

### M6 — Ledger ed estensioni (M)

1. `docs/STUDIO_BRIDGE.md`: contratto minimo che l'app host implementa per sbloccare i
   pannelli non runtime. Tipi di payload proposti, tutti applicativi e trasportati da Pulse:
   `studio.ledger.head`, `studio.ledger.entries`, `studio.ledger.inference_usage`,
   `studio.ledger.bundle.export`, `studio.agent.subjects`.
2. Pannello Ledger per Agent: head, verifica catena, uso di inferenza e token
   (che appartengono a Ledger, **non** al monitoraggio runtime: il documento Pulse è
   esplicito su questa separazione).
3. Rilevamento capacità: se il manifest non annuncia il profilo `spectre.studio/1` o
   l'host non risponde al bridge, il pannello resta chiuso con una spiegazione
   azionabile ("l'host non espone questa operazione"), non un errore generico.

### M7 — Sicurezza, senza autenticazione (M)

Decisione: **Studio non ha login**. È uno strumento da operatore che si lancia e
apre subito la dashboard. Il confine di accesso non è una password dentro
l'applicazione, è l'indirizzo su cui ascolta.

1. Ascolto su loopback per default, in sviluppo e in produzione
   (`STUDIO_BIND_IP`). Chi vuole raggiungerlo da altrove usa un tunnel SSH o
   mette davanti un proxy che autentica. Questo va detto nel README, non
   lasciato implicito.
2. `SpectreStudio.Config`: configurazione tipata, la chiave del vault caricata
   solo al boot ed **esclusa dalla proiezione pubblica**, accesso esplicito via
   `fetch_secret!/1`.
3. Token delle connessioni sigillati AES-256-GCM a riposo; senza chiave Studio
   rifiuta di scriverli invece di metterli in chiaro.
4. Header di sicurezza, CSP, `robots: noindex`.
5. Redazione: nessun token o credenziale nei log, nei flash o negli assign.

### M8 — Test, qualità, distribuzione (M)

1. `test/support/fake_pulse.ex`: server Bandit di test che monta un WebSocket parlante
   protocollo Pulse — manifest, receipt, error, e il ciclo completo di monitoring con
   sequenze, `dropped_updates`, expiry ed errore. È l'infrastruttura che rende testabili
   M1–M4 senza un'app Spectre reale.
2. Test LiveView per: gating degli scope, ciclo enable/disable con cleanup su crash,
   riconnessione, rendering delle lacune di osservazione, validazione envelope.
3. `mix precommit` esteso: `compile --warnings-as-errors`, `deps.unlock --unused`,
   `format`, `credo --strict`, `test`.
4. Verifica browser con **Spectre Lens** sulle rotte principali: titolo, gerarchia
   semantica, form, stati responsive, e la checklist §10 di `docs/UI.md`.
   `mix spectre.lens.doctor` prima della verifica.
5. `Dockerfile` + release.

---

## 3. Decisioni prese, con motivazione

Sono scelte fatte per non bloccare il lavoro. Ognuna è reversibile.

| Decisione | Scelta | Perché |
| --- | --- | --- |
| Client WebSocket | `mint_web_socket` | Controllo esplicito su header di auth, TLS, ping, backpressure. `websockex` (usato da `spectre_lens`) resta l'alternativa se si preferisce l'omogeneità con l'ecosistema |
| Persistenza | DETS + segreti cifrati | Studio non ha entità relazionali. Ecto/SQLite sarebbe peso senza ritorno alla v1 |
| Autenticazione | Nessuna | Scelta dell'utente: Studio si apre sulla dashboard. Il confine è l'indirizzo di ascolto, loopback per default |
| Sorgente bundle Lab | Upload alla v1, bridge a seguire | L'upload rende Lab utile subito senza richiedere modifiche all'app host |
| Ambiente di Lab | Incluso anche in `:prod` | Studio è uno strumento operativo; il confine di sicurezza è documentato, non aggirato |
| daisyUI | Rimosso | Incompatibile con il linguaggio visivo di riferimento. Coesistere significherebbe due sistemi di design |

---

## 4. Rischi e limiti da dichiarare in UI

Non sono note a margine: se Studio li nasconde, mente all'operatore.

1. **Il monitoraggio runtime non è la storia dell'Agent.** Sono campi `Process.info/2`
   campionati. Niente mailbox, dizionario di processo, stato GenServer, memoria
   dell'Agent, token o contenuti di prompt.
2. **I gap di sequenza sono lacune di osservazione**, non eventi di business mancanti.
3. **Le revisioni assenti in Lab non sono storia perduta.** Spectre coalesce le
   scritture di checkpoint; Lab non rivendica replay deterministico né riproduzione
   degli effetti esterni.
4. **I bundle sono artefatti fidati.** Il pannello Lab lo dichiara sempre.
5. **Gli scope oltre i due runtime sono applicativi.** Se l'host li concede senza
   imporli, la UI mostra ciò che è dichiarato: il confine reale resta dell'host.
6. **Le subscription non sono riprendibili** dopo la perdita del socket. Il re-enable
   è sempre esplicito.

## 5. Dipendenze esterne al lavoro di Studio

- Un'app host con Pulse configurato (`mode: :listen`, `transport: :websocket`,
  scope `agent.runtime.read` e `agent.runtime.stream`) per collaudare M1–M4.
  Per lo sviluppo isolato basta `test/support/fake_pulse.ex`.
- Per M5, almeno un bundle Ledger reale esportato da un'esecuzione vera.
- Per M6, l'app host deve implementare `docs/STUDIO_BRIDGE.md`. Finché non lo fa, i
  pannelli Ledger restano chiusi e lo dichiarano.

## 6. Sequenza consigliata

```text
M0 ─ pelle           →  visibile subito, sblocca ogni pannello successivo
M1 ─ connessione     →  il pezzo mancante a monte, il più rischioso: farlo presto
M2 ─ manifest/scope  →  piccolo, ma governa tutta la UI seguente
M3 ─ agent + live    →  il cuore del concept
M8a─ fake_pulse      →  anticipare: rende M1–M3 verificabili senza host reale
M4 ─ messaggi
M5 ─ Lab
M7 ─ sicurezza        →  loopback per default; nessun login
M6 ─ Ledger/bridge
M8b─ test, Lens, release
```
