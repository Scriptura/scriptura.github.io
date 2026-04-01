# 📝 Document d'Architecture : Rejet de Zig au Profit de Rust pour le Moteur de Projection AOT

Le présent document détaille l'argumentaire technique justifiant le choix de Rust face à Zig pour l'implémentation du moteur de projection réactive.

Bien que Zig offre un contrôle absolu sur le layout mémoire et s'aligne parfaitement avec les principes du Data-Oriented Design (DOD), les invariants structurels du système requièrent des garanties de concurrence et des capacités de métaprogrammation (AOT) que l'écosystème Rust sécurise de manière native.

---

## 🚦 1. Maturité de l'Ordonnancement Asynchrone (I/O Concurrency)

Le pipeline de lecture et le mécanisme de signalisation imposent une gestion massive d'entrées/sorties non-bloquantes.

- **Le besoin système :** Le moteur maintient des connexions persistantes pour écouter les signaux `LISTEN/NOTIFY` de PostgreSQL tout en servant un flux continu de requêtes HTTP entrantes avec un coût CPU quasi nul en attente.
- **La solution Rust (Tokio) :** Rust dispose d'un ordonnanceur multi-thread par _Work-Stealing_ mature (Tokio). Ce runtime répartit dynamiquement les tâches asynchrones sur les cœurs disponibles, maximisant l'usage CPU lors des I/O sans subir l'overhead des threads de l'OS.
- **La limite de Zig :** La gestion de l'asynchronisme dans Zig a connu d'importantes refontes architecturales. Implémenter un serveur HTTP hautement concurrent et un écouteur de base de données asynchrone nécessiterait soit de s'appuyer sur des bibliothèques C externes (epoll/kqueue bruts, libuv), soit de développer un _Event Loop_ sur mesure, introduisant un risque opérationnel sur une couche critique du système.

## 🛡️ 2. Garanties de Concurrence sur le Dispatcher (Data Races)

La résolution de l'amplification d'écriture repose sur un pattern Collector/Dispatcher qui mute un état partagé en mémoire.

- **Le besoin système :** Un _Collector_ intercepte les signaux et dédoublonne les identifiants dans une structure contiguë (`HashSet`). Lors du _flush_ temporel ou volumétrique, le _Dispatcher_ distribue ces identifiants sur l'ensemble des cœurs CPU pour une projection HTML parallèle.
- **La solution Rust :** Le _Borrow Checker_ garantit au moment de la compilation l'absence de _data races_. Le transfert de propriété (ownership) du `HashSet` depuis le thread du Collector vers le pool de workers du Dispatcher est validé statiquement.
- **La limite de Zig :** Zig délègue la responsabilité de la synchronisation au développeur. Dans un pipeline où la donnée transite violemment entre un thread de capture d'événements et $N$ threads de rendu matriciel, l'absence d'analyseur statique de concurrence augmente drastiquement la probabilité de conditions de course (race conditions) insidieuses en production.

## ⚙️ 3. Métaprogrammation et Projection AOT (Macros vs Comptime)

Le paradigme Ahead-Of-Time exige que la validation des données et la construction des gabarits s'effectuent à la compilation.

- **La solution Rust :** Le système s'appuie sur des macros procédurales (proc-macros) pour deux piliers fondamentaux :
  1.  **SQLx :** Validation des requêtes SQL contre le schéma PostgreSQL réel au moment de la compilation, garantissant que le layout mémoire du `struct` Rust correspond exactement au tuple retourné par la base.
  2.  **Maud :** Compilation des templates HTML directement en code machine natif, éliminant tout parsing ou allocation dynamique de chaînes de caractères au _runtime_.
- **Le positionnement de Zig :** Zig excelle dans ce domaine grâce à `comptime`, qui permet d'exécuter du code Zig arbitraire à la compilation. Théoriquement, `comptime` est supérieur et plus lisible que les macros Rust. Pratiquement, l'écosystème Zig ne fournit pas (encore) d'équivalent _drop-in_ à SQLx ou Maud capable de valider des schémas de base de données ou de compiler du balisage avec le même niveau d'intégration "Zéro Indirection".

## 🧩 4. Synthèse du Choix : Outillage vs Langage Pur

Le choix de Rust ne relève pas d'une supériorité sémantique du langage sur le DOD (domaine où Zig est structurellement plus pur, notamment sur le contrôle des allocateurs spatiaux), mais d'une adéquation de l'outillage.

Pour construire un moteur de rendu réactif :

- **Zig** imposerait de réécrire l'ordonnanceur d'I/O réseau, le driver de base de données asynchrone et le compilateur de templates.
- **Rust** fournit l'infrastructure réseau (Axum/Tower), l'ordonnanceur (Tokio) et la validation AOT (SQLx/Maud) clés en main, tout en respectant l'invariant principal du système : un déterminisme absolu sans _Garbage Collector_.
