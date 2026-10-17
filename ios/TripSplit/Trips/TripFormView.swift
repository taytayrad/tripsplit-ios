import SwiftUI

/// Add trip and Edit trip. Add trip's Save creates the trip and opens it, where the share sheet invites people
/// (TRIP-40). Edit trip lists each member's amount, then Invite someone new; someone can be removed, or leave, only
/// at $0 (PRD › Net model).
struct TripFormView: View {
    enum Mode { case add, edit(Trip) }
    let mode: Mode
    var onCreated: (Trip) -> Void = { _ in }
    /// Opens Settle up on this trip, from an alert's Pay button (the form closes first).
    var onSettleUp: () -> Void = {}
    /// The trip is gone for you (deleted, or you left): closes the trip's screen along with this sheet.
    var onTripGone: () -> Void = {}

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var name = ""
    @State private var stamp = StampSpec.random()  // a new trip's stamp shows before saving; tap to choose another
    @State private var buildingStamp = false
    @State private var hasDates = false
    @State private var start = Date.now
    @State private var end = Date.now
    @State private var saving = false
    @State private var loaded = false
    @FocusState private var nameFocused: Bool
    private var quick: Animation? { Motion.quick.animation(reduceMotion: reduceMotion) }
    enum DateField { case start, end }
    /// The date whose calendar is open under its row.
    @State private var openDate: DateField?
    @State private var removing: Member?
    @State private var confirmLeave = false
    @State private var confirmDelete = false
    @State private var failure: Failure?

