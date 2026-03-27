# Architecture Decision Records (ADR)

## Projet Marius — ECS/DOD · PostgreSQL 18

---

## ADR-001 — Interface d'écriture scellée : révocation DML globale et SECURITY DEFINER

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

L'invariant ECS posé par ADR-013 — les procédures sont les seuls points d'entrée
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

### Gardes d'autorisation dans les procédures SECURITY DEFINER

L'élévation de privilèges vers `postgres` contourne le RLS. Sans logique
d'autorisation interne, toute procédure est exécutable par n'importe quel
`marius_user` possédant `EXECUTE` — indépendamment de son rôle applicatif.

**Pattern de garde GUC** appliqué à chaque procédure sensible :

```sql
IF identity.rls_user_id() <> -1           -- GUC absent = contexte seed/admin : bypass
   AND (identity.rls_auth_bits() & <bit>) <> <bit> THEN
  RAISE EXCEPTION 'insufficient_privilege: <permission> required'
    USING ERRCODE = '42501';
END IF;
```

Le bypass sur `rls_user_id() = -1` est intentionnel : le seed CI/CD et les
sessions `marius_admin` directes n'injectent pas les GUC applicatifs. Leur accès
est contrôlé par ADR-001 au niveau du rôle, pas par les GUC.

| Procédure                          | Permission requise      | Complément                                                  |
| ---------------------------------- | ----------------------- | ----------------------------------------------------------- |
| `content.publish_document`         | `publish_contents` (16) | —                                                           |
| `content.create_document`          | `create_contents` (2)   | `p_author_id` = `rls_user_id()` sauf `edit_others_contents` |
| `content.save_revision`            | `edit_contents` (4)     | OU `edit_others_contents` (32768)                           |
| `content.create_tag`               | `manage_tags` (2048)    | —                                                           |
| `content.add_tag_to_document`      | `edit_contents` (4)     | OU `edit_others_contents` (32768) + ownership check         |
| `content.remove_tag_from_document` | `edit_contents` (4)     | OU `edit_others_contents` (32768) + ownership check         |
| `content.create_comment`           | `create_comments` (32)  | `p_account_entity_id` = `rls_user_id()`                     |
| `identity.anonymize_person`        | `manage_users` (256)    | Sauf auto-anonymisation (`p_entity_id` = `rls_user_id()`)   |
| `identity.grant_permission`        | `manage_users` (256)    | —                                                           |
| `identity.revoke_permission`       | `manage_users` (256)    | —                                                           |

| `org.create_organization` | `manage_system` (524288) | — |
| `org.add_organization_to_hierarchy` | `manage_system` (524288) | — |

| `commerce.create_transaction` | ownership `client_entity_id` = `rls_user_id()` | OU `manage_commerce` (262144) |
| `commerce.create_transaction_item` | ownership transaction + `manage_commerce` | statut `status=0` requis |

Procédures sans garde (accès ouvert à tout `marius_user` authentifié) :
`identity.create_account`, `identity.create_person`, `identity.record_login`.

**`content.ensure_tag` : non implémenté (rejet délibéré).** Un `ensure_tag` gardé
par `edit_contents` permettrait à tout auteur de créer des tags arbitrairement,
contournant le bit `manage_tags` que `create_tag` exige. La taxonomie est un
domaine structurel distinct de l'édition de contenu. Le workflow correct : les
tags sont créés en amont par les rôles `manage_tags` ; les auteurs lient les tags
existants via `add_tag_to_document`.

---

## ADR-002 — Row-Level Security stateless via GUC bitmask

**Statut** : Adopté

### Problème

Activer un filtrage de sécurité par ligne (RLS) sans déclencher de jointure sur
`identity.role` à chaque ligne évaluée. Avec un modèle traditionnel, chaque
évaluation de politique ferait `SELECT permissions FROM identity.role WHERE id = ...`
— un accès disque potentiel par ligne et par requête.

### Décision — Pattern GUC Stateless

Le middleware injecte deux variables de session PostgreSQL (GUC) avant toute requête :

```sql
SET LOCAL marius.user_id   = '<entity_id>';
SET LOCAL marius.auth_bits = '<bitmask INT4>';
```

Les politiques lisent ces GUC via deux fonctions helpers STABLE :

```sql
identity.rls_user_id()   → COALESCE(current_setting('marius.user_id',  true)::INT, -1)
identity.rls_auth_bits() → COALESCE(current_setting('marius.auth_bits', true)::INT,  0)
```

Le paramètre `true` de `current_setting` retourne NULL au lieu de lever une erreur
si le GUC n'est pas défini (connexion système, seed CI/CD). Le COALESCE garantit
le comportement fail-closed : `user_id = -1` ne correspond à aucune ligne,
`auth_bits = 0` désactive tous les bits.

**Coût d'évaluation** : une lecture de GUC de session (mémoire de processus) +
une opération bitwise `&`. O(1) inconditionnel, zéro accès disque.

**Fonctions STABLE** : PostgreSQL évalue une fonction STABLE une seule fois par
statement, pas une fois par ligne. Pour une requête retournant N lignes, les deux
GUC sont lus une seule fois.

### Tables RLS activées

| Table                       | Politiques SELECT                                       | Politiques UPDATE/DELETE       |
| --------------------------- | ------------------------------------------------------- | ------------------------------ |
| `content.core`              | publié OU publish_contents OU edit_others OU auteur     | propre contenu OU edit_others  |
| `commerce.transaction_core` | propre commande OU view_transactions OU manage_commerce | manage_commerce uniquement     |
| `identity.account_core`     | propre compte OU manage_users                           | propre compte OU manage_users  |
| `content.comment`           | approuvé OU auteur OU moderate_comments                 | aucune (pas de DML applicatif) |

### Interaction avec SECURITY DEFINER (ADR-001)

Les procédures s'exécutent en tant que `postgres` (superutilisateur), qui contourne
toujours le RLS. Ce comportement est **intentionnel** : les procédures implémentent
leur propre logique métier (ex : `create_document` écrit `author_entity_id` correctement)
et ne doivent pas être filtrées par des politiques conçues pour les lectures applicatives.

