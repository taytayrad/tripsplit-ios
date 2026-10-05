import SwiftUI
import UIKit

/// Add trip and Edit trip. Adding opens Add members next (members aren't required); you can go back from there to
/// fix the name or dates. People picked in Add members join only on Save (Edit trip) or Done (Add trip).
struct TripFormView: View {
    enum Mode { case add, edit(Trip) }
    let mode: Mode
    var onCreated: (Trip) -> Void = { _ in }

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var stamp = StampSpec.random()  // the new trip's stamp, shown before saving
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
    @State private var removing: Member?
    @State private var confirmDelete = false
    @State private var error: String?
    /// What Retry in the error alert does again.
    @State private var retry: (() async -> Void)?

    private var isAdding: Bool { if case .add = mode { true } else { false } }
    private var editing: Trip? { if case .edit(let t) = mode { t } else { created } }
    private var liveTrip: Trip? { editing.flatMap { app.trip($0.id) } }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if let live = liveTrip {
                        StampAvatar(spec: live.stamp, size: 96).frame(maxWidth: .infinity)
                    } else {
                        Button { withAnimation { stamp = .random() } } label: {
                            StampAvatar(spec: stamp, size: 96).frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Trip stamp")
                        .accessibilityHint("Double tap for a different stamp")
                    }
                }
                .listRowBackground(Color.clear)

                Section("Name") {
                    TextField("Trip name", text: $name).focused($nameFocused)
                        .submitLabel(.done).onSubmit { nameFocused = false }
                }

                Section {
                    Toggle("Dates", isOn: $hasDates.animation())
                    if hasDates {
                        DatePicker("Start", selection: $start, displayedComponents: .date).simultaneousGesture(endEditingOnTouch)
                        DatePicker("End", selection: $end, in: start..., displayedComponents: .date).simultaneousGesture(endEditingOnTouch)
                    }
                } footer: { Text("Optional. A start and an end.") }
                // Touching the dates ends editing the name; otherwise the keyboard stays up and keeps typing into it.
                .onChange(of: hasDates) { nameFocused = false }

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
                        ForEach(pickedPeople(on: trip), id: \.id) { person in
                            HStack {
                                Text(person.displayName)
                                Spacer()
                                Text(isAdding ? "Joins when you tap Done" : "Joins when you save").font(.footnote).foregroundStyle(Color.tsSecondary)
                            }
                            .swipeActions { Button("Remove", role: .destructive) { picked.remove(person.id) } }
                        }
                        Button { openMembers() } label: {
                            HStack {
                                Text("Add member").foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Color(.tertiaryLabel))
                            }
                        }
                    }
                    Section {
                        Button("Delete trip", role: .destructive) { confirmDelete = true }
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(isAdding ? "Add trip" : "Edit trip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { cancel() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || saving)
                }
            }
            .navigationDestination(isPresented: $showingMembers) {
                if let trip = editing {
                    AddMembersView(tripId: trip.id, picked: $picked, onDone: isAdding ? { Task { await finishAdding(trip) } } : nil)
                }
            }
            .onAppear {
                nameFocused = false  // coming back from Add members shouldn't raise the keyboard
                guard !loaded else { return }  // ...or undo edits made before going there
                loaded = true
                load()
            }
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
                Button("Retry") { Task { await retry?() } }
                Button("Cancel", role: .cancel) {}
            } message: { Text(error ?? "") }
        }
    }

    /// A date picker's calendar hands focus back to whatever had it when it opened, so the name has to let go on
    /// touch-down, before the calendar appears, or the keyboard returns when the calendar closes.
    private var endEditingOnTouch: some Gesture {
        DragGesture(minimumDistance: 0).onChanged { _ in
            guard nameFocused else { return }
            nameFocused = false
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
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
        if let s = t.start, let e = t.end { hasDates = true; start = s; end = e }
    }

    /// Edit trip: save the details, then add the people picked. Add trip: create the trip (or update the one
    /// already created, after going back) and go to Add members.
    private func save() async {
        saving = true; defer { saving = false }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        retry = { await save() }
        do {
            if let t = editing {
                try await app.updateTrip(t.id, name: trimmed, start: hasDates ? start : nil, end: hasDates ? end : nil)
                if isAdding { openMembers() } else { try await addPicked(to: t.id); dismiss() }
            } else {
                created = try await app.createTrip(name: trimmed, stamp: stamp, start: hasDates ? start : nil, end: hasDates ? end : nil)
                openMembers()
            }
        } catch { self.error = AppModel.describe("Check your connection and try again.", error) }
    }

    /// Done in Add members, in the Add trip flow.
    private func finishAdding(_ trip: Trip) async {
        retry = { await finishAdding(trip) }
        do {
            try await addPicked(to: trip.id)
            onCreated(trip)
            dismiss()
        } catch { self.error = AppModel.describe("Couldn’t add everyone. Check your connection and try again.", error) }
    }

    /// Adding someone already on the trip does nothing, so a retry after a partial failure is safe.
    private func addPicked(to trip: UUID) async throws {
        for id in picked { try await app.addMember(id, to: trip) }
        picked = []
    }

    /// Once Add trip has saved the trip, Cancel finishes the flow on it rather than pretending it wasn't made.
    private func cancel() {
        if isAdding, let created { onCreated(created) }
        dismiss()
    }

    private func remove(_ m: Member, keep: Bool) async {
        guard let t = editing else { return }
        retry = { await remove(m, keep: keep) }
        do { try await app.removeMember(m.userId, from: t.id, keepBalance: keep) } catch { self.error = AppModel.describe("Couldn’t remove them. Try again.", error) }
    }

    private func deleteTrip() async {
        guard let t = editing else { return }
        retry = { await deleteTrip() }
        do { try await app.deleteTrip(t.id); dismiss() } catch { self.error = AppModel.describe("Couldn’t delete the trip. Try again.", error) }
    }
}

/// Share the invite link, or pick people you already share a trip with. Picks join on Save or Done, so a mistaken
/// pick is just unchecked.
struct AddMembersView: View {
    let tripId: UUID
    @Binding var picked: Set<UUID>
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
                    ForEach(trip.members, id: \.userId) { Text($0.userId == app.userId ? "You" : $0.profiles.displayName) }
                }

                let known = app.people.filter { !onTrip.contains($0.id) }.sorted { $0.displayName < $1.displayName }
                if !known.isEmpty {
                    Section {
                        ForEach(known, id: \.id) { person in
                            CheckRow(title: person.displayName, isOn: .init(
                                get: { picked.contains(person.id) },
                                set: { if $0 { picked.insert(person.id) } else { picked.remove(person.id) } }))
                        }
                    } header: { Text("On TripSplit") } footer: {
                        Text(onDone == nil ? "They join when you go back and tap Save." : "They join when you tap Done.")
                    }
                }
            }
            .navigationTitle("Add members")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if let onDone { Button("Done", action: onDone).fontWeight(.semibold) }
            }
            .refreshable { await app.refresh() }
        }
    }
}
