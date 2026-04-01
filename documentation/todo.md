## Contexte

Je possède un moteur JavaScript de gestion d’interface (tabs + accordéons) basé sur `<details>/<summary>` transformés en composants ARIA.

Le moteur actuel est **fonctionnel, robuste et très contraint**, avec :

- transformation JIT du DOM (`transform()`)
- moteur d’état (`syncState`)
- pipeline d’animation strict (ordre des mutations critique)
- accessibilité complète (ARIA 1.1)
- compatibilité `hidden="until-found"` + `beforematch`
- persistance via `localStorage`
- navigation clavier
- séparation logique (JS) / rendu (CSS)

⚠️ Toute modification doit préserver **strictement** ces invariants.

---

## Objectif

Faire évoluer ce moteur vers une architecture plus déterministe inspirée :

- ECS (Entity Component System)
- Data-Oriented Design (DOD)
- pipeline explicite (compute → commit → render)

SANS casser :

- le comportement existant
- les animations
- l’accessibilité
- la résilience

---

## Problème rencontré

Une tentative de refactor complet a échoué car :

1. Suppression implicite de `transform()` → plus de DOM canonique
2. Suppression du DOM comme source partielle de vérité → perte d’état initial
3. Simplification abusive de `syncState` → règles métier cassées
4. Désynchronisation animation / mutations DOM
5. Perte de certaines features (beforematch, clavier, persistence)

Conclusion :
👉 Le moteur actuel dépend d’invariants implicites du DOM qu’il ne faut PAS supprimer brutalement.

---

## Approche cible (à implémenter progressivement)

L’objectif n’est PAS de réécrire, mais de migrer par étapes sûres.

### 1. Pipeline cible

```text
HTML brut
 → transform()              // compilation DOM (INCHANGÉE)
   → DOM canonique
     → state mirror (nouveau)
       → scheduler (nouveau)
         → logique existante (syncState adaptée)
           → animation existante (INCHANGÉE)
```

---

### 2. Règles strictes

Tu dois respecter :

#### A. Transform est intouchable (phase 1)

- Ne pas supprimer
- Ne pas simplifier
- Ne pas déplacer sa responsabilité

#### B. Animation est intouchable

- Respect strict de :
  - scrollHeight timing
  - reflow forcé
  - rAF
  - transitionend
  - aria-hidden vs until-found

#### C. syncState est la référence métier

- Toute nouvelle logique doit être équivalente
- Pas de simplification naïve

#### D. DOM reste source de vérité INITIALE

- Puis state devient source après synchronisation

---

### 3. Étape demandée (UNIQUEMENT celle-ci)

👉 Implémenter **un scheduler minimal + state mirror**
👉 SANS casser le reste

Concrètement :

#### A. Ajouter un state mirror

```js
const indexMap = new Map()
let openState = []
```

Synchronisé avec DOM, mais pas encore source principale.

---

#### B. Introduire un scheduler

Remplacer :

```js
trigger.addEventListener('click', () => syncState(trigger))
```

par :

```js
trigger.addEventListener('click', () => enqueue(trigger))
```

Avec :

```js
const queue = []
let scheduled = false

const enqueue = trigger => {
  queue.push(trigger)
  if (!scheduled) {
    scheduled = true
    queueMicrotask(flush)
  }
}

const flush = () => {
  scheduled = false
  const unique = new Set(queue)
  queue.length = 0

  unique.forEach(trigger => {
    syncState(trigger) // IMPORTANT : ne pas modifier pour l’instant
  })
}
```

---

#### C. NE PAS modifier :

- transform()
- animatePanel()
- logique interne de syncState
- gestion localStorage
- navigation clavier
- beforematch

---

### 4. Objectif de cette étape

- Introduire batching / déduplication
- Ne provoquer AUCUNE régression
- Préparer séparation future state vs DOM

---

### 5. Étapes suivantes (ne pas implémenter maintenant)

Quand cette étape est validée :

1. Remplacer lecture DOM → lecture state
2. Introduire commit centralisé
3. Construire un graph indexé (optionnel)
4. Optimiser layout mémoire

---

## Contraintes de réponse

- Tu dois travailler par **modifications minimales**
- Tu dois **expliquer chaque changement**
- Tu dois **garantir zéro régression fonctionnelle**
- Si un doute existe → ne pas modifier

---

## Input

Je vais te fournir mon fichier JS actuel : `disclosure.js`.

---

## Output attendu

1. Version modifiée du fichier (diff minimal)
2. Explication structurée :
   - ce qui change
   - pourquoi c’est safe
   - ce qui est préparé pour la suite

3. Liste des invariants préservés

---

## Rappel critique

Ce moteur est déjà très optimisé et contraint.

👉 Le but n’est PAS de le “simplifier”
👉 Le but est de le **rendre plus déterministe sans perdre ses garanties**

---
