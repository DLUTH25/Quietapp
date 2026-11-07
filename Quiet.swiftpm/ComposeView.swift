import AVFoundation
import PhotosUI
import SwiftUI

/// The only screen you use day to day: pick a video, write a caption, post. Nothing else.
@MainActor
struct ComposeView: View {
    @EnvironmentObject private var model: AppModel

    @State private var pickerItem: PhotosPickerItem?
    @State private var video: SelectedVideo?
    @State private var loadingVideo = false

    @State private var caption = ""
    @State private var destination: Destination = .post
    @State private var privacy: String?
    @State private var allowComments = true
    @State private var allowDuet = true
    @State private var allowStitch = true
    @State private var discloseCommercial = false
    @State private var yourBrand = false
    @State private var brandedContent = false

    @State private var phase: Phase = .editing
    @State private var creatorError: String?
    @State private var showSettings = false

    enum Phase: Equatable {
        case editing
        case uploading(Double)
        case processing
        case done(Destination)
        case failed(String)
    }

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .done(let destination):
                    DoneView(destination: destination, reset: reset)
                case .uploading, .processing:
                    SendingView(phase: phase)
                default:
                    form
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Text("Quiet").font(.system(.title2, design: .serif).weight(.light))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("Settings")
                }
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
        }
        .task { await refreshCreator() }
        .onChange(of: pickerItem) { _, item in
            Task { await load(item) }
        }
    }

    // MARK: - Form

    private var form: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                videoTile

                TextField("Caption", text: $caption, axis: .vertical)
                    .lineLimit(3...8)
                    .padding(14)
                    .background(Color.field, in: RoundedRectangle(cornerRadius: 14))
                    .onChange(of: caption) { _, text in
                        if text.count > 2200 { caption = String(text.prefix(2200)) }
                    }

                Picker("Send to", selection: $destination) {
                    ForEach(Destination.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                if destination == .post {
                    postOptions
                } else {
                    Text("The video goes to your TikTok inbox as a draft. Finish it there whenever you want.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if case .failed(let message) = phase {
                    Text(message).font(.footnote).foregroundStyle(.red)
                }
                if let problem = blockingProblem {
                    Text(problem).font(.footnote).foregroundStyle(.secondary)
                }

                Button {
                    Task { await submit() }
                } label: {
                    Text(destination == .post ? "Post" : "Send to drafts")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .tint(.primary)
                .foregroundStyle(Color(uiColor: .systemBackground))
                .disabled(blockingProblem != nil)

                if destination == .post {
                    legalNote
                }
            }
            .padding(20)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private var videoTile: some View {
        PhotosPicker(selection: $pickerItem, matching: .videos, preferredItemEncoding: .current) {
            ZStack {
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color.field)
                if let thumbnail = video?.thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                } else if loadingVideo {
                    ProgressView()
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "plus").font(.title2.weight(.light))
                        Text(video == nil ? "Choose a video" : "Video selected").font(.subheadline)
                    }
                    .foregroundStyle(.secondary)
                }
            }
            .frame(width: 150, height: 266)
            .clipped()
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(video == nil ? "Choose a video" : "Change video")
    }

    @ViewBuilder
    private var postOptions: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Who can see this")
                Spacer()
                Menu {
                    ForEach(model.creator?.privacyLevelOptions ?? [], id: \.self) { option in
                        Button(Privacy.label(option)) { privacy = option }
                            .disabled(brandedContent && option == "SELF_ONLY")
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(privacy.map(Privacy.label) ?? "Choose")
                        Image(systemName: "chevron.up.chevron.down").font(.caption)
                    }
                    .foregroundStyle(privacy == nil ? Color.secondary : Color.primary)
                }
                .disabled(model.creator == nil)
            }
            .padding(.vertical, 12)

            Divider()

            DisclosureGroup("More options") {
                VStack(spacing: 4) {
                    Toggle("Allow comments", isOn: $allowComments)
                        .disabled(model.creator?.commentDisabled ?? false)
                    Toggle("Allow Duet", isOn: $allowDuet)
                        .disabled(model.creator?.duetDisabled ?? false)
                    Toggle("Allow Stitch", isOn: $allowStitch)
                        .disabled(model.creator?.stitchDisabled ?? false)

                    Divider().padding(.vertical, 6)

                    Toggle("Disclose commercial content", isOn: $discloseCommercial)
                    if discloseCommercial {
                        Toggle("Your brand", isOn: $yourBrand)
                        Toggle("Branded content (paid partnership)", isOn: $brandedContent)
                    }
                }
                .padding(.top, 8)
            }
            .padding(.vertical, 12)
            .onChange(of: discloseCommercial) { _, on in
                if !on { yourBrand = false; brandedContent = false }
            }
            .onChange(of: brandedContent) { _, on in
                if on && privacy == "SELF_ONLY" { privacy = nil }
            }

            if let name = model.creator?.creatorNickname ?? model.creator?.creatorUsername {
                Divider()
                Text("Posting as \(name)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.top, 12)
            }
            if let creatorError {
                Text(creatorError).font(.footnote).foregroundStyle(.red).padding(.top, 8)
            }
        }
    }

    private var legalNote: some View {
        let branded = brandedContent ? "[Branded Content Policy](https://www.tiktok.com/legal/page/global/bc-policy/en) and " : ""
        let text = "By posting, you agree to TikTok's \(branded)[Music Usage Confirmation](https://www.tiktok.com/legal/page/global/music-usage-confirmation/en)."
        return Text(LocalizedStringKey(text))
            .font(.caption)
            .foregroundStyle(.secondary)
            .tint(.secondary)
    }

    /// Why the post button is disabled, or nil when it's ready.
    private var blockingProblem: String? {
        guard video != nil else { return loadingVideo ? "Preparing video…" : nil }
        if destination == .drafts { return nil }
        guard let creator = model.creator else { return "Connecting to TikTok…" }
        if privacy == nil { return "Choose who can see this." }
        if discloseCommercial && !yourBrand && !brandedContent {
            return "Pick \"Your brand\" or \"Branded content\", or turn off the disclosure."
        }
        if brandedContent && privacy == "SELF_ONLY" {
            return "Branded content can't be set to \"Only me\"."
        }
        if let max = creator.maxVideoPostDurationSec, let duration = video?.duration, duration > Double(max) {
            return "This video is longer than TikTok allows for this account (\(max / 60) min)."
        }
        return nil
    }

    // MARK: - Actions

    private func refreshCreator() async {
        do {
            try await model.loadCreator()
            creatorError = nil
            // Respect settings the account already has turned off in TikTok.
            if let creator = model.creator {
                if creator.commentDisabled { allowComments = false }
                if creator.duetDisabled { allowDuet = false }
                if creator.stitchDisabled { allowStitch = false }
            }
        } catch {
            creatorError = error.localizedDescription
        }
    }

    private func load(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        loadingVideo = true
        defer { loadingVideo = false }
        do {
            guard let picked = try await item.loadTransferable(type: PickedVideo.self) else { return }
            video = await SelectedVideo(url: picked.url)
            if case .failed = phase { phase = .editing }
        } catch {
            phase = .failed("Couldn't load that video.")
        }
    }

    private func submit() async {
        guard let video else { return }
        phase = .uploading(0)
        do {
            if destination == .post { try await model.loadCreator() }
            let token = try await model.accessToken()
            let plan = ChunkPlan(totalBytes: video.size)

            let publish: PublishInit
            switch destination {
            case .post:
                let options = TikTokAPI.PostOptions(
                    caption: caption,
                    privacyLevel: privacy ?? "SELF_ONLY",
                    disableComment: !allowComments || (model.creator?.commentDisabled ?? false),
                    disableDuet: !allowDuet || (model.creator?.duetDisabled ?? false),
                    disableStitch: !allowStitch || (model.creator?.stitchDisabled ?? false),
                    yourBrand: yourBrand,
                    brandedContent: brandedContent
                )
                publish = try await TikTokAPI.initDirectPost(token: token, options: options, plan: plan)
            case .drafts:
                publish = try await TikTokAPI.initDraftUpload(token: token, plan: plan)
            }

            guard let uploadURL = publish.uploadUrl else {
                throw QuietError.message("TikTok didn't return an upload address.")
            }
            try await TikTokAPI.upload(file: video.url, to: uploadURL, plan: plan, mimeType: video.mimeType) { fraction in
                phase = .uploading(fraction)
            }

            phase = .processing
            try await waitUntilFinished(publishID: publish.publishId)
            phase = .done(destination)
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    private func waitUntilFinished(publishID: String) async throws {
        // TikTok processes the video after upload. Check every few seconds for up to ~10 minutes.
        for _ in 0..<200 {
            let token = try await model.accessToken()
            let status = try await TikTokAPI.status(token: token, publishID: publishID)
            switch status.status {
            case "PUBLISH_COMPLETE", "SEND_TO_USER_INBOX":
                return
            case "FAILED":
                throw QuietError.message("TikTok couldn't publish this video (\(status.failReason ?? "unknown reason")).")
            default:
                try await Task.sleep(for: .seconds(3))
            }
        }
        // Still processing: TikTok will finish on its own, so don't treat it as a failure.
    }

    private func reset() {
        if let url = video?.url { try? FileManager.default.removeItem(at: url) }
        video = nil
        pickerItem = nil
        caption = ""
        privacy = nil
        discloseCommercial = false
        phase = .editing
        Task { await refreshCreator() }
    }
}

// MARK: - Progress and done states

private struct SendingView: View {
    let phase: ComposeView.Phase

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            if case .uploading(let fraction) = phase {
                ProgressView(value: fraction).frame(maxWidth: 220)
                Text("Uploading").foregroundStyle(.secondary)
            } else {
                ProgressView()
                Text("TikTok is processing your video").foregroundStyle(.secondary)
            }
            Spacer()
            Text("You can leave this screen open and look away.")
                .font(.footnote)
                .foregroundStyle(.tertiary)
                .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct DoneView: View {
    let destination: Destination
    let reset: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Spacer()
            Text(destination == .post ? "Posted." : "Sent to drafts.")
                .font(.system(size: 34, weight: .light, design: .serif))
            Text(destination == .post ? "That's it. Back to your day." : "Finish it from your TikTok inbox when you're ready.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
            Button("Post something else", action: reset)
                .padding(.bottom, 32)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Video loading

/// Copies the picked video out of the photo library into a temporary file.
struct PickedVideo: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { video in
            SentTransferredFile(video.url)
        } importing: { received in
            let ext = received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension
            let destination = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(ext)
            try FileManager.default.copyItem(at: received.file, to: destination)
            return PickedVideo(url: destination)
        }
    }
}

struct SelectedVideo {
    let url: URL
    let size: Int
    let duration: Double?
    let thumbnail: UIImage?

    var mimeType: String {
        switch url.pathExtension.lowercased() {
        case "mp4", "m4v": return "video/mp4"
        case "webm": return "video/webm"
        default: return "video/quicktime"
        }
    }

    init(url: URL) async {
        self.url = url
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        size = (attributes?[.size] as? NSNumber)?.intValue ?? 0

        let asset = AVURLAsset(url: url)
        duration = try? await asset.load(.duration).seconds

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 600, height: 600)
        if let frame = try? await generator.image(at: CMTime(seconds: 0.5, preferredTimescale: 600)) {
            thumbnail = UIImage(cgImage: frame.image)
        } else {
            thumbnail = nil
        }
    }
}

extension Color {
    static let field = Color(uiColor: .secondarySystemBackground)
}
