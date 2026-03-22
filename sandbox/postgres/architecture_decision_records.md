# Architecture Decision Records (ADR)
## Projet Marius — Refonte ECS/DOD · PostgreSQL 18
## Session R&D · 2025–2026

---

> Ce document consolide l'ensemble des arbitrages architecturaux effectués au fil
> des phases de refonte. Pour chaque décision : le contexte, les options évaluées,
> la décision retenue et sa justification technique.

---

## ADR-001 — Séparation DDL / DML

**Statut** : Adopté  
**Phase** : Consolidation finale

### Contexte
Le master schema initial fusionnait schéma et données de test dans un seul fichier.

### Décision
Scinder en deux artefacts :
- `master_schema_ddl.pgsql` — Blueprint immuable (schéma pur)
- `master_schema_dml.pgsql` — Seed data (dev/CI uniquement)

### Justification
Les données de remplissage n'ont pas vocation à être exécutées en production. La
séparation permet un cycle CI/CD propre : le DDL est idempotent et versionnable
seul ; le DML est optionnel et dépend de l'environnement cible.

**Exception documentée** : les `INSERT` sur `identity.permission_bit` et
`identity.role` restent dans le DDL. Ce sont des données de configuration
structurelle insécables du schéma (au même titre que les `REVOKE` qui les suivent).

---

## ADR-002 — Spine `content.document` indépendant de `identity.entity`

**Statut** : Adopté  
**Phase** : Phase 3 (domaine content)

### Contexte
Le modèle `identity.entity` sert de spine universel pour les acteurs du système
(comptes, profils publics). La question s'est posée de le réutiliser pour les
documents (articles, pages).

### Options évaluées
| Option | Avantage | Inconvénient |
|---|---|---|
| Spine partagé (`identity.entity`) | Un seul registre d'IDs | Mélange volumétrique, cascades croisées, couplage sémantique |
| Spine dédié (`content.document`) | Isolation complète | Un registre de plus à maintenir |

### Décision
Spine `content.document` indépendant.

### Justification
Quatre raisons distinctes, chacune suffisante :

1. **Sémantique** : un document n'est pas un acteur. Il n'a pas d'auth, pas de
   contact, pas de permissions. Partager le spine introduit des jointures à vide
   sur 100 % des requêtes documentaires.

2. **Volumétrie asymétrique** : 500 000 utilisateurs vs potentiellement plusieurs
   millions de documents et révisions. Un spine partagé ferait exploser
   `identity.entity`, dégradant ses index B-tree.

3. **Cascade isolée** : `DELETE CASCADE` sur un article ne doit pas traverser
   `identity.entity` (table des acteurs du système).

4. **Évolutivité** : `content.document` peut supporter du polymorphisme documentaire
   (`doc_type`) sans modifier `identity`.

---

## ADR-003 — Bitmask `INT4` pour les permissions de rôle

**Statut** : Adopté  
**Phase** : Optimisation bitmask (itération post-Phase 1)

### Contexte
Le modèle original stockait 15 colonnes `BOOLEAN` dans `identity.role`.

### Options évaluées
| Type | Taille réelle | Alignement | Opérateurs |
|---|---|---|---|
| 15 × `BOOLEAN` | 15 B (+ padding) | Align 1 chacun | Accès colonne par colonne |
| `BIT(16)` | 6 B (varlena 4B + 2B données) | varlena | Syntaxe `B'...'` peu lisible |
| `INT2` | 2 B fixe | Align 2 | `&`, `\|`, `~` natifs — mais bit 15 = signe |
| `INT4` | 4 B fixe | Align 4 | `&`, `\|`, `~` natifs — 17 bits libres |

### Décision
`INT4` unique, colonne `permissions`.

### Justification
- `BIT(n)` est varlena dans PostgreSQL : 4 bytes d'en-tête + données. Plus lourd
  que `INT4`, opérateurs moins naturels.
- `INT2` couvre les 15 permissions actuelles (max 32 767), mais le bit 15 est le
  bit de signe signé. Toute 16e permission déclencherait un dépassement silencieux.
- `INT4` : 4 bytes fixes, alignement natif CPU, 17 bits libres pour extensions,
  opérateurs `&` / `|` / `~` lisibles par tout développeur.

