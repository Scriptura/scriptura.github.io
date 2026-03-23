# Architecture Decision Records (ADR)

## Projet Marius — ECS/DOD · PostgreSQL 18

---

> Arbitrages architecturaux du projet Marius. Chaque entrée documente ce qui
> **n'est pas déductible de la lecture du code** : le raisonnement qui a conduit
> à une décision, les alternatives écartées et leurs coûts respectifs.
>
> Ordre : priorité décroissante — invariants de sécurité et contraintes physiques
> d'abord, décisions structurelles et de typage ensuite, organisation du dépôt en fin.

---

## ADR-020 — Interface d'écriture scellée : révocation DML globale et SECURITY DEFINER

**Statut** : Adopté

### Décision

Trois mécanismes conjugués forment le verrou d'écriture :

1. `marius_user` (rôle applicatif) ne reçoit que `SELECT` et `EXECUTE`. Aucun
   `INSERT`, `UPDATE`, `DELETE` direct sur les tables physiques.
2. Toutes les procédures de mutation sont déclarées `SECURITY DEFINER` avec
   `SET search_path = 'schema', 'pg_catalog'`. Elles s'exécutent avec les droits
   du propriétaire (`postgres`), indépendamment des droits de l'appelant.
3. `marius_admin` hérite de `marius_user` et reçoit en sus l'écriture directe.
   Réservé aux migrations, backfills et correctifs de production.

### Pourquoi ce n'est pas de la sur-ingénierie

L'invariant ECS posé par ADR-019 — les procédures sont les seuls points d'entrée
en écriture — ne peut être tenu qu'au niveau moteur. Laisser `INSERT/UPDATE/DELETE`
accessibles à `marius_user` revient à documenter une contrainte sans l'appliquer.
Toute dérive (ORM bypassant les procédures, script de migration mal ciblé) est
silencieuse et non détectable à la lecture du DDL.

### Risques SECURITY DEFINER et parades

**Vulnérabilité `search_path`** : une procédure `SECURITY DEFINER` qui résout
des noms non qualifiés dans un `search_path` contrôlé par l'attaquant peut être
détournée pour appeler des objets substitués.

Double parade :

- `SET search_path = 'schema', 'pg_catalog'` fixe le `search_path` pour chaque
  exécution, indépendamment du `search_path` de la session appelante.
- Tous les noms d'objets dans les corps de procédures sont entièrement qualifiés
  (`identity.entity`, `content.comment`, etc.) — seconde ligne de défense
  indépendante du `search_path`.

`marius_user` n'ayant pas de privilège `CREATE` sur les schémas applicatifs,
il ne peut pas y déposer d'objets substituts.

**Surcoût de performance** : le context switch de privilèges est de l'ordre de
quelques µs. `CREATE PROCEDURE` n'est jamais inlinable par le planner (contrairement
à `CREATE FUNCTION`), donc `SECURITY DEFINER` n'ajoute aucune régression.

### Rôles résultants

| Rôle           | SELECT | EXECUTE | INSERT/UPDATE/DELETE | Usage                             |
| -------------- | ------ | ------- | -------------------- | --------------------------------- |
| `marius_user`  | ✓      | ✓       | ✗                    | Runtime applicatif                |
| `marius_admin` | ✓      | ✓       | ✓                    | Maintenance, migrations, CI seed  |
| `postgres`     | ✓      | ✓       | ✓                    | Owner des objets, déploiement DDL |

---

## ADR-021 — Correctifs de cohérence : snapshot complet, verrou exclusif, trigger manquant

**Statut** : Adopté

### Contexte

