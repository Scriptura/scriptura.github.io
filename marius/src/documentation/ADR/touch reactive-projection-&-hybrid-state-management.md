# Document d'Arbitrage : Projection Réactive & Gestion d'État Hybride

## 1. Option C : Pattern "Draft vs. Committed"

### Problématique

Dans un système de **Projection Réactive** avec un tick de 500ms, le risque de "clobbering" (écrasement du DOM en cours d'édition par une projection asynchrone) est critique. L'utilisation de `contenteditable` ou de formulaires complexes nécessite une réconciliation d'état.

### Décision Architecturale

Rejet de l'Option B (Morphing/Idiomorph) au profit de l'**Option C** : une gestion explicite des états de synchronisation via des attributs de données natifs.

### Mécanique du Flux (State Machine)

L'interface utilisateur est traitée comme un tampon de mémoire vive (Draft) distinct de la source de vérité (Committed).

1.  **État : Pristine (Initial)**
    - L'élément affiche la donnée projetée par le pipeline Rust/Maud.
2.  **État : Dirty (Focus/Input)**
    - Action : `onFocus` ou `onInput`.
    - Mutation : L'élément reçoit l'attribut `data-state="dirty"`.
    - Invariant : HTMX est instruit d'ignorer tout signal de `swap` provenant du serveur pour cet ID spécifique tant que cet attribut est présent.
3.  **État : Sync (Blur)**
    - Action : `onBlur`.
    - Mutation : Envoi de la commande SQL brute via l'endpoint de mutation. L'élément passe en `data-state="sync"`.
4.  **État : Committed (Success)**
    - Action : Réception HTTP 200.
    - Mutation : Suppression de l'attribut `data-state`.
    - Résultat : Le prochain cycle du **Dispatcher** vient rafraîchir le nœud avec la valeur officielle calculée par PostgreSQL.

### Avantages DOD/AOT

- **Zéro Indirection** : Pas de moteur de "diffing" complexe (DOM-diffing) consommant du CPU client.
- **Déterminisme** : Le serveur reste un pur moteur de projection ; il ne tente pas de deviner l'état du client.
- **Alignement ADR-001** : Respecte l'isolation de l'interface d'écriture.

---

## 2. Dispatcher Adaptatif (Dynamic Tick)

### Principe de "Smoothing"

Le Dispatcher agit comme un **Filtre Passe-Bas** pour la charge système. Son rôle est de lisser l'amplification d'écriture en regroupant les mutations au sein d'une fenêtre temporelle (le `tick`).

### Logique d'Asservissement

Le délai de vidage du Collector (`HashSet`) n'est plus une constante, mais une variable ajustée en temps réel selon la télémétrie du système.

#### Invariants de Modulation :

- **Charge Faible (Mode Réactif)** :
  - Condition : `HashSet::len() < Seuil_Bas` ET `CPU_Usage < 30%`.
  - Action : Réduction du tick à **100ms**.
  - Objectif : Perception "Soft Real-Time".
- **Charge Élevée (Mode Batch)** :
  - Condition : `HashSet::len() > Seuil_Haut` OU `CPU_Usage > 70%`.
  - Action : Augmentation du tick jusqu'à **2000ms**.
  - Objectif : Maximiser le débit (Throughput) et l'efficacité du cache d'instruction CPU en traitant des lots de données contigus.

### Analyse CPU/Mémoire

- **Allocation Minimale** : Le passage d'un tick court à un tick long permet de saturer les vecteurs SIMD lors du rendu Maud en traitant plus de données par itération.
- **Backpressure** : Le système protège activement PostgreSQL contre une saturation des connexions (I/O) en forçant un regroupement des requêtes `SELECT` de projection.

---

## 3. Synthèse des Impacts

| Composant       | Stratégie               | Bénéfice Architectural                              |
| :-------------- | :---------------------- | :-------------------------------------------------- |
| **Frontend**    | Vanilla JS / Data-State | Suppression du coût de morphing, focus préservé.    |
| **Worker Rust** | PID Controller (Tick)   | Protection contre l'amplification d'écriture (DOD). |
| **PostgreSQL**  | Listen/Notify           | Découplage total Write Path / Read Path.            |
| **Rendu**       | AOT (Maud)              | CPU libéré pour la gestion des flux réseaux.        |

**Conclusion :** Ce design transforme le serveur en un moteur de flux asynchrone où la latence est un paramètre géré, et non une contrainte subie. L'utilisateur bénéficie d'une interface instantanée (via le mode Draft) tandis que l'infrastructure reste stable et froide (via le Dispatcher adaptatif).
