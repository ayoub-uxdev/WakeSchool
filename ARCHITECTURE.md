# Architecture

```
iOS/
├── project.yml            (XcodeGen)
└── WakeSchool/
    ├── App/        Point d'entrée, configuration globale
    ├── UI/         Vues SwiftUI (Dashboard, emploi du temps, devoirs, notes, réglages, WakeBot, composants)
    ├── Models/     Modèles de données (structs Codable)
    ├── Alarm/      Tout AlarmKit (AlarmManager, AlarmError)
    ├── Pronote/    Intégration Pronote, isolée derrière PronoteClient
    ├── Sync/       Synchronisation local <-> backend (à venir)
    ├── Storage/    Stockage local et sécurisé (à venir)
    └── Services/   IA, notifications, calendrier, analyse (à venir)
```

## Flux de données (cible)
Pronote (PronoteClient) -> Sync -> Storage (SwiftData) -> UI / Services. Les secrets passent par le Keychain.

## Dépendances
UI dépend de Models, Alarm et Services. Pronote dépend de Models uniquement. Aucune autre couche ne connaît les détails Pronote.

## Principes
Une fonctionnalité à la fois, pas de réécriture inutile, erreurs gérées explicitement, logs sans données sensibles, aucun secret dans le dépôt.
