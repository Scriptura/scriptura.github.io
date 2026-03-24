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

## ADR-025 — Interface sémantique snake_case : schema.org sans guillemets SQL

**Statut** : Adopté

### Contexte

Les vues sémantiques exposaient des alias camelCase entre guillemets doubles
(`"givenName"`, `"datePublished"`, `"@type"`). Cette convention crée trois
frictions opérationnelles :

1. **Guillemets obligatoires dans toute requête SQL** : `SELECT "givenName" FROM
   identity.v_person` — l'oubli d'un guillemet provoque une erreur silencieuse
   (colonne non trouvée, ou pire : résolution vers une colonne système).
2. **Caractère `@` illégal** comme identifiant SQL nu : `"@type"` ne peut jamais
   être utilisé sans guillemets.
3. **Friction avec les ORM et drivers** : la majorité des drivers (psycopg3, JDBC,
   node-postgres) retournent les colonnes en minuscules par défaut, ce qui force
   soit des mappings explicites, soit des guillemets systématiques.

### Décision

Toutes les vues sémantiques utilisent désormais le **snake_case PostgreSQL natif**,
sans guillemets. Le vocabulaire schema.org est préservé dans les noms de colonnes
par translittération directe : `givenName → given_name`, `datePublished →
published_at`, `articleBody → article_body`.

### Règles de translittération

| Règle | Exemple schema.org | Alias vue |
| ----- | ------------------ | --------- |
| camelCase → snake_case | `givenName` | `given_name` |
| Suffixe `_at` pour TIMESTAMPTZ | `datePublished` | `published_at` |
| Suffixe `_cents` pour INT8 monétaire | `price` | `price_cents` |
| Suffixe `_id` pour FK | `authorId` | `author_id` |
| Suffixe `_code` pour codes numériques | `currencyCode` | `currency_code` |
| Miroir du nom physique quand identique | `is_readable` | `is_readable` (pas `is_accessible_for_free`) |
| `@type` → `doc_type` / `org_type` | `@type` | `doc_type`, `org_type` |

### Exceptions documentées — refus de `address_country` pour `country_code`

La suggestion d'aliaser `country_code` en `address_country` est refusée.
`address_country` évoque une valeur textuelle ("France"), alors que le type
physique est `SMALLINT` contenant un code ISO 3166-1 numérique (250).
Un alias trompeur sur le type crée des erreurs de comparaison applicatives
(`WHERE address_country = 'FR'` ne fonctionnerait pas sur un SMALLINT).
Le nom `country_code` est conservé dans la table et dans la vue — il est
auto-documenté : "c'est un code, pas un nom de pays".

### Colonne `content.identity.name` → `headline`

Renommage du nom physique, pas seulement de l'alias. `name` est ambigu dans
le contexte d'un article (est-ce le titre, le nom de fichier, le nom d'auteur ?).
`headline` est le terme exact schema.org/Article. Le renommage s'étend à
`content.revision.snapshot_name → snapshot_headline` pour la cohérence du
composant de versioning.

### Colonnes `org.org_legal`

`vat_number → vat_id` : le suffixe `_id` signale un identifiant externe (non
une valeur calculée). Cohérent avec `duns` et `siret`. Ajout de `legal_name
VARCHAR(128)` : raison sociale officielle, distincte du nom commercial dans
`org.org_identity.name`.

### Impact applicatif

Les consommateurs existants de l'API doivent adapter leurs sélections :
`"givenName"` → `given_name`, `"headline"` → `headline` (idem), etc. Ce
changement est une rupture de contrat intentionnelle, effectuée en phase R&D
avant toute mise en production.

---

## ADR-024 — Fragmentation geo, soft delete RGPD et compliance de production

**Statut** : Adopté

### Contexte

Quatre vecteurs de risque identifiés avant mise en production européenne :

1. `geo.place_core` mélange spine spatial (coordonnées KNN) et adresse postale (logistique).
2. `org.org_legal.vat_number VARCHAR(15)` trop court pour les identifiants fiscaux internationaux.
3. Absence de mécanisme de droit à l'oubli (RGPD art. 17) et de traçabilité du consentement.
4. Absence de mention de droits dans les métadonnées médias (risque légal d'exploitation d'images).

