import AppKit
import SwiftUI

struct ExtensionRow: View {
    enum Style {
        case form
        case compact
    }

    enum Subject {
        case entry(ExtensionIndex.Entry, state: ExtensionState)
        case orphan(InstalledExtension)

        var id: String {
            switch self {
            case .entry(let entry, _): return entry.id
            case .orphan(let installed): return installed.id
            }
        }

        var title: String {
            switch self {
            case .entry(let entry, _): return entry.card?.title ?? entry.name
            case .orphan(let installed): return installed.name
            }
        }

        var author: String {
            switch self {
            case .entry(let entry, _): return entry.card?.author.name ?? entry.publisher
            case .orphan(let installed): return installed.publisher.isEmpty ? installed.id : installed.publisher
            }
        }

        var versionText: String {
            switch self {
            case .entry(let entry, let state): return ExtensionRow.versionText(entry, state: state)
            case .orphan(let installed): return installed.version
            }
        }

        /// The version the reader has, when it is not the version on offer.
        /// Nil on every row that is not waiting for an update, which is what
        /// keeps such a row looking exactly as it did.
        var installedVersion: String? {
            guard case .entry(_, .updateAvailable(let installed, _)) = self else { return nil }
            return installed
        }

        var offeredVersion: String {
            switch self {
            case .entry(let entry, let state):
                if case .updateAvailable(_, let available) = state { return available }
                return entry.version
            case .orphan(let installed): return installed.version
            }
        }

        var state: ExtensionState {
            switch self {
            case .entry(_, let state): return state
            case .orphan(let installed): return .installed(version: installed.version)
            }
        }
    }

    let subject: Subject
    let style: Style
    let icon: ExtensionIconSource?
    let activity: ExtensionActivity?
    let error: String?
    var isSelected = false
    let onOpen: () -> Void
    let onInstall: () -> Void
    let onRemove: () -> Void

    @ObservedObject private var palette: ThemePalette = .shared
    @ObservedObject private var store: ExtensionStore = .shared
    @State private var isHovered = false

    var body: some View {
        switch style {
        case .form:
            formBody
        case .compact:
            compactBody
        }
    }

    /// `signature`, an SF Symbol since macOS 10.15 — three releases before
    /// this app's deployment target, and old enough that no build it ships
    /// to can fail to resolve it. A name that does not resolve makes SwiftUI
    /// drop the whole row silently, so the age matters more than the shape.
    static let authorSymbol = "signature"

    static func versionText(_ entry: ExtensionIndex.Entry, state: ExtensionState) -> String {
        if case .updateAvailable(let installed, let available) = state {
            return "\(installed) \u{2192} \(available)"
        }
        return entry.version
    }

    // MARK: Form

    private var formBody: some View {
        LabeledContent {
            VStack(alignment: .trailing, spacing: 4) {
                trailing(controlSize: .regular)
                versionTag
            }
        } label: {
            HStack(alignment: .center, spacing: 10) {
                ExtensionIconView(source: icon, size: 28)
                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: subject.title)
                        .lineLimit(1)
                    byline(font: .caption)
                    if let error {
                        Text(verbatim: error)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .help(subject.id)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
    }

    // MARK: Compact

    private var compactBody: some View {
        HStack(spacing: 12) {
            ExtensionIconView(source: icon, size: 40)
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: subject.title)
                    .font(palette.font(size: 13, weight: .semibold))
                    .lineLimit(1)
                byline(font: palette.font(size: 11))
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 4) {
                trailing(controlSize: .regular)
                versionTag
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(compactBackground)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
        .onHover { isHovered = $0 }
        .help(error ?? subject.id)
    }

    private var compactBackground: Color {
        if isSelected { return (palette.accent ?? .accentColor).opacity(0.18) }
        return isHovered ? Color.primary.opacity(0.06) : .clear
    }

    // MARK: Shared

    /// Who published the extension.
    ///
    /// The mark is a signature rather than a person: the line names the
    /// author of a published thing, not the holder of an account, and the
    /// generic person placeholder reads as the second one.
    private func byline(font: Font) -> some View {
        HStack(spacing: 3) {
            Image(systemName: Self.authorSymbol)
            Text(verbatim: subject.author)
                .lineLimit(1)
        }
        .font(font)
        .foregroundStyle(.secondary)
    }

    private var versionTag: some View {
        ExtensionVersionTagView(installed: subject.installedVersion, offered: subject.offeredVersion)
    }

    @ViewBuilder
    private func trailing(controlSize: ControlSize) -> some View {
        if let activity {
            ExtensionActivityView(activity: activity, compact: controlSize == .small)
        } else {
            HStack(spacing: 6) {
                if error != nil, controlSize == .small {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.red)
                }
                requirementsBadge
                ExtensionActionButton(
                    state: subject.state,
                    style: .labelled,
                    onInstall: onInstall,
                    onRemove: onRemove)
                    .controlSize(controlSize)
            }
        }
    }

    @ViewBuilder
    private var requirementsBadge: some View {
        if let missing = store.pendingRequirements[subject.id],
           let text = ExtensionStore.requirementsBadge(missing) {
            Text(verbatim: text)
                .font(.caption)
                .foregroundStyle(.orange)
                .lineLimit(1)
                .help(missing.map(\.program).joined(separator: ", "))
        }
    }
}

struct ExtensionActionButton: View {
    enum Style {
        case bare
        case labelled
    }

