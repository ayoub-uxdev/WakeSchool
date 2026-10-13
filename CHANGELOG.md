# Changelog

## 2026-10-13 — LOT 6 : onglet Paramètres
- Ajout de `UI/SettingsView.swift` : véritable écran Réglages natif (SwiftUI `Form`), découpé en sections « Compte scolaire », « Réveil et notifications », « Apparence », « Données et diagnostic » et « À propos ». Réutilise `SchoolDataStore`, `SmartAlarmController`, `PreferencesStore` et `PronoteSyncDiagnostics`. Aucun bouton décoratif, états de chargement/erreur explicites.
- Nouvel onglet « Réglages » dans `UI/RootView.swift`.
- Apparence : nouveau modèle `AppearancePreference` (Automatique / Clair / Sombre) persisté dans `PreferencesStore`, exposé via `SchoolDataStore` et appliqué à l'écran Réglages (`.preferredColorScheme`).
- Compte scolaire : `SchoolDataStore.connectionSummary` expose un résumé NON sensible du compte PRONOTE (type de compte, hôte du serveur, méthode QR/ENT/identifiants) — jamais le mot de passe ni le jeton. Synchronisation manuelle et affichage de la dernière erreur.
- Réveil : `AlarmManager.authorizationStatus()` ajouté en LECTURE SEULE (ne déclenche aucune demande d'autorisation) + type d'affichage `WakeAlarmAuthorizationStatus`. Le moteur AlarmKit (`schedule`/`cancel`) n'est pas modifié.
- Version réelle lue depuis le bundle (`WakeAppInfo`) ; `MARKETING_VERSION`/`CURRENT_PROJECT_VERSION` ajoutés à `iOS/project.yml`.
- Tests : `WakeSchoolTests/SettingsPreferencesTests.swift` (persistance de l'apparence, libellés d'autorisation, résumé de connexion sans fuite de secret).
- Non vérifié : compilation Xcode 27 et tests simulateur (à confirmer via la CI). Limitation connue : les écrans existants (Accueil, Emploi du temps, Devoirs, Notes, Réveil) conservent leur design sombre signature ; le mode clair s'applique à l'écran Réglages et aux éléments système. Le profil scolaire détaillé (classe, nom d'établissement) n'est pas encore persisté et n'est donc pas affiché.

## 2026-10-06 — Initialisation
- Création de la structure, des documents et d'un projet SwiftUI minimal (généré par XcodeGen).
- Ajout des modèles de base, de `Alarm/AlarmManager.swift` / `AlarmError.swift` et du protocole `PronoteClient`.
- Ajout du workflow GitHub Actions (build non signé + IPA en artifact).
- Non vérifié : compilation avec Xcode 27 (à confirmer via la CI).

## 2026-10-06 — Calcul de l'heure de réveil recommandée
- Ajout de `Services/WakeTimeCalculator.swift` : calcul pur (sans AlarmKit) de l'heure de réveil à partir du premier cours, du temps de trajet, du temps de préparation et de la marge de sécurité. Le résultat (`WakeTimeRecommendation.wakeTime`) est une `Date` utilisable ensuite avec `AlarmManager.schedule(at:)`.
- Ajout d'un helper pour trouver le premier cours non annulé d'une journée à partir de `TimetableEntry`.
- Ajout de la cible de tests `WakeSchoolTests` (XcodeGen) avec tests unitaires du calcul, et d'une étape de tests simulateur dans le workflow GitHub Actions.
- `AlarmManager` et l'UI ne sont pas modifiés.
- Validé : build Xcode 27 et tests unitaires sur simulateur exécutés avec succès dans GitHub Actions.

## 2026-10-06 — Validation du build CI
- Build GitHub Actions avec Xcode 27 validé.
- Génération du projet via XcodeGen validée.
- Génération de l'IPA non signée validée.

## 2026-10-06 — Écran Réveil intelligent (démonstration)
- Ajout de `UI/SmartAlarmView.swift` : écran SwiftUI affichant l'heure de réveil recommandée, l'heure de départ, le premier cours et les paramètres (trajet, préparation, marge). La vue ne calcule aucun horaire : elle utilise `WakeTimeCalculator`.
- Ajout de `UI/SmartAlarmDemo.swift` : données de démonstration (premier cours 08:00, trajet 25 min, préparation 40 min, marge 10 min) et appel au calculateur, avec une erreur explicite si l'heure du cours ne peut pas être construite.
- `UI/RootView.swift` : `TabView` (Accueil / Réveil) pour accéder à l'écran. `DashboardView` n'est pas modifiée.
- Ajout de `WakeSchoolTests/SmartAlarmDemoTests.swift` (construction de l'heure de démonstration et cohérence avec `WakeTimeCalculator`).
- Le bouton « Programmer ce réveil » est désactivé : aucune alarme n'est programmée. `WakeTimeCalculator`, `AlarmManager`, `project.yml` et le workflow ne sont pas modifiés. Pas de Pronote ni de Supabase.
- Non vérifié : build Xcode 27 et tests simulateur (à confirmer via la CI).