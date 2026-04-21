import SwiftUI
import FirebaseFirestore
import FirebaseAuth
import UIKit

// MARK: - 1. Note Model
struct Note: Identifiable {
    var id: String
    var title: String
    var content: String
    var createdAt: Date
    var updatedAt: Date
    var isPinned: Bool
}

// MARK: - 2. Firestore Manager (ViewModel)
class FirestoreManager: ObservableObject {
    @Published var notes: [Note] = []
    @Published var errorMessage: String?
    
    // Reference to our Firestore database
    private var db = Firestore.firestore()
    private var notesListener: ListenerRegistration?
    
    deinit {
        notesListener?.remove()
    }
    
    private var userNotesCollection: CollectionReference? {
        guard let uid = Auth.auth().currentUser?.uid else { return nil }
        return db.collection("users").document(uid).collection("notes")
    }

    private func friendlyErrorMessage(for error: Error) -> String {
        let nsError = error as NSError
        if nsError.domain == FirestoreErrorDomain,
           nsError.code == FirestoreErrorCode.permissionDenied.rawValue {
            return "Permission denied for notes. Update Firestore Rules to allow users to access only their own notes."
        }
        return error.localizedDescription
    }
    
    // Fetch notes with a real-time listener
    func fetchNotes() {
        guard let uid = Auth.auth().currentUser?.uid, let collection = userNotesCollection else {
            clearNotes()
            errorMessage = "Login required to load notes."
            return
        }
        
        notesListener?.remove()
        notesListener = collection.whereField("ownerId", isEqualTo: uid).addSnapshotListener { (querySnapshot, error) in
            // Basic error handling
            if let error = error {
                print("Error getting notes: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.errorMessage = self.friendlyErrorMessage(for: error)
                }
                return
            }
            
            // Safely unwrap documents
            guard let documents = querySnapshot?.documents else { return }
            
            // Map the Firestore documents into our Swift 'Note' array
            let loadedNotes = documents.map { queryDocumentSnapshot -> Note in
                let data = queryDocumentSnapshot.data()
                let title = data["title"] as? String ?? ""
                let content = data["content"] as? String ?? ""
                let createdAt = (data["createdAt"] as? Timestamp)?.dateValue() ?? Date(timeIntervalSince1970: 0)
                let updatedAt = (data["updatedAt"] as? Timestamp)?.dateValue() ?? createdAt
                let isPinned = data["isPinned"] as? Bool ?? false

                return Note(
                    id: queryDocumentSnapshot.documentID,
                    title: title,
                    content: content,
                    createdAt: createdAt,
                    updatedAt: updatedAt,
                    isPinned: isPinned
                )
            }

            DispatchQueue.main.async {
                withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                    self.notes = loadedNotes
                    self.errorMessage = nil
                }
            }
        }
    }
    
    func clearNotes() {
        notesListener?.remove()
        notesListener = nil
        notes = []
        errorMessage = nil
    }
    
    // Add a new note to Firestore
    func addNote(title: String, content: String) {
        guard let uid = Auth.auth().currentUser?.uid, let collection = userNotesCollection else {
            errorMessage = "Login required to create notes."
            return
        }
        
        collection.addDocument(data: [
            "title": title,
            "content": content,
            "isPinned": false,
            "ownerId": uid,
            "createdAt": FieldValue.serverTimestamp(),
            "updatedAt": FieldValue.serverTimestamp()
        ]) { error in
            if let error = error {
                DispatchQueue.main.async {
                    self.errorMessage = self.friendlyErrorMessage(for: error)
                }
            }
        }
    }
    
    // Delete a note from Firestore
    func deleteNote(note: Note) {
        guard let collection = userNotesCollection else {
            errorMessage = "Login required to delete notes."
            return
        }
        
        collection.document(note.id).delete { error in
            if let error = error {
                DispatchQueue.main.async {
                    self.errorMessage = self.friendlyErrorMessage(for: error)
                }
            }
        }
    }
    
    // Update an existing note in Firestore
    func updateNote(note: Note, newTitle: String, newContent: String) {
        guard let collection = userNotesCollection else {
            errorMessage = "Login required to update notes."
            return
        }
        
        collection.document(note.id).updateData([
            "title": newTitle,
            "content": newContent,
            "updatedAt": FieldValue.serverTimestamp()
        ]) { error in
            if let error = error {
                DispatchQueue.main.async {
                    self.errorMessage = self.friendlyErrorMessage(for: error)
                }
            }
        }
    }

    // Toggle pin/favorite state for a note
    func togglePin(note: Note) {
        guard let collection = userNotesCollection else {
            errorMessage = "Login required to pin notes."
            return
        }

        collection.document(note.id).updateData([
            "isPinned": !note.isPinned,
            "updatedAt": FieldValue.serverTimestamp()
        ]) { error in
            if let error = error {
                DispatchQueue.main.async {
                    self.errorMessage = self.friendlyErrorMessage(for: error)
                }
            }
        }
    }
}