---

### 1. Séparation `geo.place_core` / `geo.postal_address` (ECS spatial vs logistique)

**Problème** : `geo.place_core` mixait coordonnées GPS et adresse postale dans le même tuple.
Les requêtes géospatiales (KNN `<->`, `ST_DWithin`) ne nécessitent que `id + coordinates`,
mais chargeaient systématiquement `street`, `locality`, `region`, `country`, `postal_code`.

**Décision** : fragmentation en deux composants 1:1 :

| Composant           | Sémantique schema.org  | Contenu                                     | Fréquence |
| ------------------- | ---------------------- | ------------------------------------------- | --------- |
| `geo.place_core`    | `Place`                | id, name, elevation, type_id, coordinates   | Hot       |
| `geo.postal_address`| `PostalAddress`        | country_code, locality, region, street, postal_code | Warm |

**Gain de densité** :

| État         | Bytes/tuple | Tuples/page |
| ------------ | ----------- | ----------- |
| Avant (mixte)| ~211 B      | ~38         |
| Après (spine)| ~26–46 B    | ~179–317    |

Les requêtes KNN sur 500 000 lieux ne chargent plus aucun octet postal.

**`country_code SMALLINT` (ISO 3166-1 numérique)** : cohérent avec `currency_code`
d'ADR-022. 2 bytes pass-by-value vs `CHAR(2)` ou `VARCHAR(2)` varlena avec en-tête
de 4 bytes. Le mapping vers le code alphabétique (`250 → "FR"`) est délégué à
l'applicatif — table de lookup statique, zéro accès base de données.

---

### 2. `vat_number VARCHAR(32)` (compliance internationale)

`VARCHAR(15)` couvrait les numéros TVA européens (max 15 chars incluant le préfixe
pays). Les identifiants fiscaux hors UE (GSTIN indien 15 chars avec format strict,
CNPJ brésilien 18 chars avec ponctuation, CFE mexicain 13 chars) nécessitent
davantage de marge. `VARCHAR(32)` absorbe tous les formats connus sans coût physique
(varlena : seul le contenu réel est stocké).

---

### 3. Soft delete RGPD : `anonymized_at` + procédure `anonymize_person`

**Problème** : un `DELETE` physique d'une entité casserait les FK vers
`commerce.transaction_core` — les commandes passéesdeviendraient incohérentes.
Une suppression logicielle par colonne booléenne (`is_deleted`) serait ambiguë
et difficile à auditer.

**Décision** : colonne `anonymized_at TIMESTAMPTZ NULL` dans `identity.entity` (spine).

- `NULL` = entité active.
- Non-NULL = anonymisation exécutée, timestamp d'audit RGPD irréversible.

La procédure `identity.anonymize_person(p_entity_id)` (SECURITY DEFINER) efface
en une transaction atomique :

| Composant                  | Action                                             |
| -------------------------- | -------------------------------------------------- |
| `identity.entity`          | `anonymized_at = now()`                            |
| `identity.person_identity` | Tous les champs nominatifs → NULL                  |
| `identity.person_contact`  | email, phone, fax, url → NULL                      |
| `identity.person_biography`| Dates et lieux → NULL                              |
| `identity.person_content`  | Textes personnels → NULL, media_id → NULL          |
| `identity.account_core`    | username/slug → `user_<id>` (non nominatif)        |
| `identity.auth`            | password_hash → `'ANONYMIZED'`, is_banned → true   |
| `identity.group_to_account`| Suppression (appartenance = donnée de traçabilité) |

L'entité physique subsiste dans `identity.entity` avec son `id` — toutes les FK
`commerce.transaction_core.client_entity_id` restent valides.

**`tos_accepted_at TIMESTAMPTZ NULL`** dans `identity.account_core` : timestamp
d'acceptation des CGU. NULL = non encore accepté. Placé en première colonne
(TIMESTAMPTZ 8 bytes, ADR-004) pour zéro padding.

---

