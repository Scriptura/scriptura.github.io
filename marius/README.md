# 🏛️ Marius : Moteur de Projection Réactive

Bienvenue sur le dépôt de **Marius**.

Marius n'est pas un framework web classique. C'est une architecture expérimentale et radicale qui repense la façon dont nous construisons des applications web orientées données.

Plutôt que d'empiler les couches traditionnelles (Base de données $\rightarrow$ ORM $\rightarrow$ API JSON $\rightarrow$ Framework Front-end $\rightarrow$ Navigateur), Marius s'inspire de l'architecture des moteurs de jeux vidéo pour proposer un chemin direct, prédictible et d'une performance absolue entre la donnée brute et l'écran de l'utilisateur.

---

## 💡 Le Concept : Moins d'intermédiaires, plus de certitudes

Dans une application web standard, le serveur passe son temps à traduire des données (du SQL vers des objets, des objets vers du JSON) et le client passe son temps à reconstruire l'interface. C'est ce qu'on appelle l'indirection.

Marius supprime ces intermédiaires à travers trois partis pris forts :

1. **La Base de Données est souveraine :** PostgreSQL n'est pas vu comme un simple espace de stockage passif, mais comme le cœur logique du système. Toute règle métier stricte y réside.
2. **Pas d'ORM (Object-Relational Mapping) :** Le code "parle" directement au moteur de base de données. Les requêtes sont validées dès la compilation pour garantir qu'aucune erreur de typage n'arrive en production.
3. **Le Serveur est un Projecteur (AOT) :** Au lieu de construire des pages à chaque requête de l'utilisateur, le serveur de Marius écoute silencieusement la base de données. Dès qu'une donnée change, il "projette" (pré-calcule) instantanément le HTML correspondant. La lecture devient alors un simple téléchargement de fichier statique.

---

## ⚙️ Comment ça marche sous le capot ?

L'architecture repose sur un duo de technologies travaillant en symbiose au sein de ce dépôt unique (Monorepo) :

- **Le Socle (PostgreSQL) :** Structuré pour une efficacité maximale. Les données sont organisées de manière à être lues le plus rapidement possible par la machine, en s'inspirant du _Data-Oriented Design_ (DOD).
- **Le Transformateur (Rust) :** Un serveur ultra-léger et asynchrone. Son seul rôle est d'écouter les événements de la base de données, de capter les changements, et de tisser le HTML natif à la volée.

### Le Cycle de Vie d'une Donnée

1. 📝 **Mutation :** Un événement modifie une donnée (ex: un achat réduit un stock).
2. 🔔 **Signal :** PostgreSQL lève instantanément la main pour signaler le changement au serveur Rust.
3. ⚡ **Projection :** Le serveur Rust récupère la donnée brute et génère le fragment HTML mis à jour, en utilisant toute la puissance des processeurs multi-cœurs.
4. 🌐 **Distribution :** L'utilisateur reçoit une interface toujours à jour, sans temps de calcul ni écrans de chargement complexes côté navigateur.

---

## 🎯 Pourquoi cette architecture ?

Ce projet a été conçu pour répondre à des problématiques précises où les architectures classiques atteignent leurs limites :

- **Déterminisme des performances :** Le temps de réponse doit être plat et prévisible, qu'il y ait 10 ou 10 000 utilisateurs connectés.
- **Sobriété énergétique et matérielle :** En supprimant le _Garbage Collector_ (gestionnaire de mémoire dynamique) et les lourds traitements côté navigateur (JavaScript massif), l'empreinte mémoire du serveur est divisée par dix.
- **Garantie de Cohérence :** En unifiant la base de données et le serveur dans ce dépôt commun, toute désynchronisation entre le modèle de données et le code fait échouer la compilation. Si ça compile, c'est que l'intégration est parfaite.

---

## 📂 Structure du Projet

- `/sql` : Le cœur de l'état. Contient les schémas, les procédures sécurisées et les règles de validation PostgreSQL.
- `/src` : Le moteur de projection. Le code source Rust responsable du serveur HTTP, de l'écoute des événements et du rendu HTML.
- `/templates` : Les gabarits d'interface qui seront compilés directement en code machine natif.

---

## 🚀 Prochaines étapes

_(Bientôt disponible)_ : Les documents d'architecture détaillés (ADR) se trouvent dans le dossier `/documentation/ADR/` pour ceux qui souhaitent plonger dans les choix techniques d'implémentation, la gestion de la mémoire, et l'approche transactionnelle fine.
