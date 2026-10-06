# Changelog

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
- vérifié : compilation et tests avec Xcode 27 (à confirmer via la CI).

## 2026-10-06 — Validation du build CI
- Build GitHub Actions avec Xcode 27 validé.
- Génération du projet via XcodeGen validée.
- Génération de l'IPA non signée validée.