Le RLS sécurise le **chemin de lecture** (`marius_user` → `SELECT` sur vues).
Le chemin d'écriture est déjà sécurisé par l'absence de DML direct (ADR-001).

### marius_admin et BYPASSRLS

`marius_admin` est un rôle non-superutilisateur avec DML direct. Sans `BYPASSRLS`,
ses opérations de maintenance seraient bloquées par les politiques RLS. `GRANT
BYPASSRLS TO marius_admin` est ajouté en Section 14 — cohérent avec son rôle de
maintenance, distinct du chemin applicatif normal.

### Fermeture des accès directs par REVOKE SELECT (audit post-implémentation)

Un audit a identifié un gap structurel : `GRANT SELECT ON ALL TABLES` en Section 13
donnait à `marius_user` un accès direct aux tables physiques sensibles, contournant
les vues contrôlées. Le RLS sur 3 tables ne fermait pas ce vecteur.

Dix tables et une vue reçoivent un `REVOKE SELECT FROM marius_user` en Section 13 :

| Table                           | Données sensibles                        | Interface contrôlée                           |
| ------------------------------- | ---------------------------------------- | --------------------------------------------- |
| `identity.auth`                 | Hash argon2id, état de bannissement      | `identity.v_auth` (SECDEF)                    |
| `identity.person_contact`       | Email, téléphone, fax (PII RGPD)         | `identity.v_person`                           |
| `commerce.transaction_payment`  | Numéro de facture, méthode, ref. PSP     | `commerce.v_transaction`                      |
| `commerce.transaction_delivery` | Numéro de suivi logistique               | `commerce.v_transaction`                      |
| `commerce.transaction_price`    | Montants, devise, taux de taxe           | `commerce.v_transaction`                      |
| `commerce.transaction_item`     | Lignes de commande, prix snapshot        | `commerce.v_transaction`                      |
| `content.identity`              | Headline, slug, description de tous docs | `content.v_article_list`, `content.v_article` |
| `content.body`                  | Corps HTML complet de tous docs          | `content.v_article`                           |
| `content.revision`              | Snapshots éditoriaux complets            | `content.v_article`                           |
| `org.org_legal`                 | DUNS, SIRET, TVA — identifiants légaux   | `marius_admin` uniquement                     |
| `identity.v_auth` (vue)         | Hash argon2id via BYPASSRLS vue          | Middleware auth (postgres)                    |

**Deux mécanismes distincts, à ne pas confondre.**

`REVOKE SELECT` et RLS ne sont pas deux couches du même dispositif — ce sont deux
mécanismes de nature différente :

- **`REVOKE SELECT`** : suppression du privilège. PostgreSQL refuse l'accès avant
  même d'évaluer une requête. Le résultat est `42501` (insufficient_privilege).
  Aucun GUC, aucune politique, aucun contournement possible via une session
  `marius_user`. C'est une frontière d'accès, pas un filtre.

- **RLS** : filtrage par ligne sur des tables _auxquelles_ `marius_user` a `SELECT`.
  Le moteur évalue la politique pour chaque ligne candidate. Le résultat n'est pas
  une erreur — c'est un ensemble vide ou partiel. RLS présuppose l'existence du
  privilège SELECT ; il ne le remplace pas.

**Modèle à deux étages résultant :**

| Table                           | Mécanisme                | Comportement si `marius_user` accède directement |
| ------------------------------- | ------------------------ | ------------------------------------------------ |
| `identity.auth`                 | `REVOKE SELECT`          | Erreur 42501 — accès refusé                      |
| `identity.person_contact`       | `REVOKE SELECT`          | Erreur 42501 — accès refusé                      |
| `commerce.transaction_payment`  | `REVOKE SELECT`          | Erreur 42501 — accès refusé                      |
| `commerce.transaction_delivery` | `REVOKE SELECT`          | Erreur 42501 — accès refusé                      |
| `commerce.transaction_price`    | `REVOKE SELECT`          | Erreur 42501 — accès refusé                      |
| `commerce.transaction_item`     | `REVOKE SELECT`          | Erreur 42501 — accès refusé                      |
| `content.identity`              | `REVOKE SELECT`          | Erreur 42501 — accès refusé                      |
| `content.body`                  | `REVOKE SELECT`          | Erreur 42501 — accès refusé                      |
| `content.revision`              | `REVOKE SELECT`          | Erreur 42501 — accès refusé                      |
| `org.org_legal`                 | `REVOKE SELECT`          | Erreur 42501 — accès refusé                      |
| `identity.v_auth` (vue)         | `REVOKE SELECT`          | Erreur 42501 — accès refusé                      |
| `content.core`                  | RLS (politiques actives) | Résultat filtré selon GUC                        |
| `commerce.transaction_core`     | RLS (politiques actives) | Résultat filtré selon GUC                        |
| `identity.account_core`         | RLS (politiques actives) | Résultat filtré selon GUC                        |
| Toutes autres tables            | `SELECT` autorisé        | Accès complet (vues = interface recommandée)     |

**Note sur le security context des vues (ADR-003 invariant 2).**
Les vues Section 12 sont owned par `postgres` (BYPASSRLS). Le RLS sur les tables
Core n'est pas évalué sur le chemin de lecture via ces vues. Le filtre d'accès
est implémenté dans le WHERE de chaque vue concernée, via les helpers GUC. Le RLS
physique reste actif pour les accès directs aux tables Core (défense en profondeur).