private enum NotesSortOption: String, CaseIterable, Identifiable {
    case newest = "Newest"
    case oldest = "Oldest"

    var id: String { rawValue }
}

// MARK: - 3. Target Notes View
struct NotesView: View {
    @StateObject private var firestoreManager = FirestoreManager()
    @EnvironmentObject var authViewModel: AuthViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.presentationMode) private var presentationMode

    @State private var showAddNote = false
    @State private var showLoginSheet = false
    @State private var selectedNoteId: String?
    @State private var editingNote: Note?
    @State private var searchText = ""
    @State private var sortOption: NotesSortOption = .newest
    @State private var didShowHeader = false
    @State private var animateEmptyIcon = false
    @State private var addButtonPressed = false
    
    var body: some View {
        Group {
            if !authViewModel.isLoggedIn {
                LoginRequiredView(
                    message: "My Notes is available for logged-in users only."
                ) {
                    showLoginSheet = true
                }
            } else {
                ZStack(alignment: .bottomTrailing) {
                    notesBackground
                        .ignoresSafeArea()

                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 14) {
                            headerSection
                            searchAndSortSection

                            if let error = firestoreManager.errorMessage {
                                Text(error)
                                    .font(.footnote)
                                    .foregroundColor(.red)
                                    .padding(10)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(.ultraThinMaterial)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .stroke(Color.red.opacity(0.24), lineWidth: 1)
                                    )
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }

                            if displayedNotes.isEmpty {
                                emptyState
                            } else {
                                ForEach(Array(displayedNotes.enumerated()), id: \.element.id) { index, note in
                                    NoteCardView(
                                        note: note,
                                        accentColor: accentColor,
                                        cardColor: cardColor,
                                        appearDelay: Double(index) * 0.06,
                                        onOpen: {
                                            openNoteDetail(note)
                                        },
                                        onEdit: {
                                            editNote(note)
                                        },
                                        onDelete: {
                                            deleteNote(note)
                                        },
                                        onPinToggle: {
                                            togglePin(for: note)
                                        }
                                    )
                                    .transition(.move(edge: .bottom).combined(with: .opacity))
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .tabBarOverlayBottomPadding(extra: 94)
                        .animation(.spring(response: 0.36, dampingFraction: 0.8), value: displayedNotes.map(\.id))
                    }

                    floatingAddButton
                        .padding(.trailing, 16)
                        .padding(.bottom, 88)
                }
                .background(detailNavigationLink)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarHidden(authViewModel.isLoggedIn)
        .sheet(item: $editingNote) { note in
            NavigationView {
                EditNoteView(firestoreManager: firestoreManager, note: note)
            }
        }
        .sheet(isPresented: $showAddNote) {
            AddNoteView(firestoreManager: firestoreManager)
        }
        .sheet(isPresented: $showLoginSheet) {
            LoginView(showGuestDismiss: true)
                .environmentObject(authViewModel)
        }
        // Fetch our notes as soon as the screen opens
        .onAppear {
            if authViewModel.isLoggedIn {
                firestoreManager.fetchNotes()
            }

            if !didShowHeader {
                withAnimation(.easeOut(duration: 0.34)) {
                    didShowHeader = true
                }
            }

            if !animateEmptyIcon {
                animateEmptyIcon = true
            }
        }
        .onChange(of: authViewModel.isLoggedIn) { isLoggedIn in
            if isLoggedIn {
                firestoreManager.fetchNotes()
            } else {
                firestoreManager.clearNotes()
            }
        }
    }

    private var displayedNotes: [Note] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        let filtered = firestoreManager.notes.filter { note in
            guard !query.isEmpty else { return true }
            return note.title.lowercased().contains(query) || note.content.lowercased().contains(query)
        }

        return filtered.sorted { lhs, rhs in
            if lhs.isPinned != rhs.isPinned {
                return lhs.isPinned && !rhs.isPinned
            }

            switch sortOption {
            case .newest:
                return lhs.updatedAt > rhs.updatedAt
            case .oldest:
                return lhs.updatedAt < rhs.updatedAt
            }
        }
    }

    private var selectedNote: Note? {
        guard let selectedNoteId else { return nil }
        return firestoreManager.notes.first(where: { $0.id == selectedNoteId })
    }

    private var detailNavigationLink: some View {
        NavigationLink(
            destination: Group {
                if let note = selectedNote {
                    NoteDetailView(firestoreManager: firestoreManager, note: note)
                } else {
                    EmptyView()
                }
            },
            isActive: Binding(
                get: { selectedNoteId != nil },
                set: { isActive in
                    if !isActive {
                        selectedNoteId = nil
                    }
                }
            )
        ) {
            EmptyView()
        }
        .hidden()
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                if presentationMode.wrappedValue.isPresented {
                    Button {
                        HapticFeedback.tap(.light)
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(AppTheme.titleText)
                            .frame(width: 40, height: 40)
                            .background(.ultraThinMaterial)
                            .overlay(
                                Circle()
                                    .stroke(Color.white.opacity(0.14), lineWidth: 1)
                            )
                            .clipShape(Circle())
                            .shadow(color: Color.black.opacity(0.16), radius: 8, x: 0, y: 5)
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 6)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("My Notes")
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(AppTheme.titleText)
                        .opacity(didShowHeader ? 1 : 0)
                        .offset(y: didShowHeader ? 0 : 8)
                        .animation(.easeOut(duration: 0.32), value: didShowHeader)

                    Text("\(firestoreManager.notes.count) notes")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.subtitleText)
                        .opacity(didShowHeader ? 1 : 0)
                        .offset(y: didShowHeader ? 0 : 6)
                        .animation(.easeOut(duration: 0.4), value: didShowHeader)
                }

                Spacer()

                Button {
                    HapticFeedback.tap(.light)
                    showAddNote = true
                } label: {
                    Label("New", systemImage: "plus")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(accentColor)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial)
                        .overlay(
                            Capsule()
                                .stroke(Color.white.opacity(0.14), lineWidth: 1)
                        )
                        .clipShape(Capsule())
                        .shadow(color: accentColor.opacity(0.28), radius: 10, x: 0, y: 0)
                }
                .buttonStyle(SpringyButtonStyle())
                .opacity(didShowHeader ? 1 : 0)
                .offset(y: didShowHeader ? 0 : 8)
                .animation(.easeOut(duration: 0.36), value: didShowHeader)
            }
        }
    }

    private var searchAndSortSection: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(AppTheme.subtitleText)

                TextField("Search notes", text: $searchText)
                    .textInputAutocapitalization(.sentences)
                    .disableAutocorrection(true)

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(AppTheme.subtitleText)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            Picker("Sort", selection: $sortOption) {
                ForEach(NotesSortOption.allCases) { option in
                    Text(option.rawValue).tag(option)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "note.text")
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(accentColor)
                .offset(y: animateEmptyIcon ? -3 : 3)
                .animation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true), value: animateEmptyIcon)

            Text("No notes yet")
                .font(.headline)
                .foregroundStyle(AppTheme.titleText)

            Text("Tap + to create your first note.")
                .font(.subheadline)
                .foregroundStyle(AppTheme.subtitleText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 26)
        .glassCard(cornerRadius: 22)
    }

    private var floatingAddButton: some View {
        Button {
            HapticFeedback.tap(.medium)

            withAnimation(.spring(response: 0.24, dampingFraction: 0.66)) {
                addButtonPressed = true
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                addButtonPressed = false
                showAddNote = true
            }
        } label: {
            Image(systemName: "plus")
                .font(.title3.weight(.bold))
                .foregroundStyle(accentColor)
                .frame(width: 56, height: 56)
                .background(.ultraThinMaterial)
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.18), lineWidth: 1)
                )
                .clipShape(Circle())
                .shadow(color: Color.black.opacity(0.18), radius: 12, x: 0, y: 7)
                .shadow(color: accentColor.opacity(0.42), radius: 16, x: 0, y: 0)
        }
        .scaleEffect(addButtonPressed ? 0.9 : 1)
        .animation(.spring(response: 0.28, dampingFraction: 0.68), value: addButtonPressed)
    }

    private var notesBackground: some View {
        ZStack {
            backgroundColor

            LinearGradient(
                colors: [backgroundColor, Color.black.opacity(0.05)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(accentColor.opacity(0.17))
                .frame(width: 220, height: 220)
                .blur(radius: 34)
                .offset(x: 120, y: -220)
        }
    }

    private var backgroundColor: Color {
        UIColor(named: "Background") == nil ? AppTheme.background : Color("Background")
    }

    private var cardColor: Color {
        UIColor(named: "Card") == nil ? AppTheme.cardBackground : Color("Card")
    }

    private var accentColor: Color {
        UIColor(named: "Accent") == nil ? AppTheme.accentPrimary : Color("Accent")
    }

    private func openNoteDetail(_ note: Note) {
        HapticFeedback.tap(.light)
        selectedNoteId = note.id
    }

    private func editNote(_ note: Note) {
        HapticFeedback.tap(.light)
        editingNote = note
    }

    private func deleteNote(_ note: Note) {
        HapticFeedback.tap(.medium)
        firestoreManager.deleteNote(note: note)
    }

    private func togglePin(for note: Note) {
        HapticFeedback.tap(.light)
        firestoreManager.togglePin(note: note)
    }
}

private struct NoteCardView: View {
    let note: Note
    let accentColor: Color
    let cardColor: Color
    var appearDelay: Double = 0
    let onOpen: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onPinToggle: () -> Void

    @State private var didAppear = false
    @State private var isPressed = false
    @State private var horizontalOffset: CGFloat = 0

    private let cornerRadius: CGFloat = 20

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text(note.title.isEmpty ? "Untitled Note" : note.title)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(AppTheme.titleText)
                    .lineLimit(1)

                Spacer(minLength: 0)

                if note.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(accentColor)
                }
            }

            Text(note.content.isEmpty ? "No content yet" : note.content)
                .font(.subheadline)
                .foregroundStyle(AppTheme.subtitleText)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            HStack(spacing: 8) {
                NoteActionIconButton(icon: "pencil", tint: .blue, action: onEdit)
                NoteActionIconButton(icon: "trash", tint: .red, action: onDelete)
                NoteActionIconButton(icon: note.isPinned ? "pin.slash.fill" : "pin.fill", tint: accentColor, action: onPinToggle)

                Spacer()

                Button(action: onOpen) {
                    Image(systemName: "arrow.up.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(AppTheme.subtitleText)
                        .frame(width: 28, height: 28)
                        .background(AppTheme.cardBackground.opacity(0.28))
                        .clipShape(Capsule())
                }
                .buttonStyle(SpringyButtonStyle())
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        }
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(
                    RadialGradient(
                        colors: [Color.white.opacity(isPressed ? 0.16 : 0), .clear],
                        center: .center,
                        startRadius: 1,
                        endRadius: 220
                    )
                )
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .shadow(color: Color.black.opacity(0.12), radius: 12, x: 0, y: 8)
        .shadow(color: accentColor.opacity(0.15), radius: 12, x: 0, y: 0)
        .scaleEffect(isPressed ? 0.96 : 1)
        .offset(x: horizontalOffset)
        .opacity(didAppear ? 1 : 0)
        .offset(y: didAppear ? 0 : 10)
        .animation(.easeOut(duration: 0.32).delay(appearDelay), value: didAppear)
        .animation(.spring(response: 0.26, dampingFraction: 0.74), value: isPressed)
        .animation(.spring(response: 0.28, dampingFraction: 0.8), value: horizontalOffset)
        .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .onLongPressGesture(minimumDuration: 0, maximumDistance: 30, pressing: { pressing in
            isPressed = pressing
        }, perform: {})
        .onTapGesture {
            onOpen()
        }
        .gesture(
            DragGesture(minimumDistance: 14)
                .onChanged { value in
                    guard abs(value.translation.width) > abs(value.translation.height) else { return }
                    horizontalOffset = max(-88, min(88, value.translation.width))
                }
                .onEnded { value in
                    guard abs(value.translation.width) > abs(value.translation.height) else {
                        horizontalOffset = 0
                        return
                    }

                    if value.translation.width <= -86 {
                        triggerSwipeAction(targetOffset: -70, action: onDelete)
                    } else if value.translation.width >= 86 {
                        triggerSwipeAction(targetOffset: 70, action: onEdit)
                    } else {
                        horizontalOffset = 0
                    }
                }
        )
        .onAppear {
            if !didAppear {
                didAppear = true
            }
        }
    }

    private var cardBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(cardColor.opacity(0.36))

            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.ultraThinMaterial)

            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.black.opacity(0.24), Color.black.opacity(0.08)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [accentColor.opacity(0.2), Color.clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .blur(radius: 12)
                .padding(8)
        }
    }

    private func triggerSwipeAction(targetOffset: CGFloat, action: @escaping () -> Void) {
        horizontalOffset = targetOffset
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            action()
            horizontalOffset = 0
        }
    }
}

