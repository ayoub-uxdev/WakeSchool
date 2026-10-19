import SwiftUI

/// Grille mensuelle : en-tête des jours de la semaine et cellules de jour.
struct CalendarMonthView: View {
    let month: Date
    let selectedDate: Date
    let coursesByDay: [Date: [TimetableEntry]]
    let onDateSelected: (Date) -> Void

    private let calendar = Calendar.current
    private let weekdaySymbols: [String]

    init(month: Date, selectedDate: Date, coursesByDay: [Date: [TimetableEntry]], onDateSelected: @escaping (Date) -> Void) {
        self.month = month
        self.selectedDate = selectedDate
        self.coursesByDay = coursesByDay
        self.onDateSelected = onDateSelected

        var cal = Calendar(identifier: .gregorian)
        cal.locale = Locale(identifier: "fr_FR")
        cal.timeZone = TimeZone(identifier: "UTC")!
        self.weekdaySymbols = cal.veryShortStandaloneWeekdaySymbols
    }

    var body: some View {
        VStack(spacing: 8) {
            // En-tête des jours de la semaine
            HStack(spacing: 0) {
                ForEach(weekdaySymbols, id: \.self) { symbol in
                    Text(symbol.uppercased())
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.6))
                        .frame(maxWidth: .infinity)
                }
            }

            // Grille des jours
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
                ForEach(daysInMonth, id: \.self) { day in
                    if let day = day {
                        CalendarDayCell(
                            date: day,
                            isSelected: calendar.isDate(day, inSameDayAs: selectedDate),
                            hasCourses: hasCourses(on: day),
                            courseStatus: status(on: day)
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(.snappy) { onDateSelected(day) }
                        }
                    } else {
                        Color.clear.frame(height: 44)
                    }
                }
            }
        }
    }

    // MARK: - Données du mois

    private var daysInMonth: [Date?] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: month) else { return [] }
        let firstDay = monthInterval.start
        let firstWeekday = calendar.component(.weekday, from: firstDay)

        var days: [Date?] = []
        // Cases vides avant le premier jour du mois
        let offset = (firstWeekday - calendar.firstWeekday + 7) % 7
        for _ in 0..<offset { days.append(nil) }

        var current = firstDay
        while calendar.isDate(current, equalTo: month, toGranularity: .month) {
            days.append(current)
            current = calendar.date(byAdding: .day, value: 1, to: current)!
        }
        return days
    }

    private func hasCourses(on date: Date) -> Bool {
        coursesByDay[calendar.startOfDay(for: date)]?.isEmpty == false
    }

    private func status(on date: Date) -> CourseStatus? {
        guard let entries = coursesByDay[calendar.startOfDay(for: date)] else { return nil }
        if entries.contains(where: { $0.isCancelled }) { return .cancelled }
        if entries.contains(where: { $0.isModified }) { return .modified }
        return .normal
    }
}
