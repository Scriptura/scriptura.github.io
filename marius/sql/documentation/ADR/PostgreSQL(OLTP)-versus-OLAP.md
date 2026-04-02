# 📝 Document d'Architecture : Rejet du Moteur OLAP au Profit de PostgreSQL pour le Modèle ECS/DOD

Le présent document détaille l'argumentaire technique justifiant le maintien de PostgreSQL (moteur orienté transactionnel - OLTP) face aux solutions orientées colonnes (OLAP, type DuckDB ou ClickHouse) pour l'implémentation de la topologie ECS (Entity Component System) et du pipeline de projection AOT (Ahead-of-Time).

Bien que le modèle OLAP incarne nativement le pattern SoA (Structure of Arrays) préconisé par le DOD (Data-Oriented Design) au niveau du stockage physique, cette topologie s'avère fondamentalement incompatible avec les contraintes de mutation, de signalisation et de déterminisme de l'architecture.

---

## 🔄 1. Rupture du Canal de Signalisation (Event-Driven Pipeline)

Le pipeline AOT repose sur un couplage fort entre le moteur de base de données et le système applicatif (Rust/Tokio) via un protocole de notification push.

- **Le mécanisme PostgreSQL :** L'architecture utilise le protocole natif `LISTEN/NOTIFY` de PostgreSQL pour propager des signaux asynchrones d'interruption lors de la mutation d'une entité. Ce signal alimente directement le composant _Collector_.
- **L'incompatibilité OLAP :** Les moteurs analytiques sont conçus pour l'ingestion massive par lots (batching client-side). Ils ne disposent pas de mécanismes de callbacks asynchrones à la ligne (row-level notification). Sans émission d'événements à la source, le _Dispatcher_ perd sa capacité à identifier précisément les entités nécessitant une reprojection réactive.

## 💾 2. Amplification d'Écriture Critique (Write Amplification)

Le système gère des mutations fines, fréquentes et hautement ciblées sur des composants spécifiques (par exemple, la décrémentation d'un stock physique ou la mise à jour d'un horodatage).

- **Le mécanisme PostgreSQL :** Le schéma physique est configuré avec un `fillfactor` calibré (70-80%) pour absorber ces modifications _in-place_ via des **HOT updates (Heap-Only Tuples)**. L'empreinte I/O est minimale, le tuple modifié restant dans la même page mémoire de 8 Ko.
- **L'incompatibilité OLAP :** Le stockage colonnaire est structurellement immuable et hautement compressé. La modification d'une simple valeur scalaire (ex: un entier `INT8`) force le moteur à décompresser, modifier, puis réécrire un bloc (chunk) entier sur le disque. Une fréquence élevée de mutations unitaires provoquerait un effondrement des performances (thrashing) dû à l'amplification d'écriture.

## 🎯 3. Topologie de Lecture Incompatible (Point Queries)

L'étape de projection implique l'extraction d'un sous-ensemble précis d'entités après l'étape de dédoublonnement en mémoire (réalisée par le _Collector_).

- **Le mécanisme PostgreSQL :** Les accès aléatoires (Random Access) pour récupérer $N$ entités spécifiques par leur identifiant (ID) sont résolus en $O(\log n)$ via les index B-Tree. Seules les pages mémoire contenant les composants requis sont chargées dans le buffer cache.
- **L'incompatibilité OLAP :** Les bases orientées colonnes sont optimisées pour les exécutions vectorisées sur des colonnes complètes (Vectorized Execution). La recherche d'identifiants épars (Point Queries) force le moteur à scanner et décompresser de larges segments de données non pertinentes, annulant l'avantage de localité spatiale du processeur.

## 🔒 4. Absence d'Intégrité Transactionnelle Fine (ACID)

Le domaine métier, incluant des opérations financières et logistiques, impose un déterminisme absolu sur l'état des composants.

- **Le mécanisme PostgreSQL :** L'architecture s'appuie sur la granularité fine du modèle transactionnel relationnel : verrous exclusifs au niveau de la ligne (`FOR UPDATE` sur les composants de stock), intégrité référentielle stricte (`ON DELETE CASCADE` sur la hiérarchie des composants), et validation par triggers pour garantir l'immuabilité financière.
- **L'incompatibilité OLAP :** Pour maximiser le débit d'ingestion et d'analyse, les moteurs OLAP assouplissent ou suppriment les verrous exclusifs (Row-level locking) et les contraintes relationnelles, rendant impossible la garantie de prévention des _race conditions_ sur des composants critiques en concurrence d'accès.

---

## 🏗️ 5. Synthèse du Positionnement : OLTP sous Contraintes DOD

L'architecture actuelle ne consiste pas à simuler de l'OLAP, mais à **contraindre un moteur OLTP selon les principes du DOD**.

L'alignement rigoureux des octets (ordonnancement décroissant des colonnes), l'utilisation d'entiers natifs (`INT8`, `INT4`), l'élimination systématique du _padding_, et la fragmentation du schéma en tables de composants denses fournissent la densité de cache CPU nécessaire. Cette approche hybride conserve l'accès aléatoire indexé (B-Tree), l'intégrité transactionnelle (ACID) et le canal de notification (`NOTIFY`) indispensables au pipeline de rendu AOT.
