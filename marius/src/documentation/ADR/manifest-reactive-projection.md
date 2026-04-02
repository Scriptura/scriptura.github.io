# Le Manifeste de la Projection Réactive

## Architecture Data-First & Rendu AOT

### 1. Vision Stratégique

Le serveur web n'est plus un médiateur interactif, mais un **Système de Projection**. Il transforme de manière déterministe un flux de mutations de données (PostgreSQL) en artéfacts statiques ou semi-statiques (HTML via Maud), éliminant le besoin de caches intermédiaires (Redis, Memcached). L'artéfact généré _est_ l'état optimal de lecture.

### 2. Résolution des Problèmes Classiques

- **Invalidation du Cache :** Élimination de la logique temporelle (TTL). L'artéfact est réécrit uniquement lorsque la source de vérité le commande.
- **Indirection de Transformation :** Suppression du mapping objet-relationnel (ORM) et de la sérialisation (JSON). Le pipeline transfère les octets directement du driver SQL aux buffers d'écriture HTML.
- **Gaspillage CPU :** Le rendu est calculé une seule fois à l'écriture (AOT), libérant le CPU pour le transport réseau (I/O) lors de la lecture.

### 3. Invariants Structurels

L'architecture repose sur trois piliers inaltérables :

1. **Source de Vérité (PostgreSQL) :** Centralise la logique métier et l'état. Seule la base de données qualifie une mutation.
2. **Canal de Transport (LISTEN/NOTIFY) :** Protocole asynchrone natif poussant les signaux de mutation vers le système applicatif.
3. **Transformateur Pur (Rust + Maud) :** Un pipeline AOT (Ahead-of-Time) sans état interne, traduisant le modèle de données (`struct`) en mémoire contiguë (DOM/HTML).

### 4. Limite Physiologique : L'Amplification d'Écriture

**Le Risque :** Dans un système réactif pur, une mise à jour massive en base de données (ex: 10 000 lignes modifiées via une procédure stockée) déclenche une avalanche de notifications. Traiter chaque signal individuellement sature le pipeline de rendu et les I/O disque/réseau, provoquant un goulot d'étranglement CPU.

### 5. La Solution DOD : Le Modèle Collector / Dispatch

Pour protéger le transformateur, on interpose un système de regroupement (Batching) qui réduit l'entropie du flux d'événements.

- **Le Collector (Dédoublonnement en O(1)) :**
  Les signaux entrants sont stockés dans une structure contiguë avec contrainte d'unicité (un `HashSet` Rust). Si un même ID est modifié 50 fois dans un court intervalle, il n'est conservé qu'une fois dans le layout mémoire.
- **Le Dispatcher (Tick & Seuil) :**
  Le vidage du Collector (`flush`) est régi par deux invariants stricts pour lisser la charge (Smoothing) :
  - _Volumétrique :_ Déclenchement si la capacité maximale est atteinte (ex: 100 entités).
  - _Temporel :_ Déclenchement périodique forcé (ex: toutes les 500ms).
- **Parallélisme de Rendu :**
  Lors du `flush`, la liste dédoublonnée d'IDs est distribuée sur l'ensemble des cœurs CPU disponibles (via un ordonnanceur comme _Rayon_ ou les workers _Tokio_). La projection de $N$ artéfacts s'exécute en simultané, garantissant une latence de mise à jour stable.

### 6. Pipeline Mécanique Global

Le cycle de vie complet d'une donnée suit ce flux directionnel strict :

1. **Mutation DB :** `UPDATE content.document` $\rightarrow$ Trigger SQL.
2. **Signal :** `pg_notify('updates', 'ID')`.
3. **Capture :** Écouteur asynchrone Rust $\rightarrow$ Injection dans le `HashSet`.
4. **Dispatch :** Seuil ou Tick atteint $\rightarrow$ Extraction des IDs uniques.
5. **Extraction Data :** Requêtes `SELECT` par lots (Batch SQL).
6. **Projection AOT :** Exécution des macros `Maud` (Multi-thread).
7. **Persistance :** Remplacement atomique de l'artéfact (Fichier / RAM).

---

Document rédigé le 25 mars 2026.