**Gain mesuré** : tuple `identity.role` passe de 61 bytes à 49 bytes (−20 %).
Le gain réel est en "CPU tuple deforming" : réduction de 17 à 3 appels
`slot_getattr()` par lecture de rôle (hot path login).

**Invariant layout** : `permissions INT4` est déclaré *avant* `id SMALLINT` pour
éliminer 2 bytes de padding (INT4 à offset 0 → aligné nativement ; SMALLINT
suit sans contrainte d'alignement supplémentaire).

---

## ADR-004 — Layout physique décroissant (règle universelle)

**Statut** : Adopté  
**Phase** : Phase 1, appliqué à tous les domaines

### Contexte
PostgreSQL aligne chaque colonne sur un multiple de son `typalign`. Un type
de petite taille suivi d'un type de grande taille génère du padding invisible.

### Décision
Ordre de déclaration systématique dans toutes les tables :
```
8 bytes  → TIMESTAMPTZ, FLOAT8, INT8
4 bytes  → INT4, DATE, FLOAT4
2 bytes  → SMALLINT
1 byte   → BOOLEAN
variable → CHAR, VARCHAR, TEXT, NUMERIC, ltree, geometry
```

### Justification
Exemples concrets de gains dans ce projet :

| Table | Avant | Après | Gain/tuple |
|---|---|---|---|
| `identity.auth` | ~167 B | ~155 B | 12 B |
| `identity.person_identity` | ~88 B | ~74 B | 14 B |
| `org.org_hierarchy` | 42 B | 40 B | 2 B |

Le gain par tuple est modeste en absolu mais permanent. Sur 500 000 lignes en
cache L2/L3, l'économie en pages chargées est mesurable (facteur ×8–10 sur les
tables person comparées au modèle monolithique original).

**Note** : `NUMERIC` est toujours varlena dans PostgreSQL, quel que soit le
paramétrage `NUMERIC(n,m)`. Il va systématiquement après les types fixes.

---

## ADR-005 — Fragmentation ECS des tables larges

**Statut** : Adopté  
**Phase** : Phase 1 (identity), Phase 2 (geo, org, commerce), Phase 3 (content)

### Contexte
Le modèle original (AoS — Array of Structures) stockait tous les attributs d'une
entité dans un seul tuple large. Ex : `__person` = 26 colonnes, ~600 bytes/tuple,
~13 tuples/page.

### Décision
Fragmentation par fréquence d'accès (pattern ECS — Entity-Component-System) :

```
Entité (spine)    → ID pur, aucune donnée métier
Core              → champs hot path (status, dates, FK primaires)
Identity          → noms, slugs, données de listing
Contact           → email, téléphone, URL (accès contextuel)
Biography/Legal   → dates, identifiants légaux (accès rare)
Content           → textes longs (TOAST, accès très rare)
```

### Justification
Un scan qui ne cible que les noms d'auteur (`person_identity`) ne charge plus
la biographie ni les descriptions. La densité par page passe de ~13 à ~110 tuples
sur ce composant seul — facteur ×8,5.

**Coût** : jointures supplémentaires sur les requêtes complètes. Mitigation via
vues sémantiques qui reconstituent l'objet complet pour la couche applicative.

---

## ADR-006 — Vues sémantiques comme seule interface applicative

**Statut** : Adopté  
**Phase** : Toutes phases

### Contexte
Les tables physiques fragmentées sont opaques et non-intuitives pour un
développeur applicatif. La sémantique schema.org était perdue dans la
fragmentation.

### Décision
La couche applicative ne connaît que les vues. Les tables physiques sont
considérées comme un détail d'implémentation.

```
Tables physiques → Composants ECS (optimisées, denses)
Vues SQL         → Interface schema.org (lisible, compatible)
```

### Justification
- Découplage total entre le modèle physique et l'interface applicative.
- Les vues peuvent être modifiées sans impacter le code applicatif (et
  réciproquement).
- La séparation `v_article_list` (listing, zéro TOAST) / `v_article` (page
  complète, avec TOAST) garantit architecturalement que les listings ne chargent
  jamais les corps HTML.

**Règle d'écriture** : lecture via vues, écriture via procédures stockées
exclusivement. Les `INSERT`/`UPDATE` directs sur les tables physiques sont
révoqués pour les rôles applicatifs.

