import Foundation
import FirebaseAuth
import FirebaseFirestore
import Combine

class AuthViewModel: ObservableObject {
    @Published var user: FirebaseAuth.User?
    @Published var username = ""
    @Published var email = ""
    @Published var password = ""
    @Published var errorMessage: String?

    private var handle: AuthStateDidChangeListenerHandle?

    init() {
        handle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            DispatchQueue.main.async {
                self?.user = user
            }
        }
    }

    deinit {
        if let handle = handle {
            Auth.auth().removeStateDidChangeListener(handle)
        }
    }

    func signIn() {
        let name = username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let db = Firestore.firestore()
        db.collection("usernames").document(name).getDocument { [weak self] snapshot, error in
            DispatchQueue.main.async {
                if let e = error {
                    self?.errorMessage = e.localizedDescription
                } else if let data = snapshot?.data(), let mappedEmail = data["email"] as? String {
                    self?.authSignIn(withEmail: mappedEmail, password: self?.password ?? "")
                } else {
                    self?.errorMessage = "Username not found"
                }
            }
        }
    }

    func signUp() {
        let name = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            self.errorMessage = "Username required"
            return
        }
        Auth.auth().createUser(withEmail: email, password: password) { [weak self] result, error in
            guard let self = self else { return }
            DispatchQueue.main.async {
                if let e = error {
                    self.errorMessage = e.localizedDescription
                } else if let user = result?.user {
                    self.errorMessage = nil
                    // set displayName
                    let change = user.createProfileChangeRequest()
                    change.displayName = name
                    change.commitChanges { profErr in
                        // ignore profile errors
                    }
                    // store username->email mapping
                    let db = Firestore.firestore()
                    db.collection("usernames").document(name.lowercased())
                      .setData(["email": self.email.lowercased()])
                }
            }
        }
    }

    private func authSignIn(withEmail email: String, password: String) {
        Auth.auth().signIn(withEmail: email, password: password) { [weak self] _, error in
            DispatchQueue.main.async {
                if let e = error {
                    self?.errorMessage = e.localizedDescription
                } else {
                    self?.errorMessage = nil
                }
            }
        }
    }

    func signOut() {
        do {
            try Auth.auth().signOut()
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }
}
