import SwiftUI

/// Add trip and Edit trip. Adding opens Add members next (members aren't required); you can go back from there to
/// fix the name or dates. People picked in Add members join only on Save (Edit trip) or Done (Add trip).
/// Edit trip lists each member's amount; someone can be removed, or leave, only at $0 (PRD › Net model).
struct TripFormView: View {
    enum Mode { case add, edit(Trip) }
    let mode: Mode
    var onCreated: (Trip) -> Void = { _ in }
    /// Opens Settle up on this trip, from an alert's Pay button (the form closes first).
    var onSettleUp: () -> Void = {}

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var stamp = StampSpec.random()  // a new trip's stamp shows before saving; tap for another
    @State private var hasDates = false
    @State private var start = Date.now
    @State private var end = Date.now
    @State private var saving = false
    /// The trip Add trip saved; from then on the form edits it instead of creating another.
    @State private var created: Trip?
    @State private var showingMembers = false
    /// People picked in Add members, not on the trip until Save or Done.
    @State private var picked: Set<UUID> = []
    @State private var loaded = false
    @FocusState private var nameFocused: Bool
    enum DateField { case start, end }
    /// The date whose calendar is open under its row.
    @State private var openDate: DateField?
    @State private var removing: Member?
    @State private var confirmLeave = false
    @State private var confirmDelete = false
    @State private var error: String?
    @State private var errorTitle = "Couldn’t save"
    /// What Retry in the error alert does again.
    @State private var retry: (() async -> Void)?

    private var isAdding: Bool { if case .add = mode { true } else { false } }
    private var editing: Trip? { if case .edit(let t) = mode { t } else { created } }
    private var liveTrip: Trip? { editing.flatMap { app.trip($0.id) } }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button { withAnimation { stamp = .random() } } label: {
                        StampAvatar(spec: stamp, size: 96).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                    .disabled(saving)
                    .accessibilityLabel("Trip stamp")
                    .accessibilityHint("Double tap for a different stamp")
                }
                .listRowBackground(Color.clear)

                Section("Name") {
                    TextField("Trip name", text: $name).focused($nameFocused)
                        .submitLabel(.done).onSubmit { nameFocused = false }
                }

