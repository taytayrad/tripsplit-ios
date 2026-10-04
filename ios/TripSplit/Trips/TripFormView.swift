import SwiftUI

/// Add trip and Edit trip. Adding opens Add members next (members aren't required).
struct TripFormView: View {
    enum Mode { case add, edit(Trip) }
    let mode: Mode
    var onCreated: (Trip) -> Void = { _ in }

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var hasDates = false
    @State private var start = Date.now
    @State private var end = Date.now
    @State private var saving = false
    @State private var created: Trip?
    @State private var removing: Member?
    @State private var confirmDelete = false
    @State private var error: String?

    private var editing: Trip? { if case .edit(let t) = mode { t } else { nil } }
    private var liveTrip: Trip? { editing.flatMap { app.trip($0.id) } }

    var body: some View {
        NavigationStack {
            Form {
                if let trip = liveTrip {
                    Section { TripAvatar(trip: trip, size: 96).frame(maxWidth: .infinity) }.listRowBackground(Color.clear)
                }

                Section("Name") { TextField("Trip name", text: $name) }

                Section {
                    Toggle("Dates", isOn: $hasDates.animation())
                    if hasDates {
                        DatePicker("Start", selection: $start, displayedComponents: .date)
                        DatePicker("End", selection: $end, in: start..., displayedComponents: .date)
                    }
                } footer: { Text("Optional. A start and an end.") }

                if let trip = liveTrip {
                    Section("Members") {
                        ForEach(trip.members, id: \.userId) { m in
                            Text(m.userId == app.userId ? "You" : m.profiles.displayName)
                                .swipeActions {
                                    if m.userId != app.userId {
                                        Button("Remove", role: .destructive) { removing = m }
                                    }
                                }
                        }
                        NavigationLink("Add member") { AddMembersView(tripId: trip.id) }
                    }
                    Section {
                        Button("Delete trip", role: .destructive) { confirmDelete = true }
                    }
                }
            }
            .navigationTitle(editing == nil ? "Add trip" : "Edit trip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || saving)
                }
            }
            .navigationDestination(item: $created) { trip in
                AddMembersView(tripId: trip.id, onDone: { onCreated(trip); dismiss() })
            }
            .onAppear(perform: load)
            .confirmationDialog("Remove \(removing?.profiles.displayName ?? "")?", isPresented: .init(get: { removing != nil }, set: { if !$0 { removing = nil } }), titleVisibility: .visible, presenting: removing) { m in
                Button("Keep their balance") { Task { await remove(m, keep: true) } }
                Button("Wipe their balance", role: .destructive) { Task { await remove(m, keep: false) } }
            } message: { _ in
                Text("Keep: what they owe or are owed still counts, and they can still settle up. Wipe: their share is split among everyone else.")
            }
            .alert("Delete this trip?", isPresented: $confirmDelete) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) { Task { await deleteTrip() } }
            } message: { Text("Its balances stop counting. Anyone on the trip can undelete it from Activity.") }
            .alert("Couldn’t save", isPresented: .init(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("Retry") { Task { await save() } }
                Button("Cancel", role: .cancel) {}
            } message: { Text(error ?? "") }
        }
    }

    private func load() {
        guard let t = editing else { return }
        name = t.name
        if let s = t.start, let e = t.end { hasDates = true; start = s; end = e }
    }

    private func save() async {
        saving = true; defer { saving = false }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        do {
            if let t = editing {
                try await app.updateTrip(t.id, name: trimmed, start: hasDates ? start : nil, end: hasDates ? end : nil)
                dismiss()
            } else {
                created = try await app.createTrip(name: trimmed, start: hasDates ? start : nil, end: hasDates ? end : nil)
            }
        } catch { self.error = AppModel.describe("Check your connection and try again.", error) }
    }

    private func remove(_ m: Member, keep: Bool) async {
        guard let t = editing else { return }
        do { try await app.removeMember(m.userId, from: t.id, keepBalance: keep) } catch { self.error = AppModel.describe("Couldn’t remove them. Try again.", error) }
    }

    private func deleteTrip() async {
        guard let t = editing else { return }
        do { try await app.deleteTrip(t.id); dismiss() } catch { self.error = AppModel.describe("Couldn’t delete the trip. Try again.", error) }
    }
}

struct AddMembersView: View {
    let tripId: UUID
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
                    ForEach(trip.members, id: \.userId) { Text($0.userId == app.userId ? "You" : $0.profiles.displayName) }
                }

                let known = app.people.filter { !onTrip.contains($0.id) }
                if !known.isEmpty {
                    Section("On TripSplit") {
                        ForEach(known, id: \.id) { person in
                            HStack {
                                Text(person.displayName)
                                Spacer()
                                Button("Add") { Task { try? await app.addMember(person.id, to: trip.id) } }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Add members")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(onDone != nil)
            .toolbar {
                if let onDone { Button("Done", action: onDone).fontWeight(.semibold) }
            }
            .refreshable { await app.refresh() }
        }
    }
}
