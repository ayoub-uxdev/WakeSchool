import XCTest
@testable import WakeSchool

/// Tests des préférences et du résumé de connexion exposés à l'écran Réglages (LOT 6).
final class SettingsPreferencesTests: XCTestCase {

    private func makePreferences(suite: String) -> PreferencesStore {
        PreferencesStore(defaults: UserDefaults(suiteName: suite)!)
    }

    // MARK: - Préférence d'apparence

    func testAppearanceDefaultsToSystem() {
        XCTAssertEqual(makePreferences(suite: "WakeSchoolSettings-\(UUID().uuidString)").appearance, .system)
    }

    func testAppearancePersistsAcrossInstances() {
        let suite = "WakeSchoolSettings-\(UUID().uuidString)"
        let first = makePreferences(suite: suite)
        XCTAssertEqual(first.appearance, .system)

        first.appearance = .dark

        let second = makePreferences(suite: suite)
        XCTAssertEqual(second.appearance, .dark)
    }

    func testAppearanceInvalidRawValueFallsBackToSystem() {
        let suite = "WakeSchoolSettings-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.set("pas-une-valeur", forKey: "appearance")
        XCTAssertEqual(PreferencesStore(defaults: defaults).appearance, .system)
    }

    func testAppearanceDisplayNamesAndSymbols() {
        XCTAssertEqual(AppearancePreference.system.displayName, "Automatique")
        XCTAssertEqual(AppearancePreference.light.displayName, "Clair")
        XCTAssertEqual(AppearancePreference.dark.displayName, "Sombre")

        for preference in AppearancePreference.allCases {
            XCTAssertFalse(preference.systemImage.isEmpty)
            XCTAssertFalse(preference.displayName.isEmpty)
        }
    }

    // MARK: - Autorisation AlarmKit (libellés d'affichage)

    func testAlarmAuthorizationStatusLabelsAreReadable() {
        XCTAssertFalse(WakeAlarmAuthorizationStatus.authorized.label.isEmpty)
        XCTAssertFalse(WakeAlarmAuthorizationStatus.denied.label.isEmpty)
        XCTAssertFalse(WakeAlarmAuthorizationStatus.notDetermined.label.isEmpty)
        XCTAssertFalse(WakeAlarmAuthorizationStatus.unknown.label.isEmpty)
    }

    // MARK: - Résumé de connexion (aucune donnée sensible)

    @MainActor
    func testConnectionSummaryReportsNotConfiguredByDefault() {
        let environment = AppEnvironment.inMemory()
        let store = SchoolDataStore(environment: environment)

        let summary = store.connectionSummary
        XCTAssertFalse(summary.isConfigured)
        XCTAssertNil(summary.accountKind)
        XCTAssertNil(summary.serverHost)
        XCTAssertNil(summary.method)
    }

    @MainActor
    func testConnectionSummaryReflectsStoredCredentialsWithoutSecrets() throws {
        let environment = AppEnvironment.inMemory()
        try CredentialsStore(store: environment.secrets).save(
            PronoteCredentials(
                serverURL: "https://demonstration.index-education.net/pronote/eleve.html",
                username: "eleve",
                password: "motdepasse-secret",
                accountKind: .student,
                usesMobileToken: false
            )
        )

        let store = SchoolDataStore(environment: environment)
        let summary = store.connectionSummary

        XCTAssertTrue(summary.isConfigured)
        XCTAssertEqual(summary.accountKind, .student)
        XCTAssertEqual(summary.serverHost, "demonstration.index-education.net")
        XCTAssertEqual(summary.method, "Identifiants directs")

        // Le résumé ne doit jamais exposer le mot de passe.
        let mirror = Mirror(reflecting: summary)
        for child in mirror.children {
            if let value = child.value as? String {
                XCTAssertFalse(value.contains("motdepasse-secret"))
            }
        }
    }

    // MARK: - Préférence d'apparence via le store

    @MainActor
    func testStoreAppearancePersistsThroughPreferences() {
        let suite = "WakeSchoolSettingsStore-\(UUID().uuidString)"
        let environment = AppEnvironment.inMemory(preferences: makePreferences(suite: suite))
        let store = SchoolDataStore(environment: environment)

        XCTAssertEqual(store.appearance, .system)
        store.setAppearance(.light)
        XCTAssertEqual(store.appearance, .light)
        XCTAssertEqual(environment.preferences.appearance, .light)
    }
}
