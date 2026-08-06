import Foundation

// Auth. Handoff §8 lists Firebase Auth, Sign in with Apple, and Google Sign-In.
//
// None of those SDKs are declared as dependencies yet — the Firebase project
// does not exist. Everything goes through this protocol so wiring the real
// backend later touches one file and no screens.

protocol AuthService {
    func signUp(name: String, email: String, password: String) async throws -> User
    func logIn(email: String, password: String) async throws -> User
    func sendPasswordReset(to email: String) async throws
    func setNewPassword(_ password: String, token: String) async throws
    func logOut() async throws
    func deleteAccount() async throws
}

enum AuthError: LocalizedError {
    case badCredentials
    case emailInUse
    case weakPassword
    case offline

    // Errors speak in the same voice as everything else.
    var errorDescription: String? {
        switch self {
        case .badCredentials: return "That pair doesn't match anything on record."
        case .emailInUse:     return "There's already a file under that address."
        case .weakPassword:   return "Too short. Eight characters, minimum."
        case .offline:        return "No connection. The record is local until there is one."
        }
    }
}

/// Stand-in until Firebase exists. Accepts anything well-formed and returns a
/// local user, so the whole flow is walkable on a simulator today.
struct LocalAuthService: AuthService {

    func signUp(name: String, email: String, password: String) async throws -> User {
        guard password.count >= 8 else { throw AuthError.weakPassword }
        var user = User()
        user.name = name
        user.email = email
        user.createdAt = Date()
        user.inviteCode = Self.makeInviteCode(from: name)
        return user
    }

    func logIn(email: String, password: String) async throws -> User {
        guard !email.isEmpty, password.count >= 8 else { throw AuthError.badCredentials }
        var user = User()
        user.email = email
        user.inviteCode = Self.makeInviteCode(from: email)
        return user
    }

    func sendPasswordReset(to email: String) async throws {}
    func setNewPassword(_ password: String, token: String) async throws {
        guard password.count >= 8 else { throw AuthError.weakPassword }
    }
    func logOut() async throws {}
    func deleteAccount() async throws {}

    /// "RAMA-4K7"
    static func makeInviteCode(from seed: String) -> String {
        let letters = seed.uppercased().filter { $0.isLetter }.prefix(4)
        let stem = letters.isEmpty ? "USER" : String(letters).padding(toLength: 4, withPad: "X", startingAt: 0)
        let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        let tail = String((0..<3).map { _ in alphabet.randomElement()! })
        return "\(stem)-\(tail)"
    }
}