    enum Action: String, CaseIterable, Equatable {
        case install
        case update
        case uninstall

        init(state: ExtensionState) {
            switch state {
            case .notInstalled: self = .install
            case .installed: self = .uninstall
            case .updateAvailable: self = .update
            }
        }

        var title: String {
            switch self {
            case .install: return "Install"
            case .update: return "Update"
            case .uninstall: return "Uninstall"
            }
        }

        var systemImage: String {
            switch self {
            case .install: return "arrow.down.circle"
            case .update: return "arrow.triangle.2.circlepath"
            case .uninstall: return "trash"
            }
        }

        var isDestructive: Bool { self == .uninstall }
    }

    let state: ExtensionState
    var style: Style = .bare
    let onInstall: () -> Void
    let onRemove: () -> Void

    @ObservedObject private var palette: ThemePalette = .shared
    @State private var isHovered = false

    private var action: Action { Action(state: state) }

    private var tint: Color {
        guard isHovered else { return .primary }
        if action.isDestructive { return palette.danger ?? .red }
        return palette.accent ?? .accentColor
    }

    var body: some View {
        switch style {
        case .bare:
            Button(action.title, action: run)
        case .labelled:
            Button(action: run) {
                Label(action.title, systemImage: action.systemImage)
                    .foregroundStyle(tint)
            }
            .onHover { isHovered = $0 }
            .animation(.easeOut(duration: 0.12), value: isHovered)
        }
    }

    private func run() {
        if action.isDestructive {
            onRemove()
        } else {
            onInstall()
        }
    }
}

struct ExtensionStateBadge: View {
    let state: ExtensionState

    var body: some View {
        switch state {
        case .notInstalled:
            EmptyView()
        case .installed:
            badge("Installed", color: .green)
        case .updateAvailable:
            badge("Update available", color: .orange)
        }
    }

    private func badge(_ title: LocalizedStringKey, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

struct ExtensionActivityView: View {
    let activity: ExtensionActivity
    var compact = false

    var body: some View {
        HStack(spacing: compact ? 5 : 8) {
            if case .downloading(let fraction?) = activity, !compact {
                ProgressView(value: fraction)
                    .progressViewStyle(.linear)
                    .frame(width: 100)
            } else {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(compact ? 0.6 : 1)
                    .frame(width: compact ? 12 : nil, height: compact ? 12 : nil)
            }
            if !compact {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .help(label)
    }

    private var label: LocalizedStringKey {
        switch activity {
        case .downloading: return "Downloading…"
        case .verifying: return "Verifying…"
        case .installing: return "Installing…"
        case .removing: return "Removing…"
        }
    }
}

struct ExtensionTagView: View {
    let text: String

    var body: some View {
        Text(verbatim: text)
            .foregroundStyle(.secondary)
            .modifier(ExtensionChipChrome())
    }
}

/// The capsule every chip in the store is drawn in, so the version tag and
/// the plain tag cannot drift apart in size, weight or radius.
struct ExtensionChipChrome: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.caption2.weight(.semibold).monospacedDigit())
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(
                Capsule().fill(Color.secondary.opacity(0.15))
            )
            .lineLimit(1)
    }
}

/// The version chip that sits under a row's button.
///
/// With nothing to update to it is one plain version, drawn exactly as any
/// other tag. With an update waiting it reads `installed -> offered`, and
/// the two halves take the theme's own colours: the version on this machine
/// in the theme's yellow, the one it could become in the theme's green.
/// Both come from the palette rather than from `Color.orange` and
/// `Color.green`, so a light theme colours them the way it colours
/// everything else, and both fall back to the system colour when no theme
/// is loaded.
struct ExtensionVersionTagView: View {
    let installed: String?
    let offered: String