private struct NoteActionIconButton: View {
    let icon: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.caption.weight(.bold))
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(tint.opacity(0.14))
                .clipShape(Capsule())
        }
        .buttonStyle(SpringyButtonStyle())
    }
}

struct NoteDetailView: View {
    @ObservedObject var firestoreManager: FirestoreManager
    let note: Note

    @State private var showEditSheet = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(resolvedNote.title.isEmpty ? "Untitled Note" : resolvedNote.title)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(AppTheme.titleText)

                HStack(spacing: 12) {
                    Label(relativeTimeString(for: resolvedNote.updatedAt), systemImage: "clock")
                        .font(.caption)
                        .foregroundStyle(AppTheme.subtitleText)

                    if resolvedNote.isPinned {
                        Label("Pinned", systemImage: "pin.fill")
                            .font(.caption)
                            .foregroundStyle(AppTheme.accentPrimary)
                    }
                }

                Divider()

                Text(resolvedNote.content.isEmpty ? "No content yet" : resolvedNote.content)
                    .font(.body)
                    .foregroundStyle(AppTheme.subtitleText)
                    .lineSpacing(5)
            }
            .padding(16)
            .glassCard(cornerRadius: 22)
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 20)
        }
        .background(AppTheme.background.ignoresSafeArea())
        .navigationTitle("Note")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarHidden(false)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    HapticFeedback.tap(.light)
                    showEditSheet = true
                } label: {
                    Image(systemName: "square.and.pencil")
                }
            }
        }
        .sheet(isPresented: $showEditSheet) {
            NavigationView {
                EditNoteView(firestoreManager: firestoreManager, note: resolvedNote)
            }
        }
    }

    private var resolvedNote: Note {
        firestoreManager.notes.first(where: { $0.id == note.id }) ?? note
    }

    private func relativeTimeString(for date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - 4. Add Note Screen
struct AddNoteView: View {
    // Allows us to dismiss the screen when done
    @Environment(\.presentationMode) var presentationMode
    
    // Link to our existing ViewModel
    @ObservedObject var firestoreManager: FirestoreManager
    
    @State private var title = ""
    @State private var content = ""
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Note Details")) {
                    TextField("Title", text: $title)
                    
                    TextEditor(text: $content)
                        .frame(height: 200)
                }
            }
            .navigationTitle("New Note")
            .navigationBarItems(
                leading: Button("Cancel") {
                    presentationMode.wrappedValue.dismiss()
                },
                trailing: Button("Save") {
                    // Save note to Firebase
                    firestoreManager.addNote(title: title, content: content)
                    // Close the sheet
                    presentationMode.wrappedValue.dismiss()
                }
                // Grey out the save button if title or content is empty
                .disabled(title.isEmpty || content.isEmpty)
            )
        }
    }
}

// MARK: - 5. Edit Note Screen
struct EditNoteView: View {
    // Allows us to navigate back when done
    @Environment(\.presentationMode) var presentationMode
    
    // Link to our existing ViewModel
    @ObservedObject var firestoreManager: FirestoreManager
    
    // The note we are editing
    let note: Note
    
    // State variables for editing
    @State private var title = ""
    @State private var content = ""
    
    // Initialize state with existing note data when screen appears
    var body: some View {
        Form {
            Section(header: Text("Edit Note")) {
                TextField("Title", text: $title)
                
                TextEditor(text: $content)
                    .frame(height: 200)
            }
        }
        .navigationTitle("Edit Note")
        .navigationBarItems(
            trailing: Button("Update") {
                // Update note in Firebase
                firestoreManager.updateNote(note: note, newTitle: title, newContent: content)
                // Go back to previous screen
                presentationMode.wrappedValue.dismiss()
            }
            // Prevent saving empty edits
            .disabled(title.isEmpty || content.isEmpty)
        )
        // Pre-fill the form with the existing data
        .onAppear {
            title = note.title
            content = note.content
        }
    }
}

struct NotesView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            NotesView()
                .environmentObject(AuthViewModel())
        }
    }
}