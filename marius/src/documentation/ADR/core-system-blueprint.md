# Blueprint Architectural : Moteur de Rendu Réactif "Marius"

## 1. Philosophie & Paradigme (Le "Pourquoi")

Ce système rejette l'approche classique (JIT, SPA, intermédiation par API JSON) au profit d'une architecture **Data-Oriented Design (DOD)** et **Ahead-Of-Time (AOT)**.

- **La donnée est le cache :** Le serveur n'est pas un médiateur interactif, c'est un moteur de projection. Il transforme un état SQL en un artéfact binaire (HTML).
- **Déterminisme absolu :** Le temps de réponse en lecture doit être plat (soft real-time), sans Garbage Collection, limité uniquement par les I/O réseau.
- **Zéro Indirection :** Suppression des couches de mapping (ORM) et de sérialisation. Les octets transitent de la base de données vers la mémoire contiguë (structs Rust) puis directement vers le buffer de sortie réseau.

## 2. La Stack Technique (Le "Quoi")

Chaque outil est sélectionné pour son alignement avec la réduction de l'empreinte mémoire, le contrôle CPU et le typage fort.

- **Socle Système : Rust (LLVM)**. Garantit l'absence de Garbage Collector, la sécurité mémoire au moment de la compilation, et un footprint RAM minimal (~20 Mo).
- **Runtime Asynchrone : Tokio**. Ordonnanceur multi-thread (Work-Stealing) pour maximiser l'usage CPU lors des I/O non-bloquants, sans l'overhead des threads OS bloquants.
- **Réseau & Routing : Axum + Tower**. Serveur HTTP exploitant le typage statique de Rust pour l'extraction de données (zéro parsing manuel). Fournit les primitives système (compression Zstd/Gzip, streaming de fichiers).
- **Moteur de Projection : Maud**. Macro Rust compilant les templates HTML directement en code machine. Zéro parsing au runtime.
- **Protocole Client : HTMX**. Traite le navigateur comme un terminal d'affichage. Échange des fragments d'état (HTML) plutôt que des données (JSON), éliminant l'état applicatif côté client.
- **Driver Data : SQLx**. Validation des requêtes SQL contre le schéma de la base de données _au moment de la compilation_. Mapping direct en structures mémoire.
- **Source de Vérité : PostgreSQL**. Centralise les invariants métier. Pilote le système via des triggers et le protocole natif `LISTEN/NOTIFY`.
- **Pipeline Assets : `build.rs` + `minify-js`**. Intégration AOT. Les assets (CSS/JS) sont minifiés, hashés et figés avant la compilation du binaire pour un cache navigateur immuable.

## 3. Topologie du Pipeline (Le "Comment")

L'architecture sépare strictement le chemin de lecture (Read Path, critique en latence) du chemin d'écriture (Write Path, critique en débit).

### A. Le Chemin de Lecture (Read Path - O(1))

1.  **Requête HTTP** entrante gérée par Tokio/Axum.
2.  **Passthrough :** Axum sert l'artéfact projeté (fichier statique ou buffer RAM) via `sendfile(2)`.
3.  **Résultat :** Latence microseconde (~100µs), coût CPU quasi nul.

### B. Le Chemin de Mutation (Write Path & Projection Réactive)

La résolution du problème d'amplification d'écriture (Write Amplification) est gérée par un pattern **Collector/Dispatcher**.

1.  **Mutation :** Une transaction SQL est validée (ex: `CALL content.publish_document()`).
2.  **Signal :** PostgreSQL émet un événement `pg_notify` contenant l'ID de l'entité.
3.  **Collector (Dédoublonnement) :** Un worker Tokio intercepte le signal et place l'ID dans un `HashSet` en mémoire. Plusieurs mutations rapides sur le même ID sont écrasées (DOD).
4.  **Dispatcher (Batching) :** Selon un invariant temporel (ex: `tick` de 500ms) ou volumétrique (ex: `len() == 100`), le `HashSet` est vidé (`flush`).
5.  **Projection Parallèle :** Les $N$ entités uniques sont extraites via SQLx en lot, puis projetées simultanément en HTML via Maud sur tous les cœurs CPU (via Rayon/Tokio). L'artéfact cible est mis à jour.

## 4. Invariants Hybrides (Comportement Client)

Bien que l'état global soit géré par le serveur, les micro-interactions locales (sans persistance requise) sont traitées en Just-In-Time (JIT) côté client.

- **Règle :** Utilisation de Vanilla JS (ou outils légers) greffés sur des attributs natifs (ex: `aria-expanded`, `<details>`).
- **Intégration HTMX :** Les scripts réactifs s'accrochent au hook `htmx.onLoad` pour garantir l'application du comportement aux fragments du DOM fraîchement injectés par le pipeline AOT.

---

Document rédigé le 25 mars 2026.
