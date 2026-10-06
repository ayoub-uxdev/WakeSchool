# WakeSchool — Contexte du projet

## Objectif
Application iPhone native, assistant scolaire intelligent (pas un clone de Pronote). Pronote/ENT = source de données quand l'intégration sera disponible.

## Vision / fonctionnalités visées
Emploi du temps, devoirs, notes et moyennes, contrôles, changements de cours, absences de professeurs, événements, rappels, préparation de la journée, réveil intelligent (AlarmKit), assistant IA WakeBot.

## Technologies
Swift / SwiftUI, iOS 27, AlarmKit. Plus tard : Supabase (RLS), SwiftData, Keychain, UserDefaults.
Build : GitHub Actions + Xcode 27 depuis Windows. Le projet Xcode est généré par XcodeGen (`iOS/project.yml`), il n'y a pas de .xcodeproj versionné.

## Équipe
Ayoub (chef de projet, tests iPhone, validation) · ChatGPT (architecture, sécurité, consignes) · Claude (développeur principal) · Gemini (assets non réalistes) · Grok (assets réalistes).

## État actuel
Base du projet en place : structure, documentation, app SwiftUI minimale (Dashboard placeholder), modèles de base, AlarmManager, protocole PronoteClient. Validé sur GitHub Actions avec Xcode 27 : build, génération du projet par XcodeGen, IPA non signée (voir CHANGELOG).
Fonctionnalités validées : `WakeTimeCalculator` (`Services/WakeTimeCalculator.swift`, calcul pur de l'heure de réveil recommandée, sans AlarmKit) et sa cible de tests `WakeSchoolTests` (tests unitaires exécutés avec succès sur simulateur dans GitHub Actions). Le calculateur n'est pas encore branché à `AlarmManager`.
Écran « Réveil intelligent » (`UI/SmartAlarmView.swift`) ajouté avec des données de démonstration, accessible via un `TabView` dans `RootView` : il affiche les horaires calculés par `WakeTimeCalculator` mais ne programme aucune alarme. Validation du build et des tests sur GitHub Actions à confirmer.

## Décisions importantes
- AlarmKit validé sur appareil réel via le prototype AlarmTest ; toute la logique reste isolée dans `Alarm/AlarmManager.swift`.
- Une alarme n'est jamais considérée comme créée si `schedule` échoue.
- Pronote isolé derrière le protocole `PronoteClient` ; aucune API inventée.
- Aucun secret dans Git ; mots de passe Pronote jamais en clair.
- Développement feature par feature, validation d'Ayoub avant chaque nouvelle fonctionnalité.