### 4. `copyright_notice VARCHAR(255)` dans `content.media_content`

Placé dans `media_content` (cold path, BASSE fréquence) et non dans `media_core`
(hot path, HAUTE fréquence). Un `SELECT` sur les listings d'articles ne charge
jamais la mention de droits — elle n'est projetée que lors de l'affichage complet
d'un média ou de la génération d'une page légale.

---

## ADR-023 — Éclatement de l'agrégat de commande en composants ECS 1:1

**Statut** : Adopté

### Contexte

Un système de commande réel nécessite des données de natures radicalement
différentes : statut d'exécution (hot, consulté à chaque affichage), données
financières (warm, consultées à la confirmation et à la facturation), informations
de livraison (cold, consultées après expédition). Les stocker dans une table
unique pollue systématiquement le cache CPU avec des données froides lors de
chaque accès chaud.

### Décision

L'entité commande est décomposée en quatre composants denses, reliés par la
même clé primaire (`transaction_id`) :

| Composant                   | Sémantique schema.org             | Fréquence d'accès |
| --------------------------- | --------------------------------- | ----------------- |
| `transaction_core`          | `Order`                           | Très haute        |
| `transaction_price`         | `PriceSpecification`              | Haute             |
| `transaction_payment`       | `PaymentChargeSpecification`      | Moyenne           |
| `transaction_delivery`      | `ParcelDelivery`                  | Basse             |
| `transaction_item`          | `OrderItem` (N lignes)            | Haute             |

Chaque composant est une relation 1:1 stricte (PK = FK vers `transaction_core`).

### Justification — cache CPU et densité

L'argument "éviter une jointure" en faveur d'une fat table repose sur un coût
mal évalué. Une jointure sur clé primaire entière (`INT4`) est un déréférencement
mémoire trivial sur une ligne déjà en cache — coût de l'ordre de quelques
nanosecondes. La pollution de cache par des colonnes froides a un coût
structurellement récurrent :

- `tracking_number VARCHAR(255)` dans `transaction_core` gonfle chaque tuple
  d'au moins 4 bytes d'en-tête varlena, plus le contenu. Sur 500 000 commandes,
  un champ non nul de 20 chars ajoute ~12 Mo de bruit sur le heap du composant core.
- Ce bruit réduit mécaniquement le nombre de tuples par page cache, augmentant
  les shared_blks_hit nécessaires pour chauffer le working set.

Avec la décomposition, `transaction_core` tient en **32 bytes/tuple** (~258
tuples/page). L'affichage du statut de toutes les commandes d'un client ne charge
jamais le transporteur ni le numéro de facture.

### Arbitrages typologiques (DOD)

**`currency_code SMALLINT`** (2 bytes, pass-by-value) plutôt que `CHAR(3)`
(varlena avec padding) ou `VARCHAR(3)` (varlena). Le code ISO 4217 numérique
(978 = EUR, 840 = USD, 826 = GBP) couvre l'ensemble des devises actives.
Le mapping vers le code alphabétique est délégué à la couche applicative — c'est
une simple table de lookup statique, jamais un accès base de données.

**`tax_rate_bp INT4`** (4 bytes, pass-by-value) plutôt que `NUMERIC(5,2)`
(varlena, arithmétique logicielle). Le taux est stocké en **basis points**
(1 bp = 0,01%). Exemples : 2000 = 20,00% · 550 = 5,50%. L'arithmétique entière
ALU native remplace l'émulation NUMERIC : `(amount_cents * tax_rate_bp) / 10000`
reste dans les registres CPU.

**Tous les montants en `INT8` centimes** (ADR-022) : `shipping_cents`,
`discount_cents`, `tax_cents` suivent la même règle que `price_cents`. Pas de
NUMERIC dans le hot path financier.

### Procédure `create_transaction`

La procédure crée atomiquement les quatre composants : `transaction_core` +
`transaction_price` (devise + montants à zéro) + `transaction_payment` (statut 0)
+ `transaction_delivery` (statut 0). **Il n'existe jamais de transaction_core sans
ses trois composants** — l'invariant est garanti par l'atomicité de la transaction.
Les composants sont mis à jour indépendamment au fil du cycle de vie de la commande.

