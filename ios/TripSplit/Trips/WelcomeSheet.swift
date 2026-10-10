import SwiftUI

/// After joining from a link: "Taylor added you to a trip!" (PRD › Prototype decisions › Joining from a link)
struct WelcomeSheet: View {
    let trip: Trip
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    private var inviter: String {
        trip.tripMembers.first { $0.userId == trip.createdBy }?.profiles.displayName.nilIfEmpty.map(PersonName.shown) ?? "A friend"
    }
    private var meta: String {
        let names = trip.members.map { $0.userId == app.userId ? "You" : PersonName.shown($0.profiles.displayName) }
        let people = ListFormatter.localizedString(byJoining: names)
        guard let s = trip.start, let e = trip.end else { return people }
        return "\(DayFormat.range(s, e)) · \(people)"
    }

    var body: some View {
        VStack(spacing: Spacing.sm) {
            HStack {
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark").font(.body.weight(.semibold)) }
                    .foregroundStyle(Color.tsSecondary).frame(width: 44, height: 44).accessibilityLabel("Close")
            }
            StampView(spec: trip.stamp).frame(width: 168)
            Text("\(inviter) added you to a trip!").font(.title3.weight(.semibold)).multilineTextAlignment(.center)
            Text(trip.name).font(.title2.bold())
            Text(meta).font(.subheadline).foregroundStyle(Color.tsSecondary).multilineTextAlignment(.center)
            Spacer().frame(height: Spacing.md)
            Button("View Trips") { dismiss() }.buttonStyle(PrimaryButtonStyle())
            Button("Add expense") { dismiss(); app.addExpense(on: trip.id) }.buttonStyle(SecondaryButtonStyle())
        }
        .padding([.horizontal, .bottom], Spacing.xl)
        .padding(.top, Spacing.sm)
        .presentationDetents([.medium, .large])
    }
}
