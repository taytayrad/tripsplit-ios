import SwiftUI

/// The Activity tab (Figma Activity › Feed [12b]): your activity, newest first, including a deleted trip's rows.
/// Search filters it by person, expense, or trip. Tapping an expense row opens its details, and a trip or member
/// row opens the trip (TRIP-20). A deleted trip's row asks to undelete it (TRIP-21). An empty feed stays plain
/// until Phase 6.
struct ActivityView: View {
    @Binding var path: [ActivityEvent.Target]
    @Environment(AppModel.self) private var app
    @State private var addingTrip = false
    @State private var settling = false
    @State private var query = ""
    /// The deleted trip whose undelete alert is showing (Figma Activity › Undelete alert [12c]).
    @State private var undeleting: ActivityEvent?

    var body: some View {
        NavigationStack(path: $path) {
            let expenseIds = Set(app.expenses.map(\.id)), tripIds = Set(app.trips.map(\.id))
            List(app.activity.filter { $0.matches(query) }) { event in
                Group {
                    if let target = event.target(expenses: expenseIds, trips: tripIds) {
                        // Tinted primary: a List button otherwise draws its label in the accent blue. Keeps the tap highlight.
                        Button { open(target, event) } label: { ActivityRow(event: event, line: line(event)) }
                            .tint(.primary)
                    } else {
                        ActivityRow(event: event, line: line(event))
                    }
                }
                    .listRowInsets(EdgeInsets(top: Spacing.md, leading: Spacing.lg, bottom: Spacing.md, trailing: Spacing.lg))
                    .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }  // Figma: separators run the row's full width
            }
            .listStyle(.insetGrouped)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always))  // Figma: always under the title
            .overlay {
                if app.activity.isEmpty {
                    Text("No activity yet").font(.subheadline).foregroundStyle(Color.tsSecondary)
                } else if !app.activity.contains(where: { $0.matches(query) }) {
                    ContentUnavailableView.search(text: query)
                }
            }
            .navigationTitle("Activity")
            .toolbar { MainHeader(onAddTrip: { addingTrip = true }, onSettleUp: { settling = true }) }
            .navigationDestination(isPresented: $settling) { SettleUpView(startTrip: nil) }
            .navigationDestination(for: ActivityEvent.Target.self) { target in
                switch target {
                case .trip(let id): TripDetailView(tripId: id)
                case .expense(let id): ExpenseDetailView(expenseId: id)
                case .activity, .undelete: EmptyView()
                }
            }
            .alert("Do you want to undelete this trip?", isPresented: .init(get: { undeleting != nil }, set: { if !$0 { undeleting = nil } }),
                   presenting: undeleting) { event in
                Button("Cancel", role: .cancel) {}
                Button("Undelete") {
                    Task {
                        do { try await app.undeleteTrip(event.tripId) }
                        catch { app.error = AppModel.describe("Couldn’t undelete the trip. Check your connection and try again.", error) }
                    }
                }
                .keyboardShortcut(.defaultAction)
            } message: { event in Text("“\(event.tripName)” and its expenses will count again.") }
            .refreshable { await app.refresh() }
            .sheet(isPresented: $addingTrip) {
                TripFormView(mode: .add) { created in path = [.trip(created.id)] }
            }
        }
    }

    private func open(_ target: ActivityEvent.Target, _ event: ActivityEvent) {
        switch target {
        case .expense, .trip: path.append(target)
        case .undelete: undeleting = event
        case .activity: path = []
        }
    }

    private func line(_ event: ActivityEvent) -> ActivityCopy.Result {
        event.statement(viewer: app.userId ?? UUID(), viewerName: app.profile?.displayName ?? "", expenses: app.expenses)
    }
}

/// Figma Activity Row: the trip's stamp, the statement, the dollar line when there is one, then the time.
struct ActivityRow: View {
    let event: ActivityEvent
    let line: ActivityCopy.Result

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            StampAvatar(spec: event.stamp, size: 36)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(line.statement).font(.callout)
                Group {
                    if let dollar = line.dollarLine { Text(dollar) }
                    Text(ActivityTime.string(event.createdAt))
                }
                .font(.footnote).foregroundStyle(Color.tsSecondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Activity timestamps (docs/events.md): today shows the time only ("9:12 AM"); an earlier day shows a short date
/// and time ("Oct 1, 6:40 PM"), with the year when it isn't this year.
enum ActivityTime {
    static func string(_ date: Date, now: Date = .now, calendar: Calendar = .current, locale: Locale = .current) -> String {
        let base = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
        let time = date.formatted(base.hour().minute())
        if calendar.isDate(date, inSameDayAs: now) { return time }
        var day = base.month(.abbreviated).day()
        if !calendar.isDate(date, equalTo: now, toGranularity: .year) { day = day.year() }
        // Joined by hand: one combined style reads "Oct 1 at 6:40 PM", and Figma says "Oct 1, 6:40 PM".
        return "\(date.formatted(day)), \(time)"
    }
}