Audit externe ayant produit 8 suggestions. Trois adressent des lacunes réelles ;
cinq sont écartées (voir analyse en fin d'entrée).

### Correction 1 — Snapshot complet dans `content.revision`

`content.save_revision()` et `content.create_document()` ne capturaient que
`name`, `slug` et `body`. Les colonnes `alternative_headline` et `description`
(portées par `content.identity`) n'étaient pas versionnées.

**Conséquence** : un `UPDATE` sur `alternative_headline` entre deux révisions
effaçait silencieusement la valeur précédente de l'historique. Le snapshot était
fonctionnellement faux sans aucun signal d'erreur.

**Correction** : deux colonnes ajoutées à `content.revision` :
`snapshot_alternative_headline VARCHAR(255)` et `snapshot_description VARCHAR(1000)`.
Les procédures `save_revision` et `create_document` les alimentent désormais.

La règle générale en découlant : **tout champ de `content.identity` éditable par
l'utilisateur doit avoir son équivalent `snapshot_*` dans `content.revision`**.

### Correction 2 — `FOR UPDATE` dans `create_transaction_item`

La procédure lisait `product_core` avec `FOR SHARE` (verrou partagé) avant de
décrémenter le stock. Deux transactions concurrentes sur le même produit pouvaient
lire simultanément `stock = 5`, vérifier la disponibilité, puis décrémenter
chacune — produisant un stock négatif (sur-vente).

`FOR SHARE` : plusieurs lecteurs simultanés autorisés → race condition possible.
`FOR UPDATE` : verrou exclusif sur la ligne → la seconde transaction attend la
fin de la première avant de lire le stock mis à jour.

**Correction** : `FOR SHARE` → `FOR UPDATE` sur le `SELECT price`.

**Note** : le `UPDATE commerce.product_core SET stock = stock - p_quantity`
qui suit opère sur la même ligne déjà verrouillée — pas de deadlock possible.

### Correction 3 — Trigger `modified_at` manquant sur `content.media_core`

`content.media_core` expose une colonne `modified_at TIMESTAMPTZ NULL` mais
n'avait pas de trigger pour la mettre à jour. Toutes les autres tables mutables
du schéma (`identity.auth`, `content.core`, `commerce.transaction`) en
disposaient.

**Correction** : trigger `BEFORE UPDATE` avec clause `WHEN` ciblant les colonnes
descriptives (`mime_type`, `folder_url`, `file_name`, `width`, `height`).

### Suggestions écartées

| # | Suggestion | Motif d'exclusion |
|---|---|---|
| 1 | Retry automatique dans `fn_slug_deduplicate` | Comportement intentionnel documenté dans le DDL : la contrainte `UNIQUE` est le garde-fou ; l'erreur 23505 est propre et attrapable côté applicatif. Ajouter un retry dans le trigger déplacerait la responsabilité du retry au mauvais niveau. |
| 4 | Remplacer `CHECK (path IS NOT NULL)` par `NOT NULL` | Déjà documenté en détail dans le DDL. Le `CHECK` est l'unique moyen de permettre `OVERRIDING SYSTEM VALUE` dans `create_comment` tout en rejetant les INSERT directs sans path. |
| 5 | B-tree complémentaire si BRIN inefficace | Déjà couvert en ADR-017 : la condition d'efficacité (insertions chronologiques) est documentée ; l'ajout d'un B-tree complémentaire est une décision opérationnelle à prendre sur données réelles, pas un invariant à inscrire dans le blueprint. |
| 7 | Partitionnement de `content.comment` et `content.revision` | Prématuré à l'échelle cible (500 k utilisateurs). PostgreSQL gère confortablement ces volumes avec les index existants. Le partitionnement ajoute de la complexité opérationnelle significative (maintenance des partitions, contraintes croisées) sans bénéfice mesurable à ce stade. |
| 8 | Suite de tests pgTAP | Hors périmètre du blueprint DDL. Pertinent comme étape CI/CD distincte. |

---

## ADR-005 — Fragmentation ECS : SoA en lieu de AoS

**Statut** : Adopté

### Décision

Chaque entité est fragmentée en tables physiques par fréquence d'accès :

```
Spine      → id pur, aucune donnée métier
Core       → champs hot path (status, dates clés, FK primaires)
Identity   → noms, slugs, données de listing
Contact    → email, téléphone, URL (accès contextuel)
Biography  → dates, lieux (accès rare)
Content    → textes longs (TOAST systématique, accès très rare)
```

### Justification

La densité de page détermine directement la quantité de données utiles résidente
en `shared_buffers`. Un tuple large charge des colonnes froides à chaque accès
chaud, comprimant inutilement le cache.

**Densités mesurées dans ce schéma** :

| Composant                   | Bytes/tuple | Tuples/page |
| --------------------------- | ----------- | ----------- |
| `identity.person_identity`  | ~74 B       | ~110        |
| `identity.auth`             | ~155 B      | ~51         |
| `identity.person_biography` | 44 B        | ~185        |
| `content.core`              | 64 B        | ~127        |

Un scan sur `person_identity` (listing d'auteurs) ne charge jamais les biographies
ni les textes longs, même si ces composants sont physiquement liés à la même entité.

**Coût accepté** : jointures supplémentaires sur les lectures complètes. Mitigé
par les vues sémantiques (ADR-006) qui masquent la fragmentation à la couche
applicative.

---

## ADR-019 — Spine polymorphe : absence de validation de sous-type au niveau moteur

**Statut** : Décision documentée (limite connue)

### Contexte

Plusieurs colonnes FK pointent vers `identity.entity` ou `org.entity` en
implicitant la présence d'un composant spécifique :

| Colonne FK                      | Table                   | Composant attendu          |
| ------------------------------- | ----------------------- | -------------------------- |
| `account_core.person_entity_id` | `identity.account_core` | `identity.person_identity` |
| `core.author_entity_id`         | `content.core`          | `identity.person_identity` |
| `org_core.contact_entity_id`    | `org.org_core`          | `identity.person_contact`  |

### Pourquoi l'intégrité de sous-type n'est pas portée par le moteur

Ajouter une FK `account_core.person_entity_id → person_identity(entity_id)`
rendrait le composant `person_identity` **obligatoire** pour toute entité
référencée comme personne d'un compte. Cela viole la sémantique ECS fondamentale :
**les composants sont optionnels par définition**. Le spine polymorphe perd son
intérêt si chaque référence impose l'existence du composant.

### Invariant effectif

La cohérence est garantie par les procédures d'écriture (ADR-020) :

- `identity.create_account()` crée systématiquement `entity + auth + account_core`
- `identity.create_person()` crée systématiquement `entity + person_identity`

Puisque l'écriture directe est révoquée pour `marius_user`, les procédures sont
les seuls points d'entrée. L'intégrité de sous-type est une **invariante
applicative**, pas une contrainte moteur.

### Alternative si une validation moteur est requise

```sql
CREATE FUNCTION identity.fn_check_person_entity()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.person_entity_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM identity.person_identity WHERE entity_id = NEW.person_entity_id
  ) THEN
    RAISE EXCEPTION 'entity_id % sans composant person_identity', NEW.person_entity_id;
  END IF;
  RETURN NEW;
END;
$$;
```

Non implémenté : coût d'un SELECT supplémentaire à chaque INSERT sur `account_core`,
injustifié dès lors qu'ADR-020 est en place.

---

## ADR-012 — Procédure `content.create_comment()` : zéro dead tuple structurel

**Statut** : Adopté

### Problème à résoudre

La construction du chemin `ltree` requiert l'`id` du commentaire, alloué par
`GENERATED ALWAYS AS IDENTITY` seulement après l'INSERT. Toute approche fondée
sur un trigger AFTER génère un UPDATE immédiat sur la ligne insérée.

Sous MVCC, un UPDATE crée une version morte (dead tuple) : la version v1 est
marquée `xmax` et reste sur le heap jusqu'au prochain autovacuum. La colonne
`path` étant couverte par deux index (GiST + B-tree composite), HOT est impossible
— chaque INSERT produit deux entrées d'index et un dead tuple garanti.

### Mécanisme retenu

```
1. nextval(sequence)  →  id alloué en mémoire, avant toute écriture heap
2. SELECT path parent →  si commentaire enfant, FOR SHARE pour stabilité
3. Construction ltree  →  chemin complet assemblé en PL/pgSQL
4. INSERT unique       →  OVERRIDING SYSTEM VALUE, chemin définitif, zéro dead tuple
```

### Justification

- Une seule écriture heap par commentaire → zéro dead tuple structurel.
- Une seule entrée par index (GiST + B-tree) au lieu de deux.
- `nextval()` est transactionnel : les gaps de séquence en cas de rollback
  sont identiques au comportement `GENERATED ALWAYS` standard.
- La procédure est le seul point d'entrée autorisé (ADR-020), ce qui garantit
  l'invariant sans trigger de contrôle supplémentaire.

---

## ADR-015 — `fillfactor` réduit sur les tables à mises à jour fréquentes

**Statut** : Adopté

### Décision

| Table                   | fillfactor | Colonne mise à jour fréquemment         |
| ----------------------- | ---------- | --------------------------------------- |
| `identity.auth`         | 70         | `last_login_at` (chaque connexion)      |
| `commerce.product_core` | 80         | `stock` (chaque vente)                  |
| `content.core`          | 75         | `status`, `modified_at` (cycle de vie)  |

### Justification

Un `fillfactor < 100` réserve de l'espace libre dans chaque page heap. Un UPDATE
dont la nouvelle version tient dans cet espace devient un **HOT update**
(Heap-Only Tuple) : aucune nouvelle entrée d'index n'est créée, la chaîne HOT
est maintenue dans la même page.

**Condition HOT** : la colonne modifiée ne doit être couverte par aucun index.

- `last_login_at` : non indexé → HOT garanti.
- `stock` : non indexé → HOT garanti.
- `status` : non indexé directement. L'index partiel `core_published` couvre
  `status = 1` ; un UPDATE `0→1` crée une entrée, `1→2` n'en crée pas.

**Coût** : `(100 - fillfactor) %` de pages physiques supplémentaires.
Sur `identity.auth` (fillfactor 70), +43 % de pages disque. Acceptable au regard
de l'élimination du bloat sur une table mise à jour 500 000 fois/jour.

---

## ADR-016 — Isolation agressive du TOAST (`toast_tuple_target = 128`)

**Statut** : Adopté

### Décision

`toast_tuple_target = 128` sur toutes les tables portant des textes longs :
`content.body`, `content.revision`, `geo.place_content`, `commerce.product_content`,
`identity.person_content`.

`content.body.content` est de plus configuré en `STORAGE EXTENDED`
(compression LZ4 + externalisation TOAST).

### Justification

Le seuil TOAST par défaut (~2 Ko) est un compromis généraliste. Avec
`toast_tuple_target = 128`, PostgreSQL externalise toute varlena dépassant le
budget de 128 bytes dans la table TOAST associée. Dans le tuple principal, seul
un pointeur TOAST de 18 bytes subsiste.

**Conséquence directe** : `SELECT` sur `content.v_article_list` (qui ne projette
pas `articleBody`) ne déclenche **aucun** accès à la table TOAST. PostgreSQL ne
résout le pointeur TOAST que si la colonne figure dans la liste de projection.

Les composants hot path (`content.core`, `content.identity`) restent denses
indépendamment du volume de contenu stocké dans `content.body`.

---

## ADR-017 — Index BRIN sur les colonnes temporelles à progression monotone

**Statut** : Adopté

### Décision

Index BRIN en lieu d'un index B-tree sur toutes les colonnes `created_at` à
progression chronologique.

| Table                  | Index                      | pages_per_range |
| ---------------------- | -------------------------- | --------------- |
| `identity.auth`        | `auth_created_at_brin`     | 128             |
| `content.core`         | `core_created_brin`        | 128             |
| `commerce.transaction` | `transaction_created_brin` | 128             |
| `org.org_core`         | `org_core_created_brin`    | 64              |

### Justification

**Définition BRIN** : stocke, pour chaque plage de N blocs physiques consécutifs,
les valeurs min et max de la colonne. Efficace uniquement si la corrélation entre
ordre d'insertion et ordre des valeurs est forte — ce qui est exact pour
`created_at` (insertions chronologiques).

**Gain RAM** : sur `identity.auth` à 500 000 lignes, un B-tree occupe ~11 Mo en
`shared_buffers`. Le BRIN équivalent : ~50 Ko. Le delta (~10 Mo) reste disponible
pour les pages heap à haute densité.

**Compromis accepté** : la recherche ponctuelle par date exacte est moins précise
(le BRIN indique quels blocs sont candidats, pas quelle ligne). Acceptable car
ces requêtes sont rares (analytics, audit). Les listings chronologiques sont
couverts par les index partiels sur `published_at` et `status`.

---

## ADR-004 — Layout physique décroissant (règle universelle)

**Statut** : Adopté

### Décision

Ordre de déclaration systématique dans toutes les tables :

```
8 bytes  →  TIMESTAMPTZ, FLOAT8, INT8
4 bytes  →  INT4, DATE, FLOAT4
2 bytes  →  SMALLINT
1 byte   →  BOOLEAN
variable →  CHAR, VARCHAR, TEXT, NUMERIC, ltree, geometry
```

### Justification

PostgreSQL aligne chaque colonne sur un multiple de son `typalign`. Un type de
petite taille suivi d'un type de grande taille génère du **padding invisible** :
bytes non utilisés insérés automatiquement pour satisfaire l'alignement du type
suivant. Ce padding est permanent et invisible dans `\d`.

`NUMERIC` est varlena dans PostgreSQL quelle que soit la précision déclarée
(`NUMERIC(12,2)` inclus). Il va systématiquement après les types fixes.

**Exemples dans ce schéma** :

| Table                      | Économie/tuple |
| -------------------------- | -------------- |
| `identity.auth`            | 12 B           |
| `identity.person_identity` | 14 B           |
| `identity.role`            | 2 B            |

---

## ADR-003 — Bitmask `INT4` pour les permissions de rôle

**Statut** : Adopté

### Décision

Les 15 permissions du système sont encodées dans une colonne `permissions INT4`
unique, par OR binaire des puissances de 2.

### Arbitrage entre les types candidats

| Type     | Taille   | Contrainte                                               |
| -------- | -------- | -------------------------------------------------------- |
| `BIT(n)` | varlena  | 4 bytes d'en-tête + données ; opérateurs moins naturels  |
| `INT2`   | 2 bytes  | Bit 15 = bit de signe ; toute 16e permission déborde     |
| `INT4`   | 4 bytes  | 17 bits libres pour extensions ; `&`, `\|`, `~` natifs   |

### Justification

`INT4` : alignement natif sur 4 bytes (déclaré à offset 0 dans `identity.role`,
zéro padding), opérateurs bitwise standard lisibles, 17 bits libres pour
extensions futures sans migration de type.

**Gain en CPU tuple deforming** : un accès à `permissions` est un seul appel
`slot_getattr()`. Pertinent sur le hot path d'authentification.

---

## ADR-006 — Vues sémantiques comme seule interface de lecture

**Statut** : Adopté

### Décision

La couche applicative ne connaît que les vues. Les tables physiques sont un
détail d'implémentation invisible au-dessus de la fragmentation ECS.

```
Tables physiques  →  Composants ECS (optimisés pour la densité)
Vues SQL          →  Interface schema.org (stable, nommage sémantique)
```

### Justification

La fragmentation ECS (ADR-005) produit un modèle physique opaque. Les vues
reconstituent l'objet complet (`v_person`, `v_account`) en masquant les jointures.

**Découplage physique/logique** : un remaniement interne des composants (split
d'une table, changement de layout) ne casse pas l'interface API tant que la vue
est maintenue. Le contrat nommé (`"givenName"`, `"datePublished"`, `"gtin13"`)
est stable.

**Séparation listing/page complète** : `content.v_article_list` projette
uniquement les colonnes hot path (zéro TOAST). `content.v_article` projette
en plus `content.body` (accès TOAST). Cette séparation est **architecturalement
garantie** — il est impossible de charger accidentellement les corps HTML lors
d'un listing, quelle que soit la requête applicative.

---

## ADR-018 — Agrégation JSON dans les vues pour éliminer le N+1

**Statut** : Adopté

### Décision

Les relations N:N (tags, médias, lignes de commande) sont agrégées directement
dans le moteur via `json_agg()` + `json_build_object()` depuis les vues
sémantiques `content.v_article` et `commerce.v_transaction`.

### Justification

Sans agrégation moteur, la couche applicative effectue une requête principale
+ N requêtes secondaires. Pour 3–20 éléments liés, le coût CPU de `json_agg`
est systématiquement inférieur au coût cumulé des aller-retours réseau
(1–5 ms/requête en LAN, 10–50 ms en WAN).

La base de données livre un objet JSON directement désérialisable. L'applicatif
n'orchestre aucune jointure secondaire.

**Limites documentées** :

- `commerce.v_transaction` sans `WHERE` force une agrégation complète sur
  l'ensemble des transactions. Toujours filtrer par `id` ou `client_entity_id`.
- `v_tag_tree."articleCount"` est une sous-requête corrélée réévaluée pour
  chaque tag. Acceptable jusqu'à ~1 000 tags ; à matérialiser au-delà.

---

## ADR-011 — `ltree` pour les hiérarchies de tags et commentaires

**Statut** : Adopté

### Comparaison des patterns hiérarchiques

| Critère             | Adjacency List                | Nested Set                  | ltree                  |
| ------------------- | ----------------------------- | --------------------------- | ---------------------- |
| Lecture sous-arbre  | O(profondeur) — CTE récursive | O(1) — BETWEEN              | O(log n) — index GiST  |
| INSERT              | O(1)                          | O(n) — recalcul intervalles | O(1) — concat chemin   |
| Lisibilité du chemin| `parent_id = 42`              | `lft=5, rgt=12`             | `theology.patristics`  |
| Index disponible    | B-tree sur `parent_id`        | B-tree sur `lft`/`rgt`      | GiST (`@>`, `<@`, KNN) |

### Justification

**Tags** : la lecture de sous-arbres est le pattern dominant. `ltree` + index
GiST résout en O(log n) sans CTE récursive. Les insertions sont rares.

**Commentaires** : le pattern dominant est l'affichage d'un thread complet
(opérateur `<@`). ltree résout en O(log n). L'INSERT est O(1) — critique sous
concurrence.

Le Nested Set est écarté pour les commentaires : son INSERT est O(n) et requiert
un verrouillage de table pour recalculer les intervalles. Incompatible avec une
table à insertions concurrentes.

La procédure `content.create_comment()` (ADR-012) construit le chemin en mémoire
avant l'INSERT unique, sans aucun UPDATE post-insertion.

---

## ADR-002 — Spine `content.document` indépendant de `identity.entity`

**Statut** : Adopté

### Arbitrage

| Option                            | Avantage               | Inconvénient                                    |
| --------------------------------- | ---------------------- | ----------------------------------------------- |
| Spine partagé (`identity.entity`) | Un seul registre d'IDs | Mélange volumétrique, cascades croisées         |
| Spine dédié (`content.document`)  | Isolation complète     | Un registre supplémentaire                      |

### Justification

1. **Sémantique** : un document n'est pas un acteur. Un spine partagé introduit
   des jointures à vide sur 100 % des requêtes documentaires.

2. **Volumétrie asymétrique** : 500 000 utilisateurs vs potentiellement plusieurs
   millions de documents et révisions. Un spine partagé dégraderait les index
   B-tree du registre des acteurs.

3. **Cascade isolée** : `DELETE CASCADE` sur un document ne doit pas traverser
   le registre des acteurs.

4. **Polymorphisme documentaire** : `content.document` porte `doc_type`
   (article, page, billet, newsletter) sans impact sur `identity`.

---

## ADR-008 — Spines `org.entity` et `geo.place_core` : stratégies distinctes

**Statut** : Adopté

### Décision

- `org.entity` : spine dédié (même pattern que `identity.entity`).
- `geo.place_core` : PK `INT` directe sur la table, pas de spine séparé.

### Justification

**`org.entity`** : les organisations peuvent avoir des contacts, des membres et
des permissions futures. Un spine dédié permet les mêmes extensions que
`identity.entity` sans couplage croisé.

**`geo.place_core`** : les lieux sont des destinations (FK cibles depuis `org`,
`identity`, `commerce`), pas des acteurs. Un spine séparé ajouterait une jointure
sur 100 % des requêtes géospatiales sans bénéfice sémantique. Le PK direct est
le niveau d'abstraction adéquat.

---

## ADR-007 — Schémas PostgreSQL pour l'isolation des domaines

**Statut** : Adopté

### Décision

Cinq schémas dédiés : `identity`, `geo`, `org`, `commerce`, `content`.

### Justification

La raison première n'est pas la lisibilité mais **l'isolation des permissions** :
`GRANT USAGE ON SCHEMA content TO editorial_service` expose uniquement le domaine
éditorial, sans aucun accès à `identity` ou `commerce`. Sans schémas, toute
granularité fine de `GRANT` nécessite un `GRANT` table par table dans `public`.

Corollaire : le `search_path` est configurable par rôle de connexion, permettant
l'isolation par service applicatif sans configuration supplémentaire côté
application.

---

## ADR-013 — `GENERATED ALWAYS AS IDENTITY` sur toutes les PK

**Statut** : Adopté

### Arbitrage entre les options d'identité

| Option                 | Taille | Remarque                                                        |
| ---------------------- | ------ | --------------------------------------------------------------- |
| UUID v4                | 16 B   | Pertinent multi-nœuds ; pénalisant sur les tables de liaison N:N |
| `SERIAL`               | 4 B    | Syntaxe propriétaire, dépréciée depuis PG 10                    |
| `GENERATED BY DEFAULT` | 4 B    | Permet les INSERT explicites sans `OVERRIDING SYSTEM VALUE`     |
| `GENERATED ALWAYS`     | 4 B    | Interdit les INSERT explicites — cohérent avec ADR-020          |

### Justification

`GENERATED ALWAYS` renforce le verrou d'ADR-020 au niveau de la séquence :
même `marius_admin` doit passer par `OVERRIDING SYSTEM VALUE` pour forcer un
id. Cela signale explicitement toute insertion hors procédure dans le code source.

UUID est écarté pour les tables de liaison N:N : deux `INT4` en PK composée
= 8 bytes. Deux UUID = 32 bytes. L'impact sur les index et la densité de page
est direct sur les tables à forte volumétrie (`content_to_tag`, `transaction_item`).

---

## ADR-014 — `NUMERIC(12,2)` pour tous les montants monétaires

**Statut** : Adopté

### Justification

`FLOAT8` introduit des erreurs d'arrondi binaire sur les représentations
décimales exactes (`0.1 + 0.2 ≠ 0.3`). Inacceptable pour des montants financiers
archivés dans `unit_price_snapshot` — le prix capturé doit être exact et stable.

`NUMERIC` sans précision produit un stockage variable non contrôlé.

`NUMERIC(12,2)` : précision décimale exacte, plage jusqu'à 9 999 999 999,99
(~10 Md€), stockage interne de 6–8 bytes pour les montants courants.

---

## ADR-009 — Table `commerce.transaction_item` : résolution 1NF

**Statut** : Adopté

### Décision

Les lignes de commande sont une table dédiée :
`commerce.transaction_item(transaction_id, product_id, quantity, unit_price_snapshot)`.

### Justification

Une liste d'identifiants sérialisée en colonne varchar rend impossible toute FK
référentielle, tout agrégat par produit et tout historique de prix. Le champ
`unit_price_snapshot NUMERIC(12,2)` capture le prix au moment de l'INSERT : le
prix courant peut évoluer sans altérer l'historique des commandes passées.

`quantity INT4` (et non `SMALLINT`) : SMALLINT max = 32 767. Les commandes B2B
peuvent dépasser ce volume. INT4 couvre jusqu'à ~2,1 milliards.

---

## ADR-010 — Typage `CHAR(9)` / `CHAR(14)` pour DUNS et SIRET

**Statut** : Adopté

### Justification

DUNS (9 chiffres) et SIRET (14 chiffres) sont des identifiants non arithmétiques :
**les zéros initiaux sont significatifs**. Un type entier les perd silencieusement.
`VARCHAR` n'impose pas la longueur fixe. `CHAR(n)` est le seul type garantissant
longueur fixe et conservation des zéros initiaux.

Validation par contrainte CHECK avec regex (`'^[0-9]{9}$'`, `'^[0-9]{14}$'`) :
coût fixe à l'INSERT, zéro coût à la lecture, pas de trigger.

---

## ADR-001 — Séparation DDL / DML

**Statut** : Adopté

Deux artefacts distincts :

- `master_schema_ddl.pgsql` — Blueprint immuable, idempotent, versionnable seul.
- `master_schema_dml.pgsql` — Seed data, dev/CI uniquement, jamais exécuté en
  production.

**Exception** : les `INSERT` sur `identity.permission_bit` et `identity.role`
restent dans le DDL — données de configuration structurelle insécables du schéma
au même titre que les `REVOKE` qui les suivent.

---

## Récapitulatif des densités

| Table                       | Bytes/tuple | Tuples/page |
| --------------------------- | ----------- | ----------- |
| `content.document`          | 32 B        | ~255        |
| `content.core`              | 64 B        | ~127        |
| `content.content_to_tag`    | 32 B        | ~255        |
| `identity.role`             | 49 B        | ~167        |
| `identity.auth`             | ~155 B      | ~51         |
| `identity.person_identity`  | ~74 B       | ~110        |
| `identity.person_biography` | 44 B        | ~185        |
| `org.org_hierarchy`         | 40 B        | ~204        |
| `commerce.transaction_item` | 44 B        | ~186        |
| `geo.place_core` (minimal)  | 61 B        | ~134        |

---

*Architecture ECS/DOD · PostgreSQL 18 · Projet Marius · 21 décisions*