### Relation avec les autres ADR

- ADR-005 (fragmentation ECS) : même pattern appliqué au domaine Commerce.
- ADR-022 (INT8 centimes) : invariant étendu à tous les montants de `transaction_price`.
- ADR-020 (SECURITY DEFINER) : `create_transaction` est la seule procédure
  d'écriture autorisée pour `marius_user` sur `transaction_core` et ses composants.

---

## ADR-022 — Optimisations CPU/mémoire : entiers natifs, VARCHAR, padding documenté, pushdown

**Statut** : Adopté

### Contexte

Audit DOD ciblé sur les composants chauds (`commerce.product_core`,
`commerce.transaction_item`, `org.org_legal`, `identity.auth`,
`commerce.v_transaction`). Quatre ajustements de topologie physique.

### 1. NUMERIC → INT8 centimes (commerce)

Voir ADR-014 pour le raisonnement complet. Résumé :

- `NUMERIC` est varlena → padding d'alignement, tuple deforming indirect, arithmétique logicielle.
- `INT8` est pass-by-value, aligné sur 8 bytes, arithmétique ALU native.
- Gain de densité : ×2 sur `product_core` (24 B/tuple), ×2,2 sur `transaction_item` (20 B/tuple).
- Convention de nommage : suffixe `_cents` visible dans les noms de colonnes et dans les alias de vues.

### 2. `CHAR(n)` → `VARCHAR(n)` (org.org_legal, commerce.product_identity)

`CHAR(n)` dans PostgreSQL est varlena comme `VARCHAR(n)`. La seule différence est
le padding espace sur écriture et le stripping sur lecture : **surcoût CPU sans
contrepartie**. Les contraintes CHECK avec regex garantissent la longueur exacte et
la conservation des zéros initiaux — `VARCHAR(n)` est strictement suffisant.

Correction étendue à `isbn_ean VARCHAR(13)` dans `commerce.product_identity` pour
la même raison (était `CHAR(13)`).

### 3. Slot de padding libre dans `identity.auth` — documentation

Séquence de types en fin de tuple fixe de `identity.auth` :
```
role_id   SMALLINT  (2 B, offset 28)
is_banned BOOLEAN   (1 B, offset 30)
[padding] —         (1 B, offset 31)  ← slot libre
password_hash varlena               (offset 32, alignement 4 B)
```

Ce byte de padding est structurellement inévitable : la varlena `password_hash`
requiert un alignement sur 4 bytes, et la séquence SMALLINT + BOOLEAN consomme
3 bytes. Le slot à l'offset 31 est documenté comme **emplacement réservé pour un
prochain BOOLEAN** (ex : `is_email_verified`) sans coût marginal.

**Pourquoi pas le type interne `"char"`** : c'est un type système sans opérateurs
de domaine ni coercition standard. Il rend le schéma opaque pour tout DBA et
incompatible avec les outils standards. Pour les états fermés futurs, `SMALLINT`
avec `CHECK (status IN (...))` reste le bon choix.

### 4. Pushdown garanti sur `commerce.v_transaction` — documentation

PostgreSQL inline les vues avant planification : la vue n'est pas une barrière
d'optimisation. `WHERE "identifier" = :id` appliqué sur `v_transaction` se réécrit
en `WHERE t.id = :id` par le query rewriter avant que le planner n'intervienne.
`t.id` figure dans le GROUP BY — le prédicat est poussé avant `json_agg()`, l'index
PK est utilisé, l'agrégation porte sur les lignes de la commande concernée uniquement.

**Vérification recommandée** :
```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM commerce.v_transaction WHERE "identifier" = 1;
-- Attendu : Index Scan sur commerce.transaction (PK), pas de Seq Scan.
```

**Invariant d'usage** : `v_transaction` ne doit jamais être appelée sans filtre.
Un `SELECT *` sans `WHERE` agrège toutes les lignes de toutes les transactions.
Documenté dans la définition de la vue.

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

## ADR-014 — `INT8` centimes pour tous les montants monétaires

