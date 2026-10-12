# Reprise LOT 5 (12 octobre 2026)

Base : iOS(4).zip. Modifications ciblées : fermeture correcte de `HomeworkView.section` avant la déclaration de `HomeworkDetailView` ; déplacement de `protocolGradeRejection` hors de `protocolGrade` dans `PronoteMapper.swift`.

Validation réalisée : `swiftc -frontend -parse` sur l'ensemble des fichiers Swift, aucune erreur syntaxique. Ce contrôle ne remplace PAS une compilation Xcode 27, des tests unitaires ou un test iPhone.

État du travail hérité de Copilot : formatter HTML, affichage détaillé et regroupement par date des devoirs, modèles et tentative de téléchargement de pièces jointes, diagnostics de notes. Ces fonctionnalités nécessitent validation réelle. L'importance des devoirs reste `.unspecified` dans le mapper ; Prochains DS, calendrier de vacances et navigation distante sur toute l'année ne sont pas terminés. Ne pas considérer LOT 5 comme livré fonctionnellement.

Ne pas publier de logs de session ni de secrets PRONOTE. Conserver un backup de la version synchronisant PRONOTE avant intégration.