---

## ADR-007 — Schémas PostgreSQL pour l'isolation des domaines

**Statut** : Adopté  
**Phase** : Phase 1 (décision initiale)

### Contexte
Le modèle original utilisait un préfixe `__` (double underscore) pour toutes les
tables dans le schéma `public`.

### Décision
Migration vers cinq schémas dédiés :

| Schéma | Contenu |
|---|---|
| `identity` | Acteurs, comptes, permissions, rôles |
| `geo` | Lieux, coordonnées géospatiales |
| `org` | Organisations, hiérarchies |
| `commerce` | Produits, transactions, lignes de commande |
| `content` | Documents, médias, tags, commentaires |

### Justification
- Isolation des permissions : `GRANT USAGE ON SCHEMA content TO editorial_role`
  sans exposer `identity` ou `commerce`.
- `search_path` configurable par rôle de connexion (isolation par service).
- Lisibilité : `content.tag` vs `__tag`, `identity.auth` vs `__account`.
- Prérequis à la fragmentation ECS : sans schémas, les tables fragmentées
  (`person_core`, `person_identity`...) polluent un espace de noms unique.

---

## ADR-008 — Gestion des spines org et geo sans `identity.entity`

**Statut** : Adopté  
**Phase** : Phase 2

### Contexte
Les organisations et les lieux sont des entités structurelles. Faut-il les
rattacher au spine `identity.entity` (spine universel) ou leur créer un spine
propre ?

### Décision
- `org.entity` : spine propre (même pattern que `identity.entity`)
- `geo.place_core` : pas de spine séparé, PK `INT` directe sur la table

### Justification
**org.entity** : les organisations peuvent avoir des contacts, des membres, des
permissions futures. Un spine dédié permet les mêmes extensions que `identity`.

**geo.place_core** : les lieux ne sont pas des acteurs. Ils sont des destinations
(FK cibles depuis `org`, `identity`, `commerce`). Un spine séparé ajouterait
une jointure sur 100 % des requêtes géospatiales sans aucun bénéfice sémantique.
Le PK `INT` direct est le bon niveau d'abstraction.

---

## ADR-009 — Résolution 1NF : suppression de `__transaction._list`

**Statut** : Adopté  
**Phase** : Phase 2 (domaine commerce)

### Contexte
Le modèle original stockait la liste des produits d'une commande dans une
colonne `_list VARCHAR(255)` contenant des IDs sérialisés en CSV.

### Problèmes identifiés
1. **1NF violée** : plusieurs valeurs atomiques dans une colonne.
2. **Intégrité référentielle impossible** : pas de FK sur un CSV.
3. **Requêtes impossibles** : impossible d'agréger quantités ou prix par produit
   sans parsing applicatif.
4. **Snapshot de prix absent** : le prix historique d'une commande était perdu.

### Décision
Table `commerce.transaction_item(transaction_id, product_id, quantity,
unit_price_snapshot)`.

### Justification
- FK sur `product_id` → intégrité référentielle garantie.
- `unit_price_snapshot NUMERIC(12,2)` : copie du prix au moment de l'INSERT
  (pattern "snapshot de prix"). Le prix courant peut changer sans altérer
  l'historique des commandes.
- `quantity INT4` (et non `SMALLINT`) : le SMALLINT max est 32 767. Les commandes
  B2B peuvent dépasser ce volume. INT4 couvre jusqu'à 2 147 483 647.

---

## ADR-010 — Corrections de typage DUNS / SIRET

**Statut** : Adopté  
**Phase** : Phase 2 (domaine org)

### Contexte
Le modèle original déclarait `_duns SMALLINT` et `_siret SMALLINT`.
SMALLINT est limité à 32 767.

### Décision
- `duns CHAR(9)` + contrainte `CHECK (duns ~ '^[0-9]{9}$')`
- `siret CHAR(14)` + contrainte CHECK Luhn inline

### Justification
DUNS = 9 chiffres, plage 000000000–999999999. Non-arithmétique : les zéros
initiaux sont significatifs. SMALLINT (max 32 767) ne couvre même pas 5 chiffres.
INT4 couvrirait la plage numérique mais perdrait les zéros initiaux.
`CHAR(9)` est le type exact : longueur fixe, zéros conservés, validation par regex.

