import Foundation

/// Calcul des moyennes. Toutes les valeurs sont ramenées sur 20.
enum AverageCalculator {

    /// Moyenne pondérée par les coefficients. Ignore les notes au barème ou coefficient invalide.
    static func weightedAverage(of grades: [Grade]) -> Double? {
        let valid = grades.filter { $0.outOf > 0 && $0.coefficient > 0 }
        guard !valid.isEmpty else { return nil }
        let totalCoefficient = valid.reduce(0) { $0 + $1.coefficient }
        let weightedSum = valid.reduce(0) { $0 + $1.normalizedValue * $1.coefficient }
        return weightedSum / totalCoefficient
    }

    /// Moyenne par matière, triée par nom de matière.
    static func subjectAverages(from grades: [Grade]) -> [SubjectAverage] {
        let groups = Dictionary(grouping: grades, by: { $0.subject.id })
        var result: [SubjectAverage] = []
        for (_, group) in groups {
            guard let first = group.first,
                  let average = weightedAverage(of: group) else { continue }
            result.append(SubjectAverage(subject: first.subject, average: average))
        }
        return result.sorted { $0.subject.name < $1.subject.name }
    }

    /// Moyenne générale = moyenne simple des moyennes de matières (sans coefficient de matière).
    static func generalAverage(of averages: [SubjectAverage]) -> Double? {
        guard !averages.isEmpty else { return nil }
        return averages.reduce(0) { $0 + $1.normalizedAverage } / Double(averages.count)
    }

    /// Dernières notes, de la plus récente à la plus ancienne.
    static func recentGrades(_ grades: [Grade], limit: Int) -> [Grade] {
        Array(grades.sorted { $0.date > $1.date }.prefix(max(0, limit)))
    }
}