    private var isAdding: Bool { if case .add = mode { true } else { false } }
    private var editing: Trip? { if case .edit(let t) = mode { t } else { nil } }
    private var liveTrip: Trip? { editing.flatMap { app.trip($0.id) } }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    // The stamp and "Edit stamp" are one control: both open the builder (TRIP-39).
                    Button { buildingStamp = true } label: {
                        VStack(spacing: Spacing.sm) {
                            StampAvatar(spec: stamp, size: 96)
                            Text("Edit stamp").foregroundStyle(Color.accentColor)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                    .disabled(saving)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Trip stamp")
                    .accessibilityValue(stamp.spokenName)
                    .accessibilityHint("Double tap to edit the stamp")
                    .accessibilityAddTraits(.isButton)
                    .sheet(isPresented: $buildingStamp) { StampBuilderView(stamp: $stamp) }
                }
                .listRowBackground(Color.clear)

                Section("Name") {
                    TextField("Trip name", text: $name).focused($nameFocused)
                        .submitLabel(.done).onSubmit { nameFocused = false }
                }

                Section {
                    Toggle("Dates", isOn: $hasDates.animation(quick))
                    if hasDates {
                        dateRow("Start", start, .start)
                        if openDate == .start {
                            DatePicker("Start", selection: $start, displayedComponents: .date).datePickerStyle(.graphical).labelsHidden()
                        }
                        dateRow("End", end, .end)
                        if openDate == .end {
                            DatePicker("End", selection: $end, in: Calendar.current.startOfDay(for: start)..., displayedComponents: .date).datePickerStyle(.graphical).labelsHidden()
                        }
                    }
                } footer: { Text("Optional. A start and an end.") }
                // Touching the dates ends editing the name; otherwise the keyboard stays up and keeps typing into it.
                .onChange(of: hasDates) { nameFocused = false; openDate = nil }
                .onChange(of: start) {  // compare days: `start` carries a time of day
                    if Calendar.current.startOfDay(for: end) < Calendar.current.startOfDay(for: start) { end = start }
                }
                .onChange(of: nameFocused) { if nameFocused { withAnimation(quick) { openDate = nil } } }

                if let trip = liveTrip {
                    Section {
                        let nets = SettleUp.memberNets(trip: trip.id, app.settlements)
                        ForEach(trip.members, id: \.userId) { m in
                            let amount = MemberAmount(cents: nets[m.userId] ?? 0, isYou: m.userId == app.userId)
                            HStack {
                                Text(m.userId == app.userId ? "You" : PersonName.shown(m.profiles.displayName))
                                Spacer()
                                VStack(alignment: .trailing, spacing: Spacing.xxs) {
                                    Text(amount.label).font(.footnote).foregroundStyle(Color.tsSecondary)
                                    Text(Money.string(amount.cents)).font(.headline)
                                        .foregroundStyle(amount.cents < 0 ? Color.tsOwe : amount.cents > 0 ? Color.tsOwed : Color.tsSecondary)
                                }
                            }
                            .accessibilityElement(children: .combine)
                                .swipeActions {
                                    if m.userId != app.userId, !saving {
                                        Button("Remove", role: .destructive) { removing = m }
                                    }
                                }
                        }
                    } header: { Text("Members") } footer: {
                        Text("Swipe left on someone to remove them. They can be removed, or leave, once they’re settled up.")
                    }
                    // Its own card, not a row in the list, so it doesn't read as another person.
                    Section {
                        InviteRow(trip: trip).disabled(saving)
                    } footer: {
                        if trip.members.count >= 20 { Text("This trip has 20 people, the most it can hold.") }
                    }
                    Section {
                        Button("Leave trip", role: .destructive) { confirmLeave = true }.disabled(saving)
                        Button("Delete trip", role: .destructive) { confirmDelete = true }.disabled(saving)
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .interactiveDismissDisabled(saving)
            .navigationTitle(isAdding ? "Add trip" : "Edit trip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(saving) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || saving)
                }
            }
            .onAppear {
                guard !loaded else { return }  // load once, so a later appear doesn't undo edits
                loaded = true
                load()
            }
            .alert(removeTitle, isPresented: .init(get: { removing != nil }, set: { if !$0 { removing = nil } }), presenting: removing) { m in
                if net(of: m.userId) == 0 {
                    Button("Cancel", role: .cancel) {}
                    Button("Remove", role: .destructive) { Task { await remove(m) } }
                } else if owesThem(m.userId) {
                    Button("Not now", role: .cancel) {}
                    Button("Pay \(PersonName.shown(m.profiles.displayName))") { settleUp() }
                } else {
                    Button("OK", role: .cancel) {}
                }
            } message: { m in
                Text(net(of: m.userId) == 0 ? "Their past expenses stay as they are." : "Only members with a $0 balance can be removed.")
            }
            .alert(leaveTitle, isPresented: $confirmLeave) {
                let mine = net(of: app.userId)
                if mine == 0 {
                    Button("Cancel", role: .cancel) {}
                    Button("Leave", role: .destructive) { Task { await leave() } }
                } else if mine < 0 {
                    Button("Not now", role: .cancel) {}
                    Button("Pay \(Money.string(mine))") { settleUp() }
                } else {
                    Button("OK", role: .cancel) {}
                }
            } message: { Text(leaveMessage) }
            .alert("Delete this trip?", isPresented: $confirmDelete) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) { Task { await deleteTrip() } }
            } message: { Text("Its balances stop counting. Anyone on the trip can undelete it from Activity.") }
            .failureAlert($failure)
        }
    }

    /// A date row that opens its calendar inline (the Calendar app's pattern). The compact picker's popover hands
    /// focus back to the name when it closes, flashing the keyboard; a plain button ends editing first instead.
    private func dateRow(_ title: String, _ date: Date, _ field: DateField) -> some View {
        Button {
            nameFocused = false
            withAnimation(quick) { openDate = openDate == field ? nil : field }
        } label: {
            HStack {
                Text(title).foregroundStyle(.primary)
                Spacer()
                Text(date.formatted(.dateTime.month(.abbreviated).day().year()))
                    .foregroundStyle(openDate == field ? Color.accentColor : Color.tsSecondary)
            }
        }
        .accessibilityValue(date.formatted(date: .long, time: .omitted))
        .accessibilityHint(openDate == field ? "Double tap to close the calendar" : "Double tap to choose a date")
    }

    private func load() {
        guard let t = editing else { return }
        name = t.name
        stamp = t.stamp
        if let s = t.start, let e = t.end { hasDates = true; start = s; end = e }
    }

    /// Edit trip: save the details. Add trip: create the trip and open it, where the share sheet comes up.
    private func save() async {
        guard !saving else { return }  // a second tap before the first await would create a second trip
        saving = true; defer { saving = false }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        do {
            if let t = editing {
                try await app.updateTrip(t.id, name: trimmed, stamp: stamp == t.stamp ? nil : stamp, start: hasDates ? start : nil, end: hasDates ? end : nil)
            } else {
                onCreated(try await app.createTrip(name: trimmed, stamp: stamp, start: hasDates ? start : nil, end: hasDates ? end : nil))
            }
            dismiss()
        } catch { failure = Failure(title: "Couldn’t save", error: error) { await save() } }
    }

    private func net(of user: UUID?) -> Int {
        guard let trip = editing, let user else { return 0 }
        return SettleUp.memberNets(trip: trip.id, app.settlements)[user] ?? 0
    }

    /// You owe this person something on the trip, so the alert can offer to pay them.
    private func owesThem(_ user: UUID) -> Bool {
        guard let trip = editing else { return false }
        return app.settlements.contains { $0.tripId == trip.id && $0.payerId == app.userId && $0.payeeId == user }
    }

    private var removeTitle: String {
        guard let m = removing else { return "" }
        let name = PersonName.shown(m.profiles.displayName)
        return net(of: m.userId) == 0 ? "Remove \(name)?" : "\(name) can’t be removed yet"
    }

    private var leaveTitle: String {
        net(of: app.userId) == 0 ? "Leave \(editing?.name ?? "this trip")?" : "You can’t leave until you’re settled up"
    }

    private var leaveMessage: String {
        let mine = net(of: app.userId), trip = editing?.name ?? "this trip"
        if mine < 0 { return "You owe \(Money.string(mine)) on \(trip)." }
        if mine > 0 { return "You’re owed \(Money.string(mine)) on \(trip)." }
        return "You’ll stop seeing it, and its invite link won’t let you back in."
    }

    /// Closes the form and opens Settle up on this trip.
    private func settleUp() {
        dismiss()
        onSettleUp()
    }

    private func remove(_ m: Member) async {
        guard let t = editing else { return }
        do { try await app.removeMember(m.userId, from: t.id) }
        catch { failure = Failure(title: "Couldn’t remove them", error: error) { await remove(m) } }
    }

    private func leave() async {
        guard let t = editing else { return }
        do { try await app.leaveTrip(t.id); closeGoneTrip() }
        catch { failure = Failure(title: "Couldn’t leave the trip", error: error) { await leave() } }
    }

    private func deleteTrip() async {
        guard let t = editing else { return }
        do { try await app.deleteTrip(t.id); closeGoneTrip() }
        catch { failure = Failure(title: "Couldn’t delete the trip", error: error) { await deleteTrip() } }
    }

    /// Pops the trip and closes this sheet together while the trip still renders, then refreshes, so the trip
    /// screen doesn't flash blank before it goes.
    private func closeGoneTrip() {
        dismiss()
        onTripGone()
        Task { await app.refresh() }
    }
}