Même raisonnement pour SIRET (14 chiffres, clé de Luhn).

La contrainte Luhn est implémentée inline en CHECK (pas de trigger) :
coût = 14 opérations entières à l'INSERT, zéro coût à la lecture.

---

## ADR-011 — `ltree` pour les hiérarchies de tags et commentaires

**Statut** : Adopté  
**Phase** : Phase 3 (domaine content)

### Contexte
Deux structures hiérarchiques à gérer : la taxonomie des tags et l'arborescence
des commentaires. Trois patterns évalués : Adjacency List, Nested Set, ltree.

### Comparaison

| Critère | Adjacency List | Nested Set | ltree |
|---|---|---|---|
| Lecture sous-arbre | O(profondeur) — CTE récursive | O(1) — BETWEEN | O(log n) — index GiST |
| INSERT | O(1) | O(n) — recalcul intervalles | O(1) — concat chemin |
| Lisibilité | `parent_id = 42` | `lft=5, rgt=12` | `theology.patristics` |
| Index utilisable | B-tree sur parent_id | B-tree sur lft/rgt | GiST (KNN, @>, <@) |

### Décision
`ltree` pour les deux cas.

### Justification
**Tags** : les insertions de tags sont rares (taxonomie éditoriale stable), les
lectures de sous-arbres sont fréquentes ("tous les articles sur les Pères de
l'Église"). ltree avec index GiST résout le sous-arbre en O(log n) sans CTE.

**Commentaires** : le pattern dominant est l'affichage d'un thread complet
(`<@` descendant). ltree le résout en O(log n). Les insertions sont O(1)
(concat du chemin parent + id). La modération (déplacement d'un commentaire)
est rare et acceptable en O(descendants).

Le Nested Set est écarté pour les commentaires : son INSERT est O(n), catastrophique
sous concurrence (verrouillage de table nécessaire pour recalculer les intervalles).

---

## ADR-012 — Procédure `content.create_comment()` vs double trigger BEFORE/AFTER

**Statut** : Adopté  
**Phase** : Patch post-Phase 3

### Contexte
La construction du chemin ltree nécessitait l'`id` du commentaire, alloué par
`GENERATED ALWAYS AS IDENTITY` seulement après l'INSERT. La solution initiale
utilisait un trigger BEFORE (chemin préfixe) + trigger AFTER (finalisation).

### Problème
Le trigger AFTER génère un `UPDATE` immédiat sur la ligne venant d'être insérée.
Sous MVCC, un UPDATE crée un dead tuple (v1 marqué `xmax`, v2 écrit sur le heap).
La colonne `path` étant couverte par deux index (GiST + B-tree composite), HOT
est impossible → chaque INSERT déclenche 2 entrées d'index par commentaire.

Sur un site actif (10 000+ commentaires/jour) :
- Bloat linéaire sur `content.comment`
- Pression autovacuum doublée (dead tuples auto-infligés)
- 2 écritures heap par commentaire au lieu de 1

### Décision
Procédure `content.create_comment()` avec `nextval()` préalable.

### Mécanisme
```
1. nextval(sequence) → id alloué en mémoire, avant toute écriture heap
2. SELECT path du parent (si réponse) → lecture en cache probable
3. Construction du chemin ltree complet en mémoire PL/pgSQL
4. INSERT OVERRIDING SYSTEM VALUE → une seule écriture heap, chemin définitif
```

### Justification
- Zéro dead tuple structurel.
- Une seule entrée d'index par commentaire (GiST + B-tree).
- Logique explicite, testable unitairement, instrumentable.
- `nextval()` est atomique et transactionnel : les gaps de séquence en cas
  de rollback sont identiques au comportement GENERATED ALWAYS standard.

**Contrainte opérationnelle** : les INSERT directs sur `content.comment` sont
révoqués pour les rôles applicatifs. La procédure est le seul point d'entrée.

---

## ADR-013 — `GENERATED ALWAYS AS IDENTITY` vs `SERIAL` / UUID

**Statut** : Adopté implicitement  
**Phase** : Phase 1 (décision initiale)

### Contexte
Le modèle original utilisait `INT GENERATED BY DEFAULT AS IDENTITY` (syntaxe SQL
standard). Le commentaire dans le fichier original mentionnait UUID comme
alternative.

### Décision
`INT GENERATED ALWAYS AS IDENTITY` sur toutes les tables.

### Justification
- **UUID** : 16 bytes vs 4 bytes (INT4). Sur les tables de liaison N:N (tuples
  à 32 bytes), remplacer les deux INT4 par deux UUID doublerait la taille du
  tuple et dégraderait les index. UUID est pertinent pour les systèmes
  distribués multi-nœuds ; un PostgreSQL monolithique n'en a pas besoin.
- **SERIAL** : syntaxe propriétaire PostgreSQL, dépréciée depuis PG 10.
  `GENERATED ALWAYS AS IDENTITY` est le standard SQL:2003 équivalent.
- **GENERATED ALWAYS** vs **BY DEFAULT** : `ALWAYS` interdit les INSERT directs
  avec une valeur explicite (sauf `OVERRIDING SYSTEM VALUE`), forçant l'usage
  des procédures d'écriture. Cohérent avec l'architecture de contrôle d'accès.

---

## ADR-014 — `NUMERIC(12,2)` pour les montants monétaires

**Statut** : Adopté  
**Phase** : Phase 2 (domaine commerce)

### Contexte
Le modèle original déclarait `_price NUMERIC NULL` (sans précision).

### Décision
`NUMERIC(12,2)` pour tous les montants (`price`, `unit_price_snapshot`).

### Justification
- `FLOAT8` (double précision) introduit des erreurs d'arrondi binaire sur les
  représentations décimales exactes. Ex : `0.1 + 0.2 ≠ 0.3` en virgule flottante.
  Inacceptable pour des montants financiers.
- `NUMERIC` sans précision : stockage variable non contrôlé, performances
  imprévisibles.
- `NUMERIC(12,2)` : précision décimale exacte, max 9 999 999 999,99 (~10 Md€),
  stockage interne compact (~6-8 bytes pour les montants courants).

---

## ADR-015 — `fillfactor` sur les tables à mises à jour fréquentes

**Statut** : Adopté  
**Phase** : Phases 1, 2, 3

### Décision et valeurs retenues

| Table | fillfactor | Colonne(s) mise(s) à jour fréquemment |
|---|---|---|
| `identity.auth` | 70 | `last_login_at` (chaque connexion) |
| `commerce.product_core` | 80 | `stock`, `is_available` (chaque vente) |
| `content.core` | 75 | `status`, `modified_at` (cycle de vie) |

### Justification
Le `fillfactor` réserve un pourcentage de chaque page pour les mises à jour
futures. Un UPDATE qui tient dans l'espace réservé de la même page devient
un HOT update (Heap-Only Tuple) : aucune nouvelle entrée d'index n'est créée.

**Condition HOT** : la colonne modifiée n'est couverte par aucun index.
- `last_login_at` : non indexé → HOT garanti avec fillfactor < 100
- `stock` : non indexé → HOT garanti
- `status` : non indexé → HOT garanti (l'index `core_published` est partiel sur
  `status = 1` ; un UPDATE status 0→1 crée une entrée, mais 1→2 n'en crée pas)

**Coût** : augmentation de l'espace disque proportionnelle à `(100 - fillfactor) %`.
Sur `identity.auth` (fillfactor 70) : +43 % de pages physiques.
Acceptable au regard de l'élimination du bloat sur une table accédée 500 000×/jour.

---

## ADR-016 — Isolation agressive du TOAST (`toast_tuple_target = 128`)

**Statut** : Adopté  
**Phase** : Phases 2 et 3 (toutes les tables de contenu "froid")  
**Origine** : Audit Gemini — omission identifiée dans la v1 du journal

### Contexte
PostgreSQL déclenche le TOAST (The Oversized-Attribute Storage Technique) par
défaut au-delà de ~2 Ko par tuple. En dessous, les varlena longs (TEXT, VARCHAR
volumineux) restent dans le tuple principal, alourdissant les scans même lorsque
la colonne n'est pas projetée.

### Tables concernées

| Table | Colonne(s) TOAST | Justification |
|---|---|---|
| `content.body` | `content TEXT` | Corps HTML, toujours > 2 Ko en pratique |
| `content.revision` | `snapshot_body TEXT` | Snapshot éditorial, même volume |
| `geo.place_content` | `description TEXT` | Texte descriptif long |
| `commerce.product_content` | `description TEXT` | Fiche produit longue |
| `identity.person_content` | `description TEXT` | Biographie longue |

### Décision
`toast_tuple_target = 128` sur toutes les tables de contenu "froid".

### Justification
Le seuil par défaut (≈ 2 Ko) est un compromis généraliste. Pour les tables cold
path de ce modèle, le comportement souhaité est le TOAST *systématique* de tout
texte long, même court (< 2 Ko), afin de garantir que les tables hot path
(`content.core`, `content.identity`) ne soient jamais alourdies par des
attributs textuels, quelle que soit la taille du contenu.

**Mécanisme concret** : avec `toast_tuple_target = 128`, PostgreSQL tente de
maintenir le tuple principal sous 128 bytes. Toute varlena qui dépasse ce budget
est externalisée dans la table TOAST associée. Dans le tuple principal, seul un
pointeur TOAST de 18 bytes subsiste.

**Conséquence directe pour le hot path** : un `SELECT` sur `content.v_article_list`
(qui ne projette pas `articleBody`) ne déclenche *aucun* accès à la table TOAST,
même si `content.body` est physiquement joint dans la vue parente `content.v_article`.
PostgreSQL ne résout le pointeur TOAST que si la colonne est dans la liste de
projection.

**Avertissement DBA** : supprimer ce paramètre (retour au défaut de 2 Ko) ne
détruirait pas les données existantes, mais les prochains INSERT et UPDATE
laisseraient des tuples plus larges en heap, dégradant progressivement la
densité des tables cold path et leur impact sur le cache.

**Stratégie de stockage complémentaire** : `content.body.content` est configuré
en `STORAGE EXTENDED` (compression LZ4 + TOAST). Un article HTML de 50 Ko est
typiquement compressé à 12–15 Ko en stockage réel.

---

## ADR-017 — Index BRIN sur les colonnes temporelles chronologiques

**Statut** : Adopté  
**Phase** : Phases 1, 2 et 3  
**Origine** : Audit Gemini — omission identifiée dans la v1 du journal

### Contexte
Les colonnes `created_at` de type `TIMESTAMPTZ` sont présentes dans la majorité
des tables. Un index B-tree classique sur ces colonnes serait valide mais
disproportionné pour l'usage réel.

### Tables concernées

| Table | Index BRIN | pages_per_range |
|---|---|---|
| `identity.auth` | `auth_created_at_brin` | 128 |
| `content.core` | `core_created_brin` | 128 |
| `commerce.transaction` | `transaction_created_brin` | 128 |
| `org.org_core` | `org_core_created_brin` | 64 |

### Décision
Index BRIN (Block Range Index) sur toutes les colonnes `created_at` à progression
monotone, en remplacement des index B-tree.

### Justification
**Définition** : un BRIN stocke, pour chaque plage de N blocs consécutifs
(`pages_per_range`), les valeurs min et max de la colonne indexée. La taille
totale d'un BRIN est de l'ordre de quelques dizaines de Ko, contre plusieurs Mo
pour un B-tree sur la même colonne.

**Condition d'efficacité** : le BRIN est optimal lorsque la corrélation entre
l'ordre physique des tuples et l'ordre des valeurs est forte. C'est exactement
le cas pour `created_at` : les lignes sont insérées chronologiquement, donc
les valeurs min/max par plage de blocs sont naturellement resserrées.

**Compromis accepté** :
- Recherche ponctuelle (`WHERE created_at = '2024-05-16'`) : le BRIN est moins
  précis qu'un B-tree (il indique *quels blocs* sont candidats, pas *quelle ligne*).
  Le heap scan résiduel est acceptable car ces requêtes sont rares (analytics,
  audit).
- Requête par plage (`WHERE created_at BETWEEN ... AND ...`) : efficace — le BRIN
  élimine les blocs hors plage sans les charger.
- Listings chronologiques (usage dominant) : couverts par les index partiels sur
  `published_at` et `status`, pas par le BRIN.

**Gain RAM** : un index B-tree sur `identity.auth.created_at` (500 000 lignes)
occuperait ~11 Mo en shared buffers. Le BRIN équivalent : ~50 Ko. Le delta (~10 Mo)
reste disponible pour le cache des pages heap à haute densité.

---

## ADR-018 — Résolution du problème N+1 par agrégation JSON dans les vues

**Statut** : Adopté  
**Phase** : Phases 2 et 3 (vues cross-schéma)  
**Origine** : Audit Gemini — omission identifiée dans la v1 du journal

### Contexte
Les vues sémantiques (`content.v_article`, `commerce.v_transaction`) doivent
exposer des relations N:N (tags d'un article, médias d'un article, lignes d'une
commande). Sans précaution, la couche applicative effectuerait une requête
principale + N requêtes secondaires (une par entité liée) : le problème N+1.

### Décision
Agrégation JSON directement dans le moteur PostgreSQL via `json_agg()` +
`json_build_object()`, ou l'équivalent SQL:2016 `JSON_ARRAYAGG()` +
`JSON_OBJECT()` (PG 15+).

### Implémentation

```sql
-- Exemple dans content.v_article
(
  SELECT json_agg(
    json_build_object('id', t.id, 'name', t.name, 'slug', t.slug, 'path', t.path::text)
    ORDER BY t.path
  )
  FROM  content.content_to_tag ct
  JOIN  content.tag t ON t.id = ct.tag_id
  WHERE ct.content_id = d.id
) AS "keywords"
```

### Justification

**Problème N+1 éliminé** : une requête sur `content.v_article` retourne l'article
*et* tous ses tags *et* tous ses médias en un seul aller-retour réseau,
indépendamment du nombre de tags ou de médias associés.

**Contrat d'interface avec la couche applicative** : la base de données livre un
objet JSON directement désérialisable. L'applicatif n'a pas à orchestrer de
jointures secondaires ni à assembler l'objet manuellement.

**Coût CPU vs coût réseau** :
- CPU moteur pour `json_agg` : élevé sur des volumes importants.
- Latence réseau pour N requêtes supplémentaires : multiplicateur de la latence
  de base (typiquement 1–5 ms par aller-retour en réseau local, 10–50 ms en WAN).
- Arbitrage : pour des objets contenant 3–20 éléments liés (tags, médias, lignes
  de commande), le coût CPU de l'agrégation est systématiquement inférieur au
  coût cumulé des aller-retours réseau.

**Limites documentées** :
- `commerce.v_transaction` : la vue agrège toutes les lignes de commande. Sans
  clause `WHERE` couverte par un index, un `SELECT *` sur cette vue sur 500 000
  transactions force une agrégation complète. Utiliser uniquement avec filtre
  (`WHERE t.id = :id` ou `WHERE t.client_entity_id = :id`), ou via la
  `MATERIALIZED VIEW` suggérée dans `extension_blueprint.pgsql`.
- Les sous-requêtes corrélées dans les vues (`SELECT COUNT(*)` pour
  `v_tag_tree."articleCount"`) sont réévaluées pour chaque ligne de la vue.
  Acceptable pour une liste de tags (~200 entrées) ; à matérialiser si la
  taxonomie dépasse plusieurs milliers de tags.

---

## Récapitulatif des tables et densités

| Table | Bytes/tuple | Tuples/page | Ratio vs modèle original |
|---|---|---|---|
| `content.document` | 32 B | ~255 | — (nouvelle) |
| `content.core` | 64 B | ~127 | — (nouvelle) |
| `content_to_tag` | 32 B | ~255 | = `__tag_to_article` |
| `identity.role` | 49 B | ~167 | −20 % vs ancien modèle booléen |
| `identity.auth` | ~155 B | ~51 | vs `__account` : ×1,7 densité |
| `identity.person_identity` | ~74 B | ~110 | vs `__person` : ×8,5 densité |
| `identity.person_biography` | 44 B | ~185 | — (composant isolé) |
| `org.org_hierarchy` | 40 B | ~204 | — (nested set conservé) |
| `commerce.transaction_item` | 44 B | ~186 | remplace `_list` VARCHAR non-indexable |
| `geo.place_core` (minimal) | 61 B | ~134 | vs `__place` complet : ×2,5 |

---

*Document généré à partir de la session R&D Marius · Architecture ECS/DOD · PostgreSQL 18*  
*ADR-016 à ADR-018 ajoutés suite à l'audit Gemini (omissions identifiées dans la v1)*
