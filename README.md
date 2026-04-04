# 🏗️ Scriptura

Scriptura est un framework front-end web conçu comme un terrain d’expérimentation à grande échelle. Les choix techniques assument une compatibilité stricte aux navigateurs modernes afin d’exploiter les capacités natives de la plateforme web sans polyfills ni surcouches d'abstraction inutiles.

Le framework repose sur un principe central : **préserver l’intégrité structurelle du HTML**. Aucun balisage superflu n’est introduit pour servir des comportements. Le contenu prime, l'arborescence DOM est traitée comme une source de vérité sémantique, et la mise en forme s’appuie sur le flux logique du document.

## 🔗 Liens & Démonstration

- **GitHub Pages (Production)** : [scriptura.github.io](https://scriptura.github.io)
- **Composants (Local)** : [components.html](https://scriptura.github.io/page/components.html)
- **Templates (Local)** : [templates.html](https://scriptura.github.io/page/templates.html)

## ⚙️ Invariants Structurels & Architecture

Scriptura ne se contente pas de styliser des composants ; il implémente des logiques de type moteur (engine-centric) au sein du navigateur, en s'inspirant des patterns **ECS (Entity-Component-System)** et **DOD (Data-Oriented Design)**.

### 1\. Séparation stricte État / Rendu (DOD)

- **DOM comme buffer de sortie exclusif :** Le DOM n'est pas utilisé pour stocker l'état volatil. Les composants complexes (comme le lecteur média) maintiennent un état interne via des _stores_ plats (objets indexés par IDs d'entité).
- **Découplage Data / Logic :** Les systèmes de logique transforment les données des stores sans jamais toucher au DOM. Un système de rendu (`UIRenderSystem`) est le seul autorisé à muter le DOM, et uniquement pour les entités marquées comme "dirty" (modifiées).

### 2\. Pipeline Déterministe

- **Boucle de traitement explicite :** Les mises à jour complexes sont drainées via un pipeline par frame (`requestAnimationFrame`).
- **Séquençage :** `Input -> CommandBuffer -> CommandSystem -> Hardware Read -> LogicSystem -> UIRenderSystem`. L'ordre garantit qu'aucune cascade d'événements asynchrones ne vient désynchroniser l'interface.

### 3\. Transformation AOT / JIT (Disclosure System)

- **HTML-First :** Les composants comme les onglets ou les accordéons sont rédigés via des balises natives (`<details>`, `<summary>`).
- **Transformation Just-In-Time :** Au runtime, un parseur convertit cette structure canonique en composants ARIA complexes (rôles `tablist`, `tabpanel`, `region`). Cela garantit un contenu accessible et indexable (SEO, CTRL+F via `hidden="until-found"`) sans bloat initial.

### 4\. Délégation Cinétique

- **Le JS gère l'état, le CSS gère le mouvement :** Le JavaScript se limite à la distribution des états et à la mutation des contrats d'attributs (`aria-expanded`, `aria-hidden`). Toute la cinétique (animations, transitions, accélération matérielle) est strictement déléguée au CSS.
- **Layout piloté par les données réelles :** Les transitions utilisent des mesures exactes du flux DOM (via `scrollHeight` capturé avant mutation) pour éviter les hauteurs fixes codées en dur.

## 🛠️ Écosystème & Outillage

Ce dépôt contient l'intégralité de la chaîne de production :

- **Bootstrap "maison" :** CSS modulaire organisé en composants, exploitant les variables natives et l'imbrication CSS moderne.
- **Templates métiers :** Gabarits structurels prêts à l'emploi (Article, Forum, etc.) démontrant la projection de différentes UI sur une sémantique unique.
- **Task Runner intégré :** Pipeline de build sur mesure opéré via des packages `pnpm`, assurant une orchestration rapide sans dépendance à des bundlers monolithiques.

## 🎯 Philosophie d'usage

L’approche consiste à partir d’un HTML correctement structuré, puis à activer des comportements via des attributs ou des conteneurs ciblés. Une même source de données (ex: une liste `<details>`) peut ainsi être projetée en différents composants (onglets exclusifs, accordéons multiples) selon le contexte, sans jamais altérer sa sémantique initiale.

> **Note :** Ce site n’a pas vocation à être une documentation API exhaustive. Il présente les patterns du framework à travers leur exécution réelle et constitue avant tout un espace d’usage concret pensé pour son auteur.