**Conséquence pratique** : les tables et vues avec `REVOKE SELECT` n'ont pas de politique
RLS et n'en ont pas besoin — elles sont structurellement inaccessibles. Ajouter
du RLS dessus serait redondant et trompeur (laisserait croire que le RLS est le
mécanisme protecteur alors que c'est le REVOKE).

**Ordre de priorité des couches** :

1. **Révocation DML** (ADR-001) : `marius_user` ne peut pas écrire directement.
2. **Révocation SELECT ciblée** (Section 13) : fermeture totale sur les tables
   les plus sensibles — accès uniquement via leurs vues sémantiques.
3. **RLS stateless GUC** (Section 15) : filtrage par ligne sur les tables
   restantes accessibles en lecture directe.

### WITH CHECK explicite sur les politiques UPDATE

PostgreSQL hérite `WITH CHECK` de `USING` par défaut sur les politiques UPDATE.
Comportement correct aujourd'hui, mais implicite : un refactoring futur pourrait
changer `USING` sans réaliser que `WITH CHECK` suit. Toutes les politiques UPDATE
exposent désormais `WITH CHECK` explicitement — contrat rendu visible dans le DDL.

### Ce que le RLS ne remplace pas

Le RLS est la troisième couche de défense. Il ne remplace pas :

- La révocation DML sur `marius_user` (ADR-001) — première couche
- La révocation SELECT sur tables sensibles (Section 13) — deuxième couche
- La logique métier des procédures (ownership, transitions d'état)
- L'authentification applicative

### Politiques absentes

`INSERT` : `marius_user` n'a pas de droit `INSERT` sur ces tables (ADR-001).
Aucune politique INSERT nécessaire. Le DML seed s'exécute en tant que `postgres`
(bypass automatique).

---

## ADR-003 — RLS et fragmentation ECS : trois invariants de cohérence

**Statut** : Adopté

### Problème

Le pattern GUC Stateless (ADR-002) garantit un filtrage O(1) par ligne sur les
tables Core. Trois propriétés structurelles de PostgreSQL RLS, non déductibles
de la lecture du DDL seul, peuvent rendre ce filtrage inopérant ou incohérent
si elles ne sont pas documentées comme contraintes d'architecture.

### Invariant 1 — Fermeture des composants satellites (ECS × RLS)

**Règle** : toute table satellite d'un composant Core sous RLS doit recevoir soit
un `REVOKE SELECT`, soit sa propre politique RLS.

**Pourquoi ce n'est pas déductible du DDL.**
Le RLS d'une table Core ne se propage pas automatiquement à ses satellites. Un
`SELECT * FROM commerce.transaction_item` par `marius_user` contourne entièrement
`rls_transaction_select` — PostgreSQL évalue le RLS de la table accédée, pas
celui de ses tables parentes. La fragmentation ECS (ADR-016) crée donc un vecteur
de fuite par défaut : chaque composant satellite 1:1 est une porte d'entrée
indépendante vers les données de la commande.

**Application dans ce schéma.**
Les satellites de `commerce.transaction_core` (`transaction_price`, `transaction_item`,
`transaction_payment`, `transaction_delivery`) reçoivent tous un `REVOKE SELECT`.
Les satellites de `content.core` (`content.identity`, `content.body`, `content.revision`)
reçoivent de même un `REVOKE SELECT` : un SELECT direct sur `content.identity`
retournerait les titres et slugs de tous les brouillons sans que `rls_core_select`
ne soit jamais évalué. L'accès applicatif est contraint aux vues sémantiques
`content.v_article_list` et `content.v_article`, qui imposent la jointure sur
`content.core` filtré par RLS.

**Extension aux vues (audit RLS global).**
Le même vecteur s'applique aux vues owned par `postgres` (BYPASSRLS) : une vue
peut lire des tables sous REVOKE SELECT et en exposer les données sans filtre.
`identity.v_auth` illustrait ce cas — la vue exposait `password_hash` à tout
`marius_user` en contournant le REVOKE sur `identity.auth`. Correction :
`REVOKE SELECT ON identity.v_auth FROM marius_user`.
`identity.v_person` illustre un second vecteur : email et phone issus de
`identity.person_contact` (REVOKE'd) étaient projetés sans filtre. Correction :
exclusion des colonnes PII de la projection de la vue.

**Invariant de maintenance.**
Lors de tout ajout d'un composant satellite dans un schéma dont le Core est sous
RLS, le `GRANT SELECT` hérité de `GRANT SELECT ON ALL TABLES` doit être
immédiatement suivi d'un `REVOKE SELECT` ciblé ou d'une politique RLS dédiée.
L'absence de protection est silencieuse — PostgreSQL n'émet aucun avertissement.
La même vérification s'applique aux vues : toute vue projetant des données issues
d'une table sous REVOKE SELECT doit recevoir soit un REVOKE SELECT propre, soit
exclure les colonnes sensibles de sa projection.

### Invariant 2 — Security context des vues et responsabilité du contrôle d'accès

**Règle** : les vues owned par un superutilisateur (BYPASSRLS) **doivent** porter
explicitement les prédicats de contrôle d'accès dans leur clause WHERE. Le RLS
physique sur les tables sous-jacentes est inopérant sur ce chemin.

**Pourquoi ce n'est pas déductible du DDL.**
Par défaut (sans `security_invoker = true`), PostgreSQL évalue les politiques RLS
en utilisant l'identité du propriétaire de la vue, pas celle de l'appelant. Les
vues de la Section 12 sont toutes owned par `postgres`, qui possède l'attribut
`BYPASSRLS`. Conséquence : `SELECT * FROM content.v_article_list` exécuté par
`marius_user` lit `content.core` en tant que `postgres` — la politique
`rls_core_select` n'est jamais évaluée. Tous les brouillons sont visibles.

L'option `security_invoker = true` restaurerait le RLS physique, mais rendrait
la vue incapable de lire les composants satellites sous REVOKE SELECT
(`content.identity`, `content.body`, etc.) — puisqu'elle s'exécuterait alors
avec les droits de `marius_user`, qui n'a pas ces privilèges.

**Invariant résultant.**
L'architecture retenue (vues owned par `postgres` + REVOKE sur satellites) est
cohérente si et seulement si chaque vue exposant des données filtrées par un Core
sous RLS réplique explicitement le prédicat de filtrage dans son WHERE. Ce WHERE
utilise les helpers GUC (`rls_user_id()`, `rls_auth_bits()`), qui lisent le GUC
de **session** — invariant par rapport au security context d'exécution de la vue.
Un `current_setting('marius.user_id', true)` appelé depuis un contexte `postgres`
retourne correctement la valeur injectée par le middleware dans la session de
`marius_user`.

**Application dans ce schéma.**
Les vues `content.v_article_list`, `content.v_article`, `identity.v_account` et
`commerce.v_transaction` portent toutes un WHERE répliquant le prédicat de leur
Core respectif. Le RLS physique reste actif pour les accès directs aux tables
(défense en profondeur), mais le WHERE de la vue est le mécanisme primaire sur le
chemin de lecture applicatif normal.

Le comportement en accès anonyme (GUC absent) reste correct : `rls_user_id() = -1`
ne correspond à aucun auteur, `rls_auth_bits() = 0` annule tous les bits → seul
`status = 1` passe pour le contenu.

### Invariant 3 — Symétrie SELECT/UPDATE dans les politiques RLS

**Règle** : tout bit de permission accordant un UPDATE ou DELETE sur une table
doit figurer aussi dans le prédicat `USING` de la politique `SELECT` de cette
même table.

**Pourquoi ce n'est pas déductible du DDL.**
PostgreSQL évalue la politique `FOR SELECT` comme pré-condition à toute opération
d'écriture : une ligne invisible en SELECT est invisible en UPDATE et DELETE. Une
politique `FOR UPDATE USING ((auth_bits & X) = X)` dont le bit X n'est pas couvert
par `FOR SELECT USING` est structurellement morte — elle ne s'applique jamais, sans
erreur ni avertissement. L'UPDATE renvoie 0 lignes affectées, indiscernable d'un
UPDATE valide sur un ensemble vide.

**Application dans ce schéma.**
`rls_core_select` inclut le bit `edit_others_contents` (32768), qui figure aussi
dans `rls_core_update_others` et `rls_core_delete_others`. Sans ce critère dans le
SELECT, le rôle `editor` (59438 = base_author + edit_others_contents + manage_tags,
sans `publish_contents`) ne peut ni voir, ni donc modifier, ni supprimer les
brouillons d'autrui — les politiques UPDATE/DELETE d'éditeur sont inatteignables.

`rls_transaction_select` inclut le bit `manage_commerce` (262144), qui figure dans
`rls_transaction_update`. Les bits `view_transactions` (131072) et `manage_commerce`
(262144) sont orthogonaux : un profil gestionnaire commerce portant uniquement
`manage_commerce` échouerait silencieusement sur tout UPDATE sans ce critère dans
le SELECT.

**Corollaire pour les procédures SECURITY DEFINER.**
Les procédures s'exécutant en tant que `postgres` bypassent le RLS. Un bit de
permission vérifié dans la garde procédurale suffit pour les opérations globales
(ex : `publish_contents` → toute publication). Pour les opérations à portée
restreinte (modifier/sauvegarder son propre contenu), la garde doit reconstituer
explicitement le filtre d'appartenance : la politique RLS d'ownership est bypassée
et ne constitue pas un garde procédural implicite.

`content.save_revision` illustre ce cas : un auteur sans `edit_others_contents`
ne peut sauvegarder que ses propres documents — ce filtre est implémenté
explicitement dans le corps de la procédure via un SELECT sur `content.core`.

**Invariant de maintenance.**
Lors de tout ajout d'une politique `FOR UPDATE` ou `FOR DELETE` sur une table Core
sous RLS, vérifier que chaque bit présent dans son `USING` est aussi couvert par
au moins un critère de la politique `FOR SELECT` de la même table.

---

## ADR-004 — Expansion du bitmask de sécurité : passage à 21 bits sur INT4

**Statut** : Adopté

### Correction de prémisse

Le prompt demandait "passer de SMALLINT à INT4 pour permissions". Cette migration
était déjà effectuée en ADR-015 (session initiale). `permissions` est et a toujours
été `INT4` dans ce schéma. Ce qui est réellement muté ici :

1. Le plafond du CHECK `permissions BETWEEN 0 AND 32767` → `BETWEEN 0 AND 2097151`
   (2²¹−1 = tous les bits 0 à 20 actifs).
2. L'ajout de 6 entrées dans `identity.permission_bit` (bits 15 à 20).
3. Le recalcul des valeurs de `identity.role`.
4. L'extension de `identity.v_role` à 21 colonnes booléennes.

### Nouveaux bits

| Bit | Valeur  | Nom                  | Sémantique                                             |
| --- | ------- | -------------------- | ------------------------------------------------------ |
| 15  | 32768   | edit_others_contents | Modifier les contenus d'autres auteurs                 |
| 16  | 65536   | moderate_comments    | Changer le statut des commentaires (spam, approbation) |
| 17  | 131072  | view_transactions    | Lecture des données financières commerce               |
| 18  | 262144  | manage_commerce      | Gestion produits, stocks, remboursements               |
| 19  | 524288  | manage_system        | Modification des invariants structurels                |
| 20  | 1048576 | export_data          | Extraction massive (RGPD, sauvegarde)                  |

### Pourquoi INT4 et pas INT8 ?

INT8 offrirait 63 bits utilisables. Mais la plage INT4 signée couvre 31 bits
positifs (2³¹−1 = 2 147 483 647). Avec 21 bits actuels et `bit_index BETWEEN 0 AND 30`
déjà en place, INT4 absorbe 10 bits de réserve supplémentaires sans migration.
INT8 doublerait la taille de la colonne (8 B vs 4 B) pour un bénéfice non
justifiable : l'architecture de sécurité d'un CMS n'a pas vocation à dépasser
30 permissions distinctes.

### Cohérence du type pass-by-value

INT4 est pass-by-value sur toutes les architectures 64 bits. L'opération de
vérification `(permissions & p_permission) <> 0` reste O(1) — une instruction
ALU, indépendante du nombre de bits définis.

### Valeurs des rôles

| Rôle          | Valeur  | Composition                                                                                   |
| ------------- | ------- | --------------------------------------------------------------------------------------------- |
| administrator | 2097151 | Tous bits 0–20 (2²¹−1)                                                                        |
| moderator     | 124990  | base_author + publish_contents + manage_tags + edit_others_contents + moderate_comments       |
| editor        | 59438   | base_author + edit_others_contents + manage_tags                                              |
| author        | 24622   | can_read + create_contents + edit_contents + delete_contents + upload_files + create_comments |
| contributor   | 16418   | can_read + create_contents + create_comments                                                  |
| commentator   | 16608   | can_read + create_comments + edit_comments + delete_comments                                  |
| subscriber    | 16384   | can_read uniquement                                                                           |

`base_author` = 16384+2+4+8+8192+32 = **24622** (ADR-003 : delete_contents(8) ajouté).
`moderator` = base_author + 16 + 2048 + 32768 + 65536 = **124990** (manage_tags ajouté — cohérence avec le cycle de vie éditorial complet).
Vérification : tous les calculs ont été validés par addition explicite des puissances de 2 avant intégration.

### Choix éditoriaux pour moderator et editor

Le modérateur dispose de la pleine autonomie sur le cycle de vie éditorial :
modification des contenus d'autrui (`edit_others_contents`), publication et
dépublication (`publish_contents`), gestion du statut des commentaires
(`moderate_comments`). `manage_users` reste réservé aux rangs supérieurs.

`delete_contents` est accordé dès le rôle `author` (ADR-003) : un auteur doit
pouvoir supprimer ses propres brouillons, et la politique `rls_core_delete_own`
vérifie ce bit. Par composition, editor et moderator en héritent. La suppression
de contenus tiers est régie par `edit_others_contents` via `rls_core_delete_others`,
indépendamment de `delete_contents`.

`manage_tags` (2048) est présent dans `editor` et `moderator`. Le modérateur ayant
autorité complète sur le cycle de vie éditorial (publication, modification, modération),
lui retirer la gestion de la taxonomie créait une asymétrie opérationnelle : il peut
publier un article mais pas créer le tag manquant pour l'indexer. `contributor` et
`author` ne reçoivent pas `manage_tags` — la taxonomie est un domaine structurel
distinct de la création de contenu.

### Bits sans enforcement moteur (signaux applicatifs)

Neuf bits sont définis dans `identity.permission_bit` mais ne font l'objet d'aucun
guard AOT ni politique RLS dans ce blueprint. Leur enforcement est délégué à la couche
applicative (middleware, panneau d'administration). Cette délégation est intentionnelle
dans tous les cas ci-dessous.

| Bit                    | Valeur  | Motif de la délégation applicative                                                                                                                                                                  |
| ---------------------- | ------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `access_admin` (0)     | 1       | Accès au panneau admin — notion applicative pure, pas de table moteur associée                                                                                                                      |
| `edit_comments` (6)    | 64      | Pas de procédure `edit_comment` dans ce blueprint ; DML révoqué sur `content.comment` (ADR-001)                                                                                                     |
| `delete_comments` (7)  | 128     | Même motif que `edit_comments`                                                                                                                                                                      |
| `manage_groups` (9)    | 512     | Aucune procédure de gestion des groupes dans ce blueprint — réservé pour usage futur                                                                                                                |
| `manage_contents` (10) | 1024    | Uniquement détenu par `administrator`, qui possède déjà `edit_others_contents`. Bit sémantiquement distinct (accès section admin éditoriale) mais sans frontière de privilège moteur supplémentaire |
| `manage_menus` (12)    | 4096    | Aucune table de menus dans ce blueprint — réservé pour usage futur                                                                                                                                  |
| `upload_files` (13)    | 8192    | Contrôle délégué au service de stockage (S3/CDN) — le moteur PostgreSQL ne gère pas les uploads                                                                                                     |
| `can_read` (14)        | 16384   | Bit de présence minimale ; les données publiques sont lisibles sans RLS — pas de guard redondant                                                                                                    |
| `export_data` (20)     | 1048576 | Aucune procédure d'export dans ce blueprint — réservé pour jobs ETL/RGPD futurs                                                                                                                     |

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
par les vues sémantiques (ADR-012) qui masquent la fragmentation à la couche
applicative.

---

## ADR-006 — Layout physique décroissant (règle universelle)

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

## ADR-007 — Procédure `content.create_comment()` : zéro dead tuple structurel

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
- La procédure est le seul point d'entrée autorisé (ADR-001), ce qui garantit
  l'invariant sans trigger de contrôle supplémentaire.

---

## ADR-008 — `fillfactor` réduit sur les tables à mises à jour fréquentes

**Statut** : Adopté

### Décision

| Table                   | fillfactor | Colonne mise à jour fréquemment        |
| ----------------------- | ---------- | -------------------------------------- |
| `identity.auth`         | 70         | `last_login_at` (chaque connexion)     |
| `commerce.product_core` | 80         | `stock` (chaque vente)                 |
| `content.core`          | 75         | `status`, `modified_at` (cycle de vie) |

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

## ADR-009 — Isolation agressive du TOAST (`toast_tuple_target = 128`)

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

## ADR-010 — Index BRIN sur les colonnes temporelles à progression monotone

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

## ADR-011 — Schémas PostgreSQL pour l'isolation des domaines

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

## ADR-012 — Vues sémantiques comme seule interface de lecture

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

## ADR-013 — Spine polymorphe : absence de validation de sous-type au niveau moteur

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

La cohérence est garantie par les procédures d'écriture (ADR-001) :

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
injustifié dès lors qu'ADR-001 est en place.

---

## ADR-014 — `GENERATED ALWAYS AS IDENTITY` sur toutes les PK

**Statut** : Adopté

### Arbitrage entre les options d'identité

| Option                 | Taille | Remarque                                                         |
| ---------------------- | ------ | ---------------------------------------------------------------- |
| UUID v4                | 16 B   | Pertinent multi-nœuds ; pénalisant sur les tables de liaison N:N |
| `SERIAL`               | 4 B    | Syntaxe propriétaire, dépréciée depuis PG 10                     |
| `GENERATED BY DEFAULT` | 4 B    | Permet les INSERT explicites sans `OVERRIDING SYSTEM VALUE`      |
| `GENERATED ALWAYS`     | 4 B    | Interdit les INSERT explicites — cohérent avec ADR-001           |

### Justification

`GENERATED ALWAYS` renforce le verrou d'ADR-001 au niveau de la séquence :
même `marius_admin` doit passer par `OVERRIDING SYSTEM VALUE` pour forcer un
id. Cela signale explicitement toute insertion hors procédure dans le code source.

UUID est écarté pour les tables de liaison N:N : deux `INT4` en PK composée
= 8 bytes. Deux UUID = 32 bytes. L'impact sur les index et la densité de page
est direct sur les tables à forte volumétrie (`content_to_tag`, `transaction_item`).

---

## ADR-015 — Bitmask `INT4` pour les permissions de rôle

**Statut** : Adopté

### Décision

Les 15 permissions du système sont encodées dans une colonne `permissions INT4`
unique, par OR binaire des puissances de 2.

### Arbitrage entre les types candidats

| Type     | Taille  | Contrainte                                              |
| -------- | ------- | ------------------------------------------------------- |
| `BIT(n)` | varlena | 4 bytes d'en-tête + données ; opérateurs moins naturels |
| `INT2`   | 2 bytes | Bit 15 = bit de signe ; toute 16e permission déborde    |
| `INT4`   | 4 bytes | 17 bits libres pour extensions ; `&`, `\|`, `~` natifs  |

### Justification

`INT4` : alignement natif sur 4 bytes (déclaré à offset 0 dans `identity.role`,
zéro padding), opérateurs bitwise standard lisibles, 17 bits libres pour
extensions futures sans migration de type.

**Gain en CPU tuple deforming** : un accès à `permissions` est un seul appel
`slot_getattr()`. Pertinent sur le hot path d'authentification.

---

## ADR-016 — Éclatement de l'agrégat de commande en composants ECS 1:1

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

| Composant              | Sémantique schema.org        | Fréquence d'accès |
| ---------------------- | ---------------------------- | ----------------- |
| `transaction_core`     | `Order`                      | Très haute        |
| `transaction_price`    | `PriceSpecification`         | Haute             |
| `transaction_payment`  | `PaymentChargeSpecification` | Moyenne           |
| `transaction_delivery` | `ParcelDelivery`             | Basse             |
| `transaction_item`     | `OrderItem` (N lignes)       | Haute             |

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

**Tous les montants en `INT8` centimes** (ADR-026) : `shipping_cents`,
`discount_cents`, `tax_cents` suivent la même règle que `price_cents`. Pas de
NUMERIC dans le hot path financier.

### Procédure `create_transaction`

La procédure crée atomiquement les quatre composants : `transaction_core` +
`transaction_price` (devise + montants à zéro) + `transaction_payment` (statut 0)

- `transaction_delivery` (statut 0). **Il n'existe jamais de transaction_core sans
  ses trois composants** — l'invariant est garanti par l'atomicité de la transaction.
  Les composants sont mis à jour indépendamment au fil du cycle de vie de la commande.

### Relation avec les autres ADR

- ADR-005 (fragmentation ECS) : même pattern appliqué au domaine Commerce.
- ADR-026 (INT8 centimes) : invariant étendu à tous les montants de `transaction_price`.
- ADR-001 (SECURITY DEFINER) : `create_transaction` est la seule procédure
  d'écriture autorisée pour `marius_user` sur `transaction_core` et ses composants.

---

## ADR-017 — Fragmentation geo, soft delete RGPD et compliance de production

**Statut** : Adopté

### Contexte

Quatre vecteurs de risque identifiés avant mise en production européenne :

1. `geo.place_core` mélange spine spatial (coordonnées KNN) et adresse postale (logistique).
2. `org.org_legal.vat_number VARCHAR(15)` trop court pour les identifiants fiscaux internationaux.
3. Absence de mécanisme de droit à l'oubli (RGPD art. 17) et de traçabilité du consentement.
4. Absence de mention de droits dans les métadonnées médias (risque légal d'exploitation d'images).

---

## ADR-018 — Closure Table pour la taxonomie des tags : ltree conservé pour les commentaires

**Statut** : Adopté

### Contexte

Le composant `content.tag` utilisait un chemin `ltree` (`path`) et un `parent_id`
pour représenter la hiérarchie taxonomique. Deux limites opérationnelles ont été
identifiées :

1. **Mobilité des tags** : déplacer un tag dans la hiérarchie avec ltree nécessite
   un UPDATE en cascade de `path` sur tous les descendants — O(n_descendants) UPDATEs,
   risque de locks en production.
2. **Couplage structurel** : `path` encode à la fois l'identité du tag
   (`theology.patristics.cyrille`) et sa position hiérarchique. Renommer un ancêtre
   force un UPDATE en cascade sur tous ses descendants.

### Décision : Closure Table pour les tags

La hiérarchie est portée par `content.tag_hierarchy(ancestor_id, descendant_id, depth)`
indépendamment des données du tag. Le spine `content.tag` devient `(id, slug, name)` — immuable.

**Invariant opérationnel** : chaque tag possède obligatoirement une self-reference
`(id, id, 0)`. La procédure `content.create_tag` garantit cet invariant à l'insertion.

**Profondeur maximale = 4** : contrainte CHECK `depth BETWEEN 0 AND 4`. La procédure
lève une exception à l'INSERT si un parent est déjà à depth 4.

### Pourquoi pas ltree pour les tags

| Critère            | ltree                            | Closure Table                                  |
| ------------------ | -------------------------------- | ---------------------------------------------- |
| Sous-arbre query   | `path <@ 'parent.path'` (GiST)   | `WHERE ancestor_id = X AND depth > 0` (B-tree) |
| Move tag           | UPDATE en cascade O(descendants) | DELETE + reinsert O(depth)                     |
| Rename ancestor    | UPDATE en cascade O(descendants) | Zéro impact (noms dans tag spine)              |
| Insert nouveau tag | O(1) — concat path               | O(depth) — inserts ancêtres                    |
| Breadcrumb         | Gratuit (le path IS le chemin)   | string_agg + self-join                         |
| Dépendance         | Extension ltree                  | SQL pur                                        |

Pour une taxonomie éditoriale à insertions rares et depth ≤ 4, le coût du move
est le critère déterminant. La requête de sous-arbre sur la Closure Table est un
équijoin sur INT4 avec index B-tree — plus cache-friendly qu'un scan GiST sur varlena.

### ltree conservé pour `content.comment`

**Non négociable.** ADR-007 est architecturalement construit autour du ltree :
la procédure `create_comment` utilise `nextval()` préalable + construction du
chemin en mémoire + INSERT unique pour garantir zéro dead tuple. La Closure Table
sur les commentaires est inapplicable :

- Volume : 10 000+ commentaires/jour → O(profondeur) inserts par commentaire
  avec locks en cascade sur `tag_hierarchy` équivalent.
- Les commentaires ne sont jamais "déplacés" — la raison principale de la Closure
  Table n'existe pas pour eux.
- La profondeur des commentaires est non bornée (ADR-022 : ltree supporte des
  arborescences profondes avec O(log n) via GiST).

L'extension ltree reste installée et en usage actif pour `content.comment.path`.

### Physique — densité

| Table                   | Avant              | Après                  |
| ----------------------- | ------------------ | ---------------------- |
| `content.tag`           | ~80 B (ltree path) | ~50 B (slug+name)      |
| `content.tag_hierarchy` | —                  | 12 B/tuple (~682/page) |

Pour 232 tags à plat : 232 lignes dans `tag_hierarchy` (self-refs).
Pour une taxonomie 4 niveaux de 232 tags répartis : max ~500-900 lignes.

### Procédure `create_tag`

Seul point d'entrée autorisé pour `marius_user`. Gère atomiquement :
l'INSERT dans le spine `tag`, la self-reference depth=0, et l'héritage des
ancêtres du parent via SELECT/INSERT depuis `tag_hierarchy`.

---

## ADR-019 — Spine `content.document` indépendant de `identity.entity`

**Statut** : Adopté

### Arbitrage

| Option                            | Avantage               | Inconvénient                            |
| --------------------------------- | ---------------------- | --------------------------------------- |
| Spine partagé (`identity.entity`) | Un seul registre d'IDs | Mélange volumétrique, cascades croisées |
| Spine dédié (`content.document`)  | Isolation complète     | Un registre supplémentaire              |

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

## ADR-020 — Spines `org.entity` et `geo.place_core` : stratégies distinctes

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

## ADR-021 — Table `commerce.transaction_item` : résolution 1NF

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

## ADR-022 — `ltree` pour les hiérarchies de tags et commentaires

**Statut** : Adopté

### Comparaison des patterns hiérarchiques

| Critère              | Adjacency List                | Nested Set                  | ltree                  |
| -------------------- | ----------------------------- | --------------------------- | ---------------------- |
| Lecture sous-arbre   | O(profondeur) — CTE récursive | O(1) — BETWEEN              | O(log n) — index GiST  |
| INSERT               | O(1)                          | O(n) — recalcul intervalles | O(1) — concat chemin   |
| Lisibilité du chemin | `parent_id = 42`              | `lft=5, rgt=12`             | `theology.patristics`  |
| Index disponible     | B-tree sur `parent_id`        | B-tree sur `lft`/`rgt`      | GiST (`@>`, `<@`, KNN) |

### Justification

**Tags** : la lecture de sous-arbres est le pattern dominant. `ltree` + index
GiST résout en O(log n) sans CTE récursive. Les insertions sont rares.

**Commentaires** : le pattern dominant est l'affichage d'un thread complet
(opérateur `<@`). ltree résout en O(log n). L'INSERT est O(1) — critique sous
concurrence.

Le Nested Set est écarté pour les commentaires : son INSERT est O(n) et requiert
un verrouillage de table pour recalculer les intervalles. Incompatible avec une
table à insertions concurrentes.

La procédure `content.create_comment()` (ADR-007) construit le chemin en mémoire
avant l'INSERT unique, sans aucun UPDATE post-insertion.

---

## ADR-023 — Agrégation JSON dans les vues pour éliminer le N+1

**Statut** : Adopté

### Décision

Les relations N:N (tags, médias, lignes de commande) sont agrégées directement
dans le moteur via `json_agg()` + `json_build_object()` depuis les vues
sémantiques `content.v_article` et `commerce.v_transaction`.

### Justification

Sans agrégation moteur, la couche applicative effectue une requête principale

- N requêtes secondaires. Pour 3–20 éléments liés, le coût CPU de `json_agg`
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

## ADR-024 — Correctifs de cohérence : snapshot complet, verrou exclusif, trigger manquant

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

| #   | Suggestion                                                 | Motif d'exclusion                                                                                                                                                                                                                                                                      |
| --- | ---------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1   | Retry automatique dans `fn_slug_deduplicate`               | Comportement intentionnel documenté dans le DDL : la contrainte `UNIQUE` est le garde-fou ; l'erreur 23505 est propre et attrapable côté applicatif. Ajouter un retry dans le trigger déplacerait la responsabilité du retry au mauvais niveau.                                        |
| 4   | Remplacer `CHECK (path IS NOT NULL)` par `NOT NULL`        | Déjà documenté en détail dans le DDL. Le `CHECK` est l'unique moyen de permettre `OVERRIDING SYSTEM VALUE` dans `create_comment` tout en rejetant les INSERT directs sans path.                                                                                                        |
| 5   | B-tree complémentaire si BRIN inefficace                   | Déjà couvert en ADR-010 : la condition d'efficacité (insertions chronologiques) est documentée ; l'ajout d'un B-tree complémentaire est une décision opérationnelle à prendre sur données réelles, pas un invariant à inscrire dans le blueprint.                                      |
| 7   | Partitionnement de `content.comment` et `content.revision` | Prématuré à l'échelle cible (500 k utilisateurs). PostgreSQL gère confortablement ces volumes avec les index existants. Le partitionnement ajoute de la complexité opérationnelle significative (maintenance des partitions, contraintes croisées) sans bénéfice mesurable à ce stade. |
| 8   | Suite de tests pgTAP                                       | Hors périmètre du blueprint DDL. Pertinent comme étape CI/CD distincte.                                                                                                                                                                                                                |

---

## ADR-025 — `INT8` centimes pour tous les montants monétaires

**Statut** : Adopté (révisé — ADR-026)

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

## ADR-026 — Optimisations CPU/mémoire : entiers natifs, VARCHAR, padding documenté, pushdown

**Statut** : Adopté

### Contexte

Audit DOD ciblé sur les composants chauds (`commerce.product_core`,
`commerce.transaction_item`, `org.org_legal`, `identity.auth`,
`commerce.v_transaction`). Quatre ajustements de topologie physique.

### 1. NUMERIC → INT8 centimes (commerce)

Voir ADR-025 pour le raisonnement complet. Résumé :

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

## ADR-027 — `VARCHAR(n)` pour DUNS, SIRET et ISBN/EAN

**Statut** : Adopté (révisé — ADR-026)

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

## ADR-028 — Interface sémantique snake_case : schema.org sans guillemets SQL

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

| Règle                                  | Exemple schema.org | Alias vue                                    |
| -------------------------------------- | ------------------ | -------------------------------------------- |
| camelCase → snake_case                 | `givenName`        | `given_name`                                 |
| Suffixe `_at` pour TIMESTAMPTZ         | `datePublished`    | `published_at`                               |
| Suffixe `_cents` pour INT8 monétaire   | `price`            | `price_cents`                                |
| Suffixe `_id` pour FK                  | `authorId`         | `author_id`                                  |
| Suffixe `_code` pour codes numériques  | `currencyCode`     | `currency_code`                              |
| Miroir du nom physique quand identique | `is_readable`      | `is_readable` (pas `is_accessible_for_free`) |
| `@type` → `doc_type` / `org_type`      | `@type`            | `doc_type`, `org_type`                       |

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

## ADR-029 — Séparation DDL / DML

**Statut** : Adopté

Deux artefacts distincts :

- `master_schema_ddl.pgsql` — Blueprint immuable, idempotent, versionnable seul.
- `master_schema_dml.pgsql` — Seed data, dev/CI uniquement, jamais exécuté en
  production.

**Exception** : les `INSERT` sur `identity.permission_bit` et `identity.role`
restent dans le DDL — données de configuration structurelle insécables du schéma
au même titre que les `REVOKE` qui les suivent.

---

## ADR-030 — Audit commerce : immuabilité financière, gardes AOT et séparation des privilèges

**Statut** : Adopté

### Contexte

Audit ciblé du schéma `commerce` sur quatre axes : séparation des privilèges lecture/transaction, immuabilité des enregistrements financiers, déshydratation du layout, robustesse aux concurrences.

### Correction 1 — Immuabilité de `transaction_item` (Trigger moteur)

**Invariant** : `unit_price_snapshot_cents` est un enregistrement d'audit financier. Sa valeur au moment de l'INSERT constitue la preuve du prix contractuel. Toute modification ultérieure, même par `marius_admin`, invalide l'intégrité de l'historique.

**Mécanisme** : trigger `BEFORE UPDATE` `transaction_item_immutable` appelant `commerce.fn_deny_transaction_item_update()` — lève `55000 (object_not_in_prerequisite_state)` sur tout UPDATE. La seule opération légitime sur une ligne existante est la suppression (annulation de ligne) : elle est couverte par `ON DELETE CASCADE` depuis `transaction_core`.

**Cohérence avec le commentaire DDL** : la table documentait déjà `unit_price_snapshot_cents` comme "immuable après création". Le trigger matérialise cet invariant au niveau moteur.

### Correction 2 — Gardes AOT sur `create_transaction_item`

Deux gardes manquants :

**Garde ownership** : la procédure étant SECURITY DEFINER (bypass RLS), tout `marius_user` pouvait ajouter des lignes à n'importe quelle transaction. Garde ajouté : `client_entity_id = rls_user_id() OR manage_commerce (262144)`.

**Garde statut** : pas de vérification que la transaction est en état `pending (status=0)`. Un item pouvait être inséré sur une transaction confirmée, expédiée ou annulée. Garde ajouté : `status <> 0` lève `55000`. La lecture du statut utilise `FOR SHARE` pour éviter une race condition avec `rls_transaction_update`.

### Correction 3 — Garde AOT sur `create_transaction`

`create_transaction` était dans la liste des "procédures sans garde" (ADR-001). Tout subscriber pouvait créer une transaction pour n'importe quel `client_entity_id` (usurpation). Garde ajouté : `p_client_entity_id = rls_user_id() OR manage_commerce (262144)`.

### Analyse des points conformes

**Séparation lecture prix / transactions** : cohérente. Le catalogue produit (`product_core`, `product_identity`) est intentionnellement public — pas de RLS, pas de REVOKE. Les données transactionnelles sont toutes sous REVOKE SELECT + RLS sur `transaction_core`.

**Déshydratation** : conforme à ADR-006 et ADR-016. `transaction_core` porte uniquement les champs hot path. `product_content` a `toast_tuple_target = 128`. `transaction_core.description TEXT` est une varlena dans le hot tuple — non-nul, elle gonfle chaque lecture de statut ; la valeur NULL (défaut) maintient le tuple à 32B.

**Race condition sur le stock** : `FOR UPDATE` sur `product_core` dans `create_transaction_item` + CHECK `stock >= 0` — correctement traité depuis ADR-024.

### Invariant de maintenance

Toute procédure SECURITY DEFINER opérant sur des données financières doit vérifier :

1. L'ownership du contexte (à qui appartient la ressource cible)
2. L'état courant de la ressource (transitions d'état valides)
3. Le bit de permission approprié

Ces trois gardes sont indépendants et tous trois nécessaires : chacun couvre un vecteur d'attaque distinct.

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

_Architecture ECS/DOD · PostgreSQL 18 · Projet Marius · 30 décisions_
