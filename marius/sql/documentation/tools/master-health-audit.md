# 🛡️ Manuel Opérationnel : Master Health Audit

**Composant :** `meta.v_master_health_audit`  
**Cible :** Architectes Système / DBA Marius  
**Objectif :** Surveillance de l'intégrité ECS/DOD et détection de la dette structurelle.

---

## I. Raison d'être (Le "Pourquoi")

Dans une architecture **ECS/DOD**, la performance ne dépend pas de la "puissance" du serveur, mais de l'organisation millimétrée des données en mémoire. Une simple modification (ajout d'index, mutation hors procédure scellée) peut briser les optimisations **HOT** ou augmenter le **padding CPU**.

La vue `v_master_health_audit` est le juge de paix. Elle fusionne les intentions de design (**AOT**) et les statistiques réelles (**Runtime**) pour garantir que le "Hardware Logiciel" ne dérive pas.

---

## II. Les 4 Piliers de l'Audit

Chaque composant est évalué sur quatre critères critiques, pondérés selon leur impact sur le système :

| Alerte                | Impact       | Signification                                                                             |
| :-------------------- | :----------- | :---------------------------------------------------------------------------------------- |
| **`security_breach`** | **CRITIQUE** | Une mutation a eu lieu hors des procédures autorisées (Contournement du scellement).      |
| **`hot_blocker`**     | **SÉVÈRE**   | Un index a été posé sur une colonne mutable, bloquant les mises à jour _Heap Only Tuple_. |
| **`density_drift`**   | **MAJEUR**   | L'alignement physique (padding) ou le bloat s'écarte du design DOD initial.               |
| **`brin_drift`**      | **MODÉRÉ**   | La corrélation physique des données s'est dégradée, rendant les index BRIN inefficaces.   |

---

## III. Utilisation (Le "Comment")

### 1. Diagnostic de Routine

Pour obtenir l'état de santé global du moteur, lancez la requête suivante :

```sql
SELECT component_name, health_score_pct, triage_status
FROM meta.v_master_health_audit
ORDER BY health_score_pct ASC;
```

### 2. Interprétation du `health_score_pct`

- **100% (OPTIMAL) :** Le composant respecte parfaitement les ADR (Architecture Decision Records).
- **< 100% (DEBT) :** Une dégradation est présente. Consultez les colonnes `*_alert` pour identifier la cause.
- **0% (CRITICAL) :** Rupture d'intégrité sécuritaire ou blocage total des chemins de performance.

### 3. Protocole d'intervention

Si un score chute, suivez cet arbre de décision :

1.  **Si `hot_blocker_alert` = TRUE :** Identifiez les index superflus sur les colonnes mutables. Supprimez l'index ou déplacez la colonne dans un composant immuable.
2.  **Si `density_drift_alert` = TRUE :** Vérifiez si un `VACUUM FULL` ou un `REINDEX` est nécessaire. Si le bloat persiste, le `fillfactor` est peut-être mal calibré.
3.  **Si `security_breach_alert` = TRUE :** Alerte de sécurité. Auditez les logs pour identifier quel rôle a modifié la donnée sans passer par l'interface de mutation officielle.

---

## IV. Gouvernance & Sécurité

- **Accès :** Seul le rôle `marius_admin` dispose des droits de lecture sur cette vue.
- **Mise à jour :** Les métriques de densité et de performance sont rafraîchies selon les cycles de l' `ANALYZE` PostgreSQL.
- **Intégration CI/CD :** Aucun déploiement en production ne doit être validé si le `health_score_pct` moyen est inférieur à **100%**.

---

> **Note aux intervenants :** Ce moteur d'audit n'est pas une simple télémétrie. C'est le garant que le code reste aligné sur le matériel. Respectez les alertes, ou le système perdra sa nature déterministe.
