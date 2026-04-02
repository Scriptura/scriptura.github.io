# 📝 Document d'Architecture : Unification en Monorepo (PostgreSQL & Rust)

Le présent document formalise la décision d'unifier le socle de données (PostgreSQL) et le moteur de traitement (Rust) au sein d'un unique dépôt de code (Monorepo). Initialement envisagée comme une séparation de domaines, la structure en deux dépôts a été écartée car elle introduisait une indirection organisationnelle incompatible avec les contraintes de couplage statique du pipeline AOT (Ahead-Of-Time).

---

## ⛓️ 1. Cohérence Statique et Validation AOT (SQLx)

L'architecture repose sur la capacité du compilateur Rust à valider les requêtes SQL contre le schéma réel de la base de données au moment de la compilation.

- **La dépendance compile-time :** L'usage de SQLx impose que le compilateur ait accès à l'état exact du DDL (Data Definition Language) pour garantir la correspondance des types. Une modification de colonne dans PostgreSQL (ex: passage d'un `INT4` à un `INT8`) invalide immédiatement le binaire Rust.
- **Le risque du multi-repo :** Séparer les dépôts créerait un "décalage de phase" où le dépôt Rust pourrait pointer vers une version obsolète du schéma, provoquant des échecs de compilation ou des erreurs de runtime indétectables avant le déploiement. Le monorepo garantit que le code et son schéma de validation coexistent dans le même espace de nommage.

## 🔄 2. Atomicité des Mutations (DDL et Structs)

Dans une approche Data-Oriented Design (DOD), la structure de la donnée (Layout) et la logique de transformation sont les deux faces d'un même artefact technique.

- **Commits Atomiques :** Le monorepo permet de réaliser des commits atomiques incluant simultanément la migration SQL (ex: ajout d'un composant ECS) et sa mise en œuvre dans le moteur Rust (mise à jour des `structs` et de la projection Maud). Cette unité de temps élimine les périodes d'incohérence entre les services.
- **Refactoring Global :** Toute modification structurelle dans la base de données peut être répercutée et testée immédiatement sur l'ensemble du pipeline applicatif, assurant que le "Blueprint" et le "Transformateur" restent synchronisés.

## 🧪 3. Intégrité du Pipeline de Test et CI/CD

Le moteur de rendu réactif nécessite un environnement d'intégration étroite pour valider le cycle de vie des signaux `LISTEN/NOTIFY`.

- **Reproductibilité locale :** Un seul dépôt permet de configurer un environnement de développement où une simple commande (`docker-compose up` ou script de setup) instancie la version exacte de PostgreSQL requise par le code Rust présent dans le répertoire de travail.
- **Validation de la CI :** Le pipeline d'intégration continue peut exécuter des tests d'intégration complets en utilisant les migrations SQL locales pour monter une base de données éphémère, garantissant que le binaire produit est certifié contre la version exacte du schéma qu'il rencontrera en production.

## 📦 4. Single Source of Truth (SSoT) et Performance

L'objectif de "Zéro Indirection" s'étend à la gestion des sources. L'unification élimine le besoin de gérer des versions de dépendances croisées (Git submodules, versions de crates externes) entre les composants de données et de logique.

- **Alignement Mécanique :** Le projet est traité comme une unité de performance monolithique. Le binaire Rust et le schéma PostgreSQL ne sont pas deux produits distincts communiquant par une interface souple, mais un seul système intégré où la base de données sert de bibliothèque de fonctions `SECURITY DEFINER` pour le runtime.
- **Simplicité Opérationnelle :** L'unification réduit la complexité de gestion des versions (versioning) et assure que la documentation, les migrations et le code source partagent un historique de modifications cohérent et linéaire.
