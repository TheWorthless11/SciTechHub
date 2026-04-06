import SwiftUI

struct ProfileView: View {
    @StateObject private var viewModel = ProfileViewModel()
    @EnvironmentObject var authViewModel: AuthViewModel
    @AppStorage("isDarkMode") private var isDarkMode = false
    
    var body: some View {
        List {
            // Profile Header
            Section {
                HStack {
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "person.circle.fill")
                            .resizable()
                            .frame(width: 80, height: 80)
                            .foregroundColor(.blue)
                        
                        Text(viewModel.userName)
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        Text(viewModel.userEmail)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .padding(.vertical, 10)
            }
            
            // Account Section
            Section(header: Text("Account")) {
                NavigationLink(destination: EditProfileView(viewModel: viewModel)) {
                    Label("Edit Profile", systemImage: "pencil")
                }
                
                NavigationLink(destination: ChangePasswordView()) {
                    Label("Change Password", systemImage: "lock.rotation")
                }
            }
            
            // Preferences Section
            Section(header: Text("Preferences")) {
                Toggle(isOn: $isDarkMode) {
                    Label("Dark Mode", systemImage: isDarkMode ? "moon.fill" : "moon")
                }
            }
            
            // Support Section
            Section(header: Text("Support")) {
                NavigationLink(destination: FAQView()) {
                    Label("FAQ", systemImage: "questionmark.circle")
                }
                
                NavigationLink(destination: ReportIssueView(viewModel: viewModel)) {
                    Label("Report Issue", systemImage: "exclamationmark.bubble")
                }
            }
            
            // Legal Section
            Section(header: Text("Legal")) {
                NavigationLink(destination: Text("Privacy Policy Details...")) {
                    Label("Privacy Policy", systemImage: "hand.raised")
                }
            }
            
            // Logout Section
            Section {
                Button(action: {
                    authViewModel.signOut()
                }) {
                    HStack {
                        Spacer()
                        Text("Logout")
                            .foregroundColor(.red)
                            .fontWeight(.semibold)
                        Spacer()
                    }
                }
            }
        }
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
    }
}