    @ObservedObject private var palette: ThemePalette = .shared

    var body: some View {
        if let installed {
            HStack(spacing: 3) {
                Text(verbatim: installed)
                    .foregroundStyle(palette.yellow ?? .orange)
                Text(verbatim: "\u{2192}")
                    .foregroundStyle(.secondary)
                Text(verbatim: offered)
                    .foregroundStyle(palette.success ?? .green)
            }
            .modifier(ExtensionChipChrome())
            .help(Text(verbatim: "Installed \(installed), \(offered) available"))
        } else {
            ExtensionTagView(text: offered)
        }
    }
}

struct ExtensionIconView: View {
    let source: ExtensionIconSource?
    var size: CGFloat = 28

    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            } else {
                RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                    .fill(Color.secondary.opacity(0.12))
                    .overlay(
                        Image(systemName: ExtensionDocument.symbol)
                            .font(.system(size: size * 0.45, weight: .semibold))
                            .foregroundStyle(.secondary)
                    )
            }
        }
        .frame(width: size, height: size)
        .task(id: source?.key) {
            image = await Self.resolve(source)
        }
    }

    @MainActor
    static func resolve(_ source: ExtensionIconSource?) async -> NSImage? {
        guard let source else { return nil }
        let key = source.key
        let cache = ExtensionIconCache.shared
        if cache.knows(key) { return cache.image(forKey: key) }
        let image = Self.image(from: await bytes(of: source))
        cache.remember(image, forKey: key)
        return image
    }

    static func bytes(of source: ExtensionIconSource) async -> Data? {
        switch source {
        case .inline(_, let data):
            return data
        case .file(let url):
            return await Task.detached(priority: .utility) { () -> Data? in
                guard let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize,
                      size <= ExtensionMediaGate.maxImageBytes
                else { return nil }
                return try? Data(contentsOf: url)
            }.value
        }
    }

    static func image(from data: Data?) -> NSImage? {
        guard let data, let image = NSImage(data: data), image.size.width > 0, image.size.height > 0 else {
            return nil
        }
        return image
    }
}

struct ExtensionContributionChips: View {
    let entry: ExtensionIndex.Entry

    var body: some View {
        HStack(spacing: 4) {
            ForEach(entry.contributes, id: \.self) { kind in
                ExtensionChipView(chip: ExtensionContributionChip.of(kind))
                    .help(kind == "languages" && !entry.languages.isEmpty
                        ? entry.languages.joined(separator: ", ")
                        : ExtensionContributionChip.of(kind).title)
            }
        }
    }
}

struct ExtensionChipView: View {
    let chip: ExtensionContributionChip

    var body: some View {
        Label(chip.title, systemImage: chip.systemImage)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(
                Capsule().fill(Color.secondary.opacity(0.15))
            )
            .foregroundStyle(.secondary)
    }
}

/// The label and mark for one entry of an extension's `contributes`.
///
/// A case for every kind `LanguageManifest` reads, and the fallthrough is
/// there for a kind a later schema adds rather than for one this build knows
/// about: a known kind reaching `default` shows its manifest spelling —
/// `iconThemes`, `grammars` — beside a puzzle piece, which names nothing and
/// tells the reader the app did not recognise its own extension.
struct ExtensionContributionChip: Equatable {
    let title: String
    let systemImage: String

    static func of(_ kind: String) -> ExtensionContributionChip {
        switch kind {
        case "languages":
            return ExtensionContributionChip(
                title: "Languages", systemImage: "chevron.left.forwardslash.chevron.right")
        case "servers":
            return ExtensionContributionChip(title: "Servers", systemImage: "server.rack")
        case "formatters":
            return ExtensionContributionChip(title: "Formatters", systemImage: "text.alignleft")
        case "themes":
            return ExtensionContributionChip(title: "Themes", systemImage: "paintpalette")
        case "iconThemes":
            return ExtensionContributionChip(title: "Icon Themes", systemImage: "photo.on.rectangle")
        case "grammars":
            return ExtensionContributionChip(title: "Grammars", systemImage: "textformat.abc")
        case "agents":
            return ExtensionContributionChip(title: "Agents", systemImage: "sparkles")
        default:
            return ExtensionContributionChip(title: kind, systemImage: "puzzlepiece")
        }
    }
}
