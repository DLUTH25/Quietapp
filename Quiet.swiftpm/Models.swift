import Foundation

/// Your TikTok developer app's keys. Entered once on the setup screen and kept in the Keychain.
struct TikTokConfig: Codable, Equatable {
    var clientKey: String
    var clientSecret: String
    var redirectURI: String
}

struct TikTokTokens: Codable {
    var accessToken: String
    var refreshToken: String
    var openID: String
    var scope: String
    var expiresAt: Date
    var refreshExpiresAt: Date
}

/// Returned by /v2/post/publish/creator_info/query/.
/// Deliberately the only "profile" data the app ever asks for: no followers, likes or views.
struct CreatorInfo: Decodable {
    let creatorNickname: String?
    let creatorUsername: String?
    let privacyLevelOptions: [String]
    let commentDisabled: Bool
    let duetDisabled: Bool
    let stitchDisabled: Bool
    let maxVideoPostDurationSec: Int?
}

struct PublishInit: Decodable {
    let publishId: String
    let uploadUrl: URL?
}

struct PublishStatus: Decodable {
    let status: String
    let failReason: String?
}

enum Destination: String, CaseIterable, Identifiable {
    case post = "Post"
    case drafts = "Drafts"
    var id: String { rawValue }
}

enum Privacy {
    static func label(_ value: String) -> String {
        switch value {
        case "PUBLIC_TO_EVERYONE": return "Everyone"
        case "MUTUAL_FOLLOW_FRIENDS": return "Friends"
        case "FOLLOWER_OF_CREATOR": return "Followers"
        case "SELF_ONLY": return "Only me"
        default: return value.capitalized
        }
    }
}

enum QuietError: LocalizedError {
    case message(String)
    case notConnected

    var errorDescription: String? {
        switch self {
        case .message(let text): return text
        case .notConnected: return "Your TikTok session ended. Connect again in Settings."
        }
    }
}