                Section {
                    Toggle("Dates", isOn: $hasDates.animation())
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
                .onChange(of: nameFocused) { if nameFocused { withAnimation { openDate = nil } } }

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
                        ForEach(pickedPeople(on: trip), id: \.id) { person in
                            HStack {
                                Text(PersonName.shown(person.displayName))
                                Spacer()
                                Text(isAdding ? "Joins when you tap Done" : "Joins when you save").font(.footnote).foregroundStyle(Color.tsSecondary)
                            }
                            .swipeActions { if !saving { Button("Remove", role: .destructive) { picked.remove(person.id) } } }
                        }
                        Button { openMembers() } label: {
                            HStack {
                                Text("Add member").foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Color(.tertiaryLabel))
                            }
                        }
                        .disabled(saving)
                    } header: { Text("Members") } footer: {
                        Text("Swipe left on someone to remove them. They can be removed, or leave, once they’re settled up.")
                    }
                    if !isAdding {
                        Section {
                            Button("Leave trip", role: .destructive) { confirmLeave = true }.disabled(saving)
                        }
                    }
                    Section {
                        Button("Delete trip", role: .destructive) { confirmDelete = true }.disabled(saving)
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .interactiveDismissDisabled(saving)
            .navigationTitle(isAdding ? "Add trip" : "Edit trip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { cancel() }.disabled(saving) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || saving)
                }
            }
            .navigationDestination(isPresented: $showingMembers) {
                if let trip = editing {
                    AddMembersView(tripId: trip.id, picked: $picked, busy: saving, onDone: isAdding ? { Task { await finishAdding(trip) } } : nil)
                }
            }
            .onAppear {
                nameFocused = false  // coming back from Add members shouldn't raise the keyboard
                guard !loaded else { return }  // ...or undo edits made before going there
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
            .alert(errorTitle, isPresented: .init(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("Retry") { Task { await retry?() } }
                Button("Cancel", role: .cancel) {}
            } message: { Text(error ?? "") }
        }
    }

    /// A date row that opens its calendar inline (the Calendar app's pattern). The compact picker's popover hands
    /// focus back to the name when it closes, flashing the keyboard; a plain button ends editing first instead.
    private func dateRow(_ title: String, _ date: Date, _ field: DateField) -> some View {
        Button {
            nameFocused = false
            withAnimation { openDate = openDate == field ? nil : field }
        } label: {
            HStack {
                Text(title).foregroundStyle(.primary)
                Spacer()
                Text(date.formatted(.dateTime.month(.abbreviated).day().year()))
                    .foregroundStyle(openDate == field ? Color.tsTintFill : Color.tsSecondary)
            }
        }
        .accessibilityValue(date.formatted(date: .long, time: .omitted))
        .accessibilityHint(openDate == field ? "Double tap to close the calendar" : "Double tap to choose a date")
    }

    private func pickedPeople(on trip: Trip) -> [Profile] {
        let onTrip = Set(trip.members.map(\.userId))
        return app.people.filter { picked.contains($0.id) && !onTrip.contains($0.id) }.sorted { $0.displayName < $1.displayName }
    }

    private func openMembers() {
        nameFocused = false
        showingMembers = true
    }

    private func load() {
        guard let t = editing else { return }
        name = t.name
        stamp = t.stamp
        if let s = t.start, let e = t.end { hasDates = true; start = s; end = e }
    }

    /// Edit trip: save the details, then add the people picked. Add trip: create the trip (or update the one
    /// already created, after going back) and go to Add members.
    private func save() async {
        guard !saving else { return }  // a second tap before the first await would create a second trip
        saving = true; defer { saving = false }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        retry = { await save() }
        do {
            if let t = editing {
                try await app.updateTrip(t.id, name: trimmed, stamp: stamp == t.stamp ? nil : stamp, start: hasDates ? start : nil, end: hasDates ? end : nil)
                if isAdding { openMembers() } else { try await addPicked(to: t.id); dismiss() }
            } else {
                created = try await app.createTrip(name: trimmed, stamp: stamp, start: hasDates ? start : nil, end: hasDates ? end : nil)
                openMembers()
            }
        } catch { errorTitle = "Couldn’t save"; self.error = AppModel.describe("Check your connection and try again.", error) }
    }

    /// Done in Add members, in the Add trip flow.
    private func finishAdding(_ trip: Trip) async {
        guard !saving else { return }
        saving = true; defer { saving = false }  // picks and navigation are locked until it's done
        retry = { await finishAdding(trip) }
        do {
            try await addPicked(to: trip.id)
            onCreated(trip)
            dismiss()
        } catch { errorTitle = "Couldn’t add everyone"; self.error = AppModel.describe("Check your connection and try again.", error) }
    }

    /// Each person leaves `picked` as soon as they're added, so after a partial failure only the unfinished ones
    /// are retried (and removing someone who did get added isn't undone by a later Save).
    private func addPicked(to trip: UUID) async throws {
        for id in picked {
            guard picked.contains(id) else { continue }  // un-picked since the loop started
            try await app.addMember(id, to: trip)
            picked.remove(id)
        }
    }

    /// Once Add trip has saved the trip, Cancel finishes the flow on it rather than pretending it wasn't made.
    private func cancel() {
        if isAdding, let created { onCreated(created) }
        dismiss()
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
        return "You’ll stop seeing it. Anyone on the trip can add you back."
    }

    /// Closes the form and opens Settle up on this trip.
    private func settleUp() {
        dismiss()
        onSettleUp()
    }

    private func remove(_ m: Member) async {
        guard let t = editing else { return }
        retry = { await remove(m) }
        do { try await app.removeMember(m.userId, from: t.id) }
        catch { errorTitle = "Couldn’t remove them"; self.error = AppModel.describe("Check your connection and try again.", error) }
    }

    private func leave() async {
        guard let t = editing else { return }
        retry = { await leave() }
        do { try await app.leaveTrip(t.id); dismiss() }
        catch { errorTitle = "Couldn’t leave the trip"; self.error = AppModel.describe("Check your connection and try again.", error) }
    }

    private func deleteTrip() async {
        guard let t = editing else { return }
        retry = { await deleteTrip() }
        do { try await app.deleteTrip(t.id); dismiss() }
        catch { errorTitle = "Couldn’t delete the trip"; self.error = AppModel.describe("Check your connection and try again.", error) }
    }
}

/// Share the invite link, or pick people you already share a trip with. Picks join on Save or Done, so a mistaken
/// pick is just unchecked.
struct AddMembersView: View {
    let tripId: UUID
    @Binding var picked: Set<UUID>
    /// True while the picks are being added: they can't change, and you can't leave, until it's done.
    var busy = false
    /// Set in the Add trip flow: Done adds the picks and finishes.
    var onDone: (() -> Void)?
    @Environment(AppModel.self) private var app

    var body: some View {
        if let trip = app.trip(tripId) {
            let onTrip = Set(trip.members.map(\.userId))
            List {
                Section {
                    ShareLink(item: InviteLink.shareURL(token: trip.inviteToken),
                              message: Text("Join “\(trip.name)” on TripSplit so we can split costs")) {
                        Text("Share a link")
                    }
                } footer: { Text("Text it to your friends. The link opens TripSplit, or the App Store first.") }

                Section("Members") {
                    ForEach(trip.members, id: \.userId) { Text($0.userId == app.userId ? "You" : PersonName.shown($0.profiles.displayName)) }
                }

                let known = app.people.filter { !onTrip.contains($0.id) }.sorted { $0.displayName < $1.displayName }
                if !known.isEmpty {
                    Section {
                        ForEach(known, id: \.id) { person in
                            CheckRow(title: PersonName.shown(person.displayName), isOn: .init(
                                get: { picked.contains(person.id) },
                                set: { if $0 { picked.insert(person.id) } else { picked.remove(person.id) } }))
                                .disabled(busy)
                        }
                    } header: { Text("On TripSplit") } footer: {
                        Text(onDone == nil ? "They join when you go back and tap Save." : "They join when you tap Done.")
                    }
                }
            }
            .navigationTitle("Add members")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(busy)
            .toolbar {
                if let onDone {
                    if busy { ProgressView() } else { Button("Done", action: onDone).fontWeight(.semibold) }
                }
            }
            .refreshable { await app.refresh() }
        }
    }
}
