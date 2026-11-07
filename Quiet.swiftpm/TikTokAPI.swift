import Foundation

/// Minimal client for TikTok's Login Kit (OAuth) and Content Posting API.
/// It only calls posting endpoints. It never requests stats, feeds, comments or follower data.
enum TikTokAPI {
    static let scopes = "user.info.basic,video.publish,video.upload"
    private static let apiBase = "https://open.tiktokapis.com"

    // MARK: - OAuth

    static func authorizeURL(config: TikTokConfig, state: String) -> URL {
        var components = URLComponents(string: "https://www.tiktok.com/v2/auth/authorize/")!
        components.queryItems = [
            URLQueryItem(name: "client_key", value: config.clientKey),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: scopes),
            URLQueryItem(name: "redirect_uri", value: config.redirectURI),
            URLQueryItem(name: "state", value: state)
        ]
        return components.url!
    }

    static func exchange(code: String, config: TikTokConfig) async throws -> TikTokTokens {
        try await tokenRequest(config: config, params: [
            "code": code,
            "grant_type": "authorization_code",
            "redirect_uri": config.redirectURI
        ])
    }

    static func refresh(_ tokens: TikTokTokens, config: TikTokConfig) async throws -> TikTokTokens {
        try await tokenRequest(config: config, params: [
            "grant_type": "refresh_token",
            "refresh_token": tokens.refreshToken
        ])
    }

    static func revoke(_ tokens: TikTokTokens, config: TikTokConfig) async {
        var request = URLRequest(url: URL(string: apiBase + "/v2/oauth/revoke/")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formEncode([
            "client_key": config.clientKey,
            "client_secret": config.clientSecret,
            "token": tokens.accessToken
        ])
        _ = try? await URLSession.shared.data(for: request)
    }

    private struct TokenResponse: Decodable {
        let accessToken: String?
        let refreshToken: String?
        let openId: String?
        let scope: String?
        let expiresIn: Int?
        let refreshExpiresIn: Int?
        let error: String?
        let errorDescription: String?
    }

    private static func tokenRequest(config: TikTokConfig, params: [String: String]) async throws -> TikTokTokens {
        var request = URLRequest(url: URL(string: apiBase + "/v2/oauth/token/")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var all = params
        all["client_key"] = config.clientKey
        all["client_secret"] = config.clientSecret
        request.httpBody = formEncode(all)

        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try decoder.decode(TokenResponse.self, from: data)
        guard let access = response.accessToken, let refresh = response.refreshToken else {
            throw QuietError.message(response.errorDescription ?? response.error ?? "TikTok sign-in failed.")
        }
        let now = Date()
        return TikTokTokens(
            accessToken: access,
            refreshToken: refresh,
            openID: response.openId ?? "",
            scope: response.scope ?? "",
            expiresAt: now.addingTimeInterval(TimeInterval(response.expiresIn ?? 86_400)),
            refreshExpiresAt: now.addingTimeInterval(TimeInterval(response.refreshExpiresIn ?? 31_536_000))
        )
    }

    // MARK: - Content Posting

    static func creatorInfo(token: String) async throws -> CreatorInfo {
        try await post("/v2/post/publish/creator_info/query/", token: token, body: [:])
    }

    struct PostOptions {
        var caption: String
        var privacyLevel: String
        var disableComment: Bool
        var disableDuet: Bool
        var disableStitch: Bool
        var yourBrand: Bool
        var brandedContent: Bool
    }

    /// Direct Post: publishes straight to the account, without opening the TikTok app.
    static func initDirectPost(token: String, options: PostOptions, plan: ChunkPlan) async throws -> PublishInit {
        try await post("/v2/post/publish/video/init/", token: token, body: [
            "post_info": [
                "title": options.caption,
                "privacy_level": options.privacyLevel,
                "disable_comment": options.disableComment,
                "disable_duet": options.disableDuet,
                "disable_stitch": options.disableStitch,
                "brand_organic_toggle": options.yourBrand,
                "brand_content_toggle": options.brandedContent
            ],
            "source_info": plan.sourceInfo
        ])
    }

    /// Upload to drafts: the video lands in the TikTok inbox to finish later.
    static func initDraftUpload(token: String, plan: ChunkPlan) async throws -> PublishInit {
        try await post("/v2/post/publish/inbox/video/init/", token: token, body: [
            "source_info": plan.sourceInfo
        ])
    }

    static func status(token: String, publishID: String) async throws -> PublishStatus {
        try await post("/v2/post/publish/status/fetch/", token: token, body: ["publish_id": publishID])
    }

    /// Uploads the file in the chunks TikTok asked for.
    static func upload(
        file: URL,
        to uploadURL: URL,
        plan: ChunkPlan,
        mimeType: String,
        progress: @MainActor (Double) -> Void
    ) async throws {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }

        for index in 0..<plan.chunkCount {
            let range = plan.range(ofChunk: index)
            try handle.seek(toOffset: UInt64(range.lowerBound))
            let chunk = try handle.read(upToCount: range.count) ?? Data()

            var request = URLRequest(url: uploadURL)
            request.httpMethod = "PUT"
            request.timeoutInterval = 300
            request.setValue(mimeType, forHTTPHeaderField: "Content-Type")
            request.setValue("\(chunk.count)", forHTTPHeaderField: "Content-Length")
            request.setValue(
                "bytes \(range.lowerBound)-\(range.upperBound - 1)/\(plan.totalBytes)",
                forHTTPHeaderField: "Content-Range"
            )

            let (_, response) = try await URLSession.shared.upload(for: request, from: chunk)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(code) else {
                throw QuietError.message("Upload failed (HTTP \(code)). Try again.")
            }
            await progress(Double(index + 1) / Double(plan.chunkCount))
        }
    }

    // MARK: - Plumbing

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    private struct ErrorEnvelope: Decodable {
        struct APIError: Decodable {
            let code: String
            let message: String?
        }
        let error: APIError?
    }

    private struct DataEnvelope<T: Decodable>: Decodable {
        let data: T
    }

    private static func post<T: Decodable>(_ path: String, token: String, body: [String: Any]) async throws -> T {
        var request = URLRequest(url: URL(string: apiBase + path)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        if let apiError = (try? decoder.decode(ErrorEnvelope.self, from: data))?.error, apiError.code != "ok" {
            throw QuietError.message(friendly(apiError.code, apiError.message))
        }
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            throw QuietError.message("TikTok returned an error (HTTP \(code)).")
        }
        return try decoder.decode(DataEnvelope<T>.self, from: data).data
    }

    private static func friendly(_ code: String, _ message: String?) -> String {
        switch code {
        case "access_token_invalid", "scope_not_authorized":
            return "TikTok needs you to connect again. Open Settings and reconnect."
        case "spam_risk_too_many_posts":
            return "TikTok's daily posting limit was reached. Try again tomorrow."
        case "spam_risk_user_banned_from_posting":
            return "TikTok isn't allowing this account to post right now."
        case "unaudited_client_can_only_post_to_private_accounts":
            return "Until TikTok approves your developer app, your TikTok account must be set to Private to post directly. Switch it to Private in the TikTok app, or use Drafts."
        case "reached_active_user_cap":
            return "Your TikTok developer app reached its daily user limit."
        default:
            if let message, !message.isEmpty { return message }
            return "TikTok error: \(code)"
        }
    }

    private static func formEncode(_ params: [String: String]) -> Data {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return params
            .map { key, value in
                let v = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
                return "\(key)=\(v)"
            }
            .joined(separator: "&")
            .data(using: .utf8)!
    }
}

/// TikTok's chunking rules: a file of 64 MB or less goes up in one piece; larger files are cut
/// into 10 MB chunks, and the last chunk takes the remainder (it stays under the 128 MB cap).
struct ChunkPlan {
    let totalBytes: Int
    let chunkSize: Int
    let chunkCount: Int

    init(totalBytes: Int) {
        let mb = 1024 * 1024
        self.totalBytes = totalBytes
        if totalBytes <= 64 * mb {
            chunkSize = totalBytes
            chunkCount = 1
        } else {
            chunkSize = 10 * mb
            chunkCount = totalBytes / chunkSize
        }
    }

    func range(ofChunk index: Int) -> Range<Int> {
        let start = index * chunkSize
        let end = index == chunkCount - 1 ? totalBytes : start + chunkSize
        return start..<end
    }

    var sourceInfo: [String: Any] {
        [
            "source": "FILE_UPLOAD",
            "video_size": totalBytes,
            "chunk_size": chunkSize,
            "total_chunk_count": chunkCount
        ]
    }
}
