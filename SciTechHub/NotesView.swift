import SwiftUI
import FirebaseFirestore

// MARK: - 1. Note Model
struct Note: Identifiable {
    var id: String
    var title: String
    var content: String
}

// MARK: - 2. Firestore Manager (ViewModel)
class FirestoreManager: ObservableObject {
    @Published var notes: [Note] = []
    
    // Reference to our Firestore database
    private var db = Firestore.firestore()
    
    // Fetch notes with a real-time listener
    func fetchNotes() {
        db.collection("notes").addSnapshotListener { (querySnapshot, error) in
            // Basic error handling
            if let error = error {
                print("Error getting notes: \(error.localizedDescription)")
                return
            }
            
            // Safely unwrap documents
            guard let documents = querySnapshot?.documents else { return }
            
            // Map the Firestore documents into our Swift 'Note' array
            self.notes = documents.map { queryDocumentSnapshot -> Note in
                let data = queryDocumentSnapshot.data()
                let title = data["title"] as? String ?? ""
                let content = data["content"] as? String ?? ""
                
                return Note(id: queryDocumentSnapshot.documentID, title: title, content: content)
            }
        }
    }
    
    // Add a new note to Firestore
    func addNote(title: String, content: String) {
        db.collection("notes").addDocument(data: [
            "title": title,
            "content": content
        ])
    }
    
    // Delete a note from Firestore
    func deleteNote(note: Note) {
        db.collection("notes").document(note.id).delete()
    }
    
    // Update an existing note in Firestore
    func updateNote(note: Note, newTitle: String, newContent: String) {
        db.collection("notes").document(note.id).updateData([
            "title": newTitle,
            "content": newContent
        ])
    }
}

// MARK: - 3. Target Notes View
struct NotesView: View {
    @StateObject private var firestoreManager = FirestoreManager()
    @State private var showAddNote = false
    
    var body: some View {
        List {
            ForEach(firestoreManager.notes) { note in
                VStack(alignment: .leading, spacing: 8) {
                    Text(note.title)
                        .font(.headline)
                    Text(note.content)
                        .font(.subheadline)
                        .foregroundColor(.gray)
                        .lineLimit(2)
                    
                    HStack(spacing: 20) {
                        // Edit Button (Navigates to Edit Screen)
                        NavigationLink(destination: EditNoteView(firestoreManager: firestoreManager, note: note)) {
                            Text("Edit")
                                .font(.callout)
                                .foregroundColor(.blue)
                        }
                        .buttonStyle(BorderlessButtonStyle())
                        
                        // Delete Button
                        Button(action: {
                            firestoreManager.deleteNote(note: note)
                        }) {
                            Text("Delete")
                                .font(.callout)
                                .foregroundColor(.red)
                        }
                        .buttonStyle(BorderlessButtonStyle())
                    }
                    .padding(.top, 4)
                }
                .padding(.vertical, 4)
            }
        }
        .navigationTitle("My Notes")
        .navigationBarItems(trailing: Button(action: {
            showAddNote = true // Opens the add screen
        }) {
            Image(systemName: "plus")
        })
        .sheet(isPresented: $showAddNote) {
            AddNoteView(firestoreManager: firestoreManager)
        }
        // Fetch our notes as soon as the screen opens
        .onAppear {
            firestoreManager.fetchNotes()
        }
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
        }
    }
}