**Statut** : Adopté (révisé — ADR-022)

### Décision

Les montants monétaires (`price_cents` dans `product_core`,
`unit_price_snapshot_cents` dans `transaction_item`) sont stockés en **centimes
de la devise de référence** sous forme d'entier `INT8`. La conversion décimale
est déléguée à la couche applicative.

### Pourquoi pas NUMERIC

`NUMERIC` est varlena dans PostgreSQL sans exception, quelle que soit la précision
déclarée. Conséquences directes :

- **Padding d'alignement** : le moteur insère des bytes de remplissage entre les
  colonnes à taille fixe et l'en-tête varlena de NUMERIC. Ce padding est invisible
  dans `\d` et permanent.
- **Tuple deforming** : NUMERIC déclenche un appel indirect via parsing de l'en-tête
  varlena à chaque lecture de tuple, même pour une comparaison triviale.
- **Arithmétique** : les opérations sur NUMERIC sont émulées en base 10000 en
  logiciel. `unit_price * quantity` dans `v_transaction` ne touche pas l'ALU.

### Pourquoi INT8 et non INT4

INT4 max = 2 147 483 647 centimes ≈ 21,4 M€. Insuffisant pour les transactions
B2B (équipements industriels, licences). INT8 max ≈ 92 000 Md€. Le surcoût est
nul : INT8 est pass-by-value sur toutes les architectures 64 bits.

### Gain de densité

| Table                       | Avant (NUMERIC) | Après (INT8) | Tuples/page |
| --------------------------- | --------------- | ------------ | ----------- |
| `commerce.product_core`     | ~48 B           | 24 B         | ~341 (×2)   |
| `commerce.transaction_item` | ~44 B           | 20 B         | ~409 (×2,2) |

### Convention de nommage

Les colonnes suffixées `_cents` rendent l'invariant d'unité visible à tout lecteur
du schéma sans documentation supplémentaire. La vue expose le suffixe
(`"priceCents"`, `"unitPriceCents"`, `"totalPriceCents"`) pour que le contrat API
soit sans ambiguïté.

---

## ADR-009 — Table `commerce.transaction_item` : résolution 1NF

**Statut** : Adopté

### Décision

Les lignes de commande sont une table dédiée :
`commerce.transaction_item(unit_price_snapshot_cents, transaction_id, product_id, quantity)`.

### Justification

Une liste d'identifiants sérialisée en colonne varchar rend impossible toute FK
référentielle, tout agrégat par produit et tout historique de prix. Le champ
`unit_price_snapshot_cents INT8` capture le prix en centimes au moment de l'INSERT :
le prix courant peut évoluer sans altérer l'historique des commandes passées.

`quantity INT4` (et non `SMALLINT`) : SMALLINT max = 32 767. Les commandes B2B
peuvent dépasser ce volume. INT4 couvre jusqu'à ~2,1 milliards.

---

## ADR-010 — `VARCHAR(n)` pour DUNS, SIRET et ISBN/EAN

**Statut** : Adopté (révisé — ADR-022)

### Décision

Les identifiants de longueur fixe (`duns VARCHAR(9)`, `siret VARCHAR(14)`,
`isbn_ean VARCHAR(13)`) utilisent `VARCHAR(n)` et non `CHAR(n)`.

### Justification

`CHAR(n)` dans PostgreSQL est varlena au même titre que `VARCHAR(n)` — il n'offre
aucun stockage fixe. La seule différence opérationnelle est le **padding espace**
à l'écriture et le **stripping** à la lecture : surcoût CPU pur sans contrepartie
en densité ni en performance de recherche.

L'invariant de longueur exacte est garanti par les contraintes CHECK avec regex.
`VARCHAR(n)` avec CHECK est strictement équivalent en termes de validation, et
absent de tout overhead de padding.

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
| `commerce.product_core`     | 24 B        | ~341        |
| `commerce.transaction_item` | 20 B        | ~409        |
| `geo.place_core` (minimal)  | 61 B        | ~134        |

---

*Architecture ECS/DOD · PostgreSQL 18 · Projet Marius · 25 décisions*
