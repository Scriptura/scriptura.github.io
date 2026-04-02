# 📂 Document d'Arbitrage : Couche de Transport & Présentation

## 🚀 1. Le Choix Stratégique : HTMX (Hypermedia-First)

Le projet Marius adopte **HTMX** comme moteur de synchronisation entre le serveur (Rust) et le client (Navigateur). Contrairement aux approches modernes qui traitent le Web comme une plateforme d'exécution d'applications (JS), nous traitons le Web comme un **système de distribution de documents réactifs**.

### L'Hypermedia comme format de message

Plutôt que d'envoyer de la donnée brute (JSON) qui nécessite une réinterprétation côté client, nous envoyons des **Messages Hypermedia** (Fragments HTML).

- **État Auto-Descriptif** : Le message contient la donnée ET les contrôles (boutons, liens, déclencheurs) pour la modifier.
- **Zéro Indirection** : Le pipeline Rust/Maud projette l'état final. HTMX ne fait que "déposer" cet état dans le DOM. Le CPU client est économisé au profit du rendu natif.

---

## 🏗️ 2. Pourquoi rejeter les Web Components ? (Le Piège du Purisme)

Bien que les Web Components soient natifs, leur utilisation comme socle de transport pour Marius introduirait une complexité accidentelle.

- **Absence de Couche de Transport** : Un Web Component est une coquille vide. Pour le mettre à jour, il faut écrire du code JS personnalisé (`fetch`, `parse`, `DOM update`). HTMX est l'automate qui gère ce cycle gratuitement.
- **Boilerplate vs Déclaratif** : Là où HTMX nécessite un attribut (`hx-get`), les Web Components imposent une définition de classe, une gestion du Shadow DOM et un cycle de vie complexe.
- **Incompatibilité AOT** : Notre rendu est effectué **Ahead-Of-Time** côté serveur via Maud. Encapsuler ce rendu dans un Web Component forcerait une double gestion des templates (un en Rust, un en JS pour la partie réactive).

---

## 📉 3. Pourquoi rejeter les Frameworks JS (React, Vue, Next.js) ?

L'utilisation d'une SPA (Single Page Application) est structurellement incompatible avec les invariants ECS/DOD de Marius.

1.  **L'Indirection de Donnée** : Passer par un bridge JSON crée un "O/R Mapping" côté frontend. Cela consomme des cycles CPU pour transformer des objets en éléments d'UI, ce qui brise notre objectif de performance $O(1)$.
2.  **Rupture du Pipeline AOT** : Les frameworks JS imposent un rendu **Just-In-Time (JIT)** ou une "hydratation" coûteuse. Marius vise un serveur "froid" qui ne fait que pousser des octets pré-calculés.
3.  **Complexité de l'État** : Maintenir un état complexe en JS parallèlement à l'état PostgreSQL crée des désynchronisations chroniques. Avec HTMX, l'unique source de vérité reste la base de données.

---

## 🛡️ 4. Analyse de l'Emprise et de la Dette Technique

L'arbitrage en faveur de HTMX minimise le risque à long terme.

- **Dette "Douce" (HTMX)** : L'emprise se limite à des attributs HTML standards (`hx-*`). Si HTMX disparaît, la logique serveur reste intacte. Un script de 100 lignes pourrait remplacer la bibliothèque en interceptant les attributs.
- **Dette "Dure" (Frameworks)** : Adopter un framework JS lie le projet à un écosystème, des gestionnaires de paquets (NPM), et des cycles de dépréciation rapides. Une migration signifierait réécrire 100% de la couche de présentation.

---

## 📊 5. Tableau Comparatif des Solutions

| Critère             | **HTMX**             | **Web Components** | **Frameworks JS**      |
| :------------------ | :------------------- | :----------------- | :--------------------- |
| **Philosophie**     | Hypermedia (REST)    | Composants natifs  | Application-centric    |
| **Logic Layout**    | Serveur (Rust/Maud)  | Mixte (JS/HTML)    | Client (JS)            |
| **Transport**       | Automatisé           | Manuel (JS fetch)  | JSON + Store           |
| **Coût CPU Client** | Très faible          | Faible             | Élevé                  |
| **Pérennité**       | Maximale (Standards) | Élevée (Natifs)    | Faible (Cycles courts) |

---

## ✅ 6. Conclusion de l'Arbitrage

Le stack **HTMX + Alpine.js (pour l'Option C)** est l'option la plus optimale pour Marius. Elle permet de maintenir un **Pipeline de Projection** pur de la base de données à l'écran, sans sacrifier l'interactivité moderne (temps réel, édition en place) et en garantissant une empreinte mémoire minimale côté serveur.
