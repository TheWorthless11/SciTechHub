import SwiftUI

struct EditProfileView: View {
    @ObservedObject var viewModel: ProfileViewModel
    @State private var name: String = ""
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        Form {
            Section(header: Text("Personal Info")) {
                TextField("Name", text: $name)
            }
            
            if let error = viewModel.errorMessage {
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
            }
            
            if let success = viewModel.successMessage {
                Text(success)
                    .foregroundColor(.green)
                    .font(.caption)
            }
            
            Button(action: {
                viewModel.updateProfile(name: name)
            }) {
                HStack {
                    Spacer()
                    if viewModel.isLoading {
                        ProgressView()
                    } else {
                        Text("Save Changes")
                            .fontWeight(.semibold)
                    }
                    Spacer()
                }
            }
            .disabled(name.isEmpty || viewModel.isLoading)
        }
        .navigationTitle("Edit Profile")
        .onAppear {
            viewModel.clearMessages()
            self.name = viewModel.userName
        }
    }
}
