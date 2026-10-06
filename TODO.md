# TODO

## Terminé
- Structure du projet et documentation
- App SwiftUI minimale (placeholder Dashboard)
- Modèles de base
- AlarmManager (code écrit)
- Protocole PronoteClient
- Workflow GitHub Actions + XcodeGen
- Vérifier la compilation sur GitHub Actions avec Xcode 27
- Calcul de l'heure de réveil recommandée : `Services/WakeTimeCalculator.swift` et tests unitaires `WakeSchoolTests/` implémentés ; build Xcode 27 et tests simulateur validés sur GitHub Actions

## En cours
- Écran « Réveil intelligent » (`UI/SmartAlarmView.swift`, données de démonstration, calcul via `WakeTimeCalculator`, alarme non programmée) : code et tests écrits, validation du build et des tests sur GitHub Actions à confirmer

## Prochaines (après validation)
- Écran de test AlarmKit dans WakeSchool
- Dashboard réel avec données de démonstration

## Futures
- Stockage (SwiftData, Keychain), Supabase + RLS, intégration Pronote, WakeBot et ses outils, emploi du temps / devoirs / notes