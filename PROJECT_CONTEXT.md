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
Squelette uniquement : structure, documentation, app SwiftUI minimale, modèles de base, AlarmManager, protocole PronoteClient. Compilation CI avec Xcode 27 validée (build GitHub Actions + XcodeGen + IPA non signée, voir CHANGELOG).

## Décisions importantes
- AlarmKit validé sur appareil réel via le prototype AlarmTest ; toute la logique reste isolée dans `Alarm/AlarmManager.swift`.
- Une alarme n'est jamais considérée comme créée si `schedule` échoue.
- Pronote isolé derrière le protocole `PronoteClient` ; aucune API inventée.
- Aucun secret dans Git ; mots de passe Pronote jamais en clair.
- Développement feature par feature, validation d'Ayoub avant chaque nouvelle fonctionnalité.
