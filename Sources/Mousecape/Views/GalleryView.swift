import SwiftUI
import CapeKit

/// The cursor themes on pling.com (gnome-look.org) as a grid with search and order. A
/// double-click installs a theme; its details show all files, the licence and a link to
/// its page.
struct GalleryView: View {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow
    @State private var detailTheme: PlingTheme?
    @State private var updateRequest: UpdateRequest?
    @FocusState private var isSearchFocused: Bool

    private var gallery: CursorGallery { model.gallery }

    var body: some View {
        @Bindable var gallery = gallery
        VStack(spacing: 0) {
            content
            Divider()
            footer
        }
        .frame(minWidth: 720, minHeight: 480)
        .searchable(text: $gallery.search, placement: .toolbar, prompt: "Search cursor themes")
        .modifier(SearchFocus(isFocused: $isSearchFocused))
        .focusedSceneValue(\.focusSearch, Self.canFocusSearch ? { isSearchFocused = true } : nil)
        .onSubmit(of: .search) { gallery.reload() }
        .onChange(of: gallery.search) { _, new in
            if new.isEmpty { gallery.reload() }     // the field's clear button
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Picker("Show", selection: $gallery.scope) {
                    Text("All Themes").tag(CursorGallery.Scope.all)
                    Text("Installed").tag(CursorGallery.Scope.installed)
                }
                .pickerStyle(.segmented)
                .help("All themes on pling.com, or those installed from here, to look for updates")
            }
            ToolbarItem {
                Picker("Order", selection: $gallery.sort) {
                    ForEach(PlingCatalog.Sort.allCases) { Text($0.title).tag($0) }
                }
                .help("Order of the themes")
            }
        }
        .onChange(of: gallery.sort) { gallery.reload() }
        .onChange(of: gallery.scope) { gallery.reload() }
        .task {
            if gallery.themes.isEmpty { gallery.reload() }
        }
        .sheet(item: $detailTheme) { theme in
            ThemeDetailView(theme: theme, gallery: gallery,
                            installedCape: model.library.cape(installedFromGalleryTheme: theme.id),
                            update: model.update(for: theme),
                            onShowInLibrary: { show($0) },
                            onShowUpdate: { updateRequest = UpdateRequest(theme: theme, file: $0) }) { file in
                install(file, of: theme)
            }
        }
        .sheet(item: $updateRequest) { request in
            UpdateView(model: model, request: request) { cape in show(cape) }
        }
    }

    @ViewBuilder
    private var content: some View {
        if gallery.themes.isEmpty && !gallery.isLoading {
            if let message = gallery.errorMessage {
                ContentUnavailableView {
                    Label("pling.com can't be reached", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(message)
                } actions: {
                    Button("Try Again") { gallery.reload() }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Group {
                    if gallery.scope == .installed && gallery.search.isEmpty {
                        ContentUnavailableView("Nothing Installed from Here", systemImage: "globe",
                                               description: Text("Themes you install from the gallery show here, with their updates."))
                    } else {
                        ContentUnavailableView.search(text: gallery.search)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 210, maximum: 280), spacing: 16)], spacing: 16) {
                    ForEach(gallery.themes) { theme in
                        let update = model.update(for: theme)
                        ThemeCard(theme: theme, isDownloading: gallery.downloading.contains(theme.id),
                                  installedCape: model.library.cape(installedFromGalleryTheme: theme.id),
                                  hasUpdate: update != nil)
                            .onTapGesture(count: 2) {
                                if let update {
                                    updateRequest = UpdateRequest(theme: theme, file: update)
                                } else {
                                    installFirstFile(of: theme)
                                }
                            }
                            .onTapGesture { detailTheme = theme }
                            .onAppear {
                                if theme.id == gallery.themes.last?.id { gallery.loadMore() }
                            }
                            .contextMenu {
                                Button("Install") { installFirstFile(of: theme) }
                                    .disabled(CursorGallery.installableFiles(of: theme).isEmpty)
                                if let update {
                                    Button("Show Update…") { updateRequest = UpdateRequest(theme: theme, file: update) }
                                }
                                Button("Details…") { detailTheme = theme }
                                if let cape = model.library.cape(installedFromGalleryTheme: theme.id) {
                                    Button("Show in Library") { show(cape) }
                                }
                                if let page = theme.detailPage {
                                    Link("Open on pling.com", destination: page)
                                }
                            }
                    }
                }
                .padding(16)
                if gallery.isLoading {
                    ProgressView()
                        .padding()
                } else if let message = gallery.errorMessage {
                    VStack {
                        Text(message).foregroundStyle(.secondary)
                        Button("Try Again") { gallery.loadMore() }
                    }
                    .padding()
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Text("Themes from pling.com, also known as gnome-look.org. They are made by others: check each theme's licence before you share or change it.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer()
            if gallery.totalCount > 0 {
                Text("\(gallery.totalCount) themes")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    /// Edit → Find (⌘F) puts the focus in the search field. SwiftUI can do that only from
    /// macOS 15 on (`searchFocused`); on macOS 14 the menu item stays disabled.
    private static var canFocusSearch: Bool {
        if #available(macOS 15, *) { true } else { false }
    }

    private func installFirstFile(of theme: PlingTheme) {
        guard let file = CursorGallery.installableFiles(of: theme).first else {
            detailTheme = theme     // nothing Mousecape can import: the details say why
            return
        }
        install(file, of: theme)
    }

    /// Selects a cape in the library and brings the library forward.
    private func show(_ cape: Cape) {
        model.selection = cape.id
        openWindow(id: "library")
    }

    /// Installs, then brings the library forward: it shows the new cape, or asks whether to
    /// replace one with the same identifier.
    private func install(_ file: PlingTheme.File, of theme: PlingTheme) {
        Task {
            await model.install(file, of: theme)
            openWindow(id: "library")
        }
    }
}

/// One theme in the grid: preview, name, author, downloads and licence, and a mark when
/// it is already in the library.
private struct ThemeCard: View {
    let theme: PlingTheme
    let isDownloading: Bool
    let installedCape: Cape?
    let hasUpdate: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ThemePreview(url: theme.thumbnail)
                .aspectRatio(280 / 171, contentMode: .fit)
                .overlay {
                    if isDownloading {
                        ProgressView()
                            .padding(10)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if let installedCape {
                        InstalledBadge(hasUpdate: hasUpdate)
                            .padding(6)
                            .help(hasUpdate ? "A newer version is on pling.com; double-click to see what it changes"
                                            : "In your library as “\(installedCape.name)”")
                    }
                }
            Text(theme.name)
                .font(.headline)
                .lineLimit(1)
            HStack(spacing: 6) {
                Text(theme.author)
                    .lineLimit(1)
                Spacer()
                Label("\(theme.downloads.formatted(.number.notation(.compactName)))", systemImage: "arrow.down.circle")
                    .labelStyle(.titleAndIcon)
                    .help("Downloads")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            LicenceBadge(licence: theme.licence)
        }
        .padding(8)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .help(hasUpdate ? "Double-click to see what the update changes; click for details"
                        : "Double-click to install; click for details")
    }
}

/// Marks a theme that is already in the library, and whether pling.com has a newer
/// version of it.
private struct InstalledBadge: View {
    var hasUpdate = false

    var body: some View {
        Group {
            if hasUpdate {
                Label("Update Available", systemImage: "arrow.down.circle.fill")
            } else {
                Label("Installed", systemImage: "checkmark.circle.fill")
            }
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .foregroundStyle(.white)
        .background(hasUpdate ? Color.blue : Color.green, in: Capsule())
        .shadow(radius: 2)
    }
}

private struct LicenceBadge: View {
    let licence: String?

    var body: some View {
        Text(licence ?? String(localized: "No licence named"))
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background((licence == nil ? Color.orange : Color.secondary).opacity(0.15), in: Capsule())
            .foregroundStyle(licence == nil ? .orange : .secondary)
    }
}

/// A preview image from pling.com, with a placeholder while it loads or when it fails.
private struct ThemePreview: View {
    let url: URL?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6).fill(.quaternary)
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFit()
                case .failure:
                    Image(systemName: "photo").foregroundStyle(.tertiary)
                default:
                    ProgressView().controlSize(.small)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

/// A theme's previews, details, description and files.
private struct ThemeDetailView: View {
    let theme: PlingTheme
    let gallery: CursorGallery
    /// The cape this theme was installed as, if it is in the library.
    let installedCape: Cape?
    /// The newer file, when pling.com has one.
    let update: PlingTheme.File?
    let onShowInLibrary: (Cape) -> Void
    let onShowUpdate: (PlingTheme.File) -> Void
    let onInstall: (PlingTheme.File) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    previews
                    header
                    files
                    if !theme.description.isEmpty {
                        Text(theme.description)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(20)
            }
            Divider()
            HStack {
                if let page = theme.detailPage {
                    Link("Open on pling.com", destination: page)
                }
                Spacer()
                Button("Close") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(12)
        }
        .frame(minWidth: 620, idealWidth: 680, minHeight: 520, idealHeight: 640)
    }

    private var previews: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 10) {
                ForEach(theme.previews, id: \.self) { url in
                    ThemePreview(url: url)
                        .frame(width: 440, height: 308)
                }
            }
        }
        .frame(height: theme.previews.isEmpty ? 0 : 316)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(theme.name)
                .font(.title2.weight(.semibold))
            HStack(spacing: 12) {
                Text("by \(theme.author)")
                Text("\(theme.downloads.formatted()) downloads")
                if let changed = theme.changed {
                    Text("updated \(changed.formatted(date: .abbreviated, time: .omitted))")
                }
                LicenceBadge(licence: theme.licence)
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            if let installedCape {
                HStack {
                    InstalledBadge(hasUpdate: update != nil)
                    Text("In your library as “\(installedCape.name)”.")
                        .foregroundStyle(.secondary)
                    Button("Show in Library") {
                        onShowInLibrary(installedCape)
                        dismiss()
                    }
                    .buttonStyle(.link)
                    if let update {
                        Button("Show Changes…") {
                            dismiss()
                            onShowUpdate(update)
                        }
                    }
                }
                .padding(.top, 4)
            }
        }
    }

    private var files: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Files").font(.headline)
            if theme.files.isEmpty {
                Text("This theme has no files to download here; its page may say where to get it.")
                    .foregroundStyle(.secondary)
            }
            ForEach(theme.files) { file in
                let installable = CursorGallery.isInstallable(file.name)
                HStack {
                    Image(systemName: installable ? "doc.zipper" : "doc")
                        .foregroundStyle(.secondary)
                    Text(file.name)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let size = file.size {
                        Text(Int64(size).formatted(.byteCount(style: .file)))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Spacer()
                    if installable {
                        Button(installedCape == nil ? "Install" : "Install Again") {
                            onInstall(file)
                            dismiss()
                        }
                        .disabled(gallery.downloading.contains(theme.id))
                    } else {
                        Text("Can't be imported")
                            .foregroundStyle(.secondary)
                            .help("Mousecape imports archives of Windows or Linux cursor themes, capes and MaCursor themes")
                    }
                }
            }
        }
    }
}

/// `searchFocused` where the system has it (macOS 15 and later).
private struct SearchFocus: ViewModifier {
    let isFocused: FocusState<Bool>.Binding

    func body(content: Content) -> some View {
        if #available(macOS 15, *) {
            content.searchFocused(isFocused)
        } else {
            content
        }
    }
}

/// An installed theme and its newer file, for `UpdateView`.
struct UpdateRequest: Identifiable {
    let theme: PlingTheme
    let file: PlingTheme.File
    var id: Int { theme.id }
}

/// What an update from pling.com changes in the installed cape, before anything is saved:
/// it downloads and converts the newer file, then shows the differences, each cursor old
/// and new side by side.
private struct UpdateView: View {
    let model: AppModel
    let request: UpdateRequest
    let onShowInLibrary: (Cape) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var prepared: PreparedUpdate?
    @State private var diff: CapeDiff?
    @State private var failure: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Update “\(request.theme.name)”")
                    .font(.title2.weight(.semibold))
                Text("The new file on pling.com is \(request.file.name). Updating replaces the cursors of “\(prepared?.installed.name ?? request.theme.name)”, your own changes to them too. The current state stays in the cape's history, so History → Restore takes the update back.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Group {
                if let failure {
                    ContentUnavailableView("The update can't be shown", systemImage: "exclamationmark.triangle",
                                           description: Text(failure))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let diff, diff.isEmpty {
                    ContentUnavailableView("Nothing Changes", systemImage: "checkmark.circle",
                                           description: Text("The new file makes the same cape. It may change only what Mousecape doesn't use, such as cursors macOS has no place for."))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let diff {
                    DiffList(diff: diff)
                } else {
                    VStack(spacing: 8) {
                        ProgressView()
                        Text("Downloading and converting…")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            HStack {
                if let prepared, !prepared.skipped.isEmpty {
                    Text("Left out, as macOS has no matching cursor: \(prepared.skipped.joined(separator: ", "))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                if let prepared, let diff {
                    if diff.isEmpty {
                        Button("Mark as Up to Date") {
                            model.markUpToDate(prepared)
                            dismiss()
                        }
                        .keyboardShortcut(.defaultAction)
                    } else {
                        Button("Update") {
                            model.applyUpdate(prepared)
                            dismiss()
                            if let cape = model.library.cape(installedFromGalleryTheme: prepared.themeID) {
                                onShowInLibrary(cape)
                            }
                        }
                        .keyboardShortcut(.defaultAction)
                    }
                }
            }
        }
        .padding(20)
        .frame(minWidth: 640, idealWidth: 720, minHeight: 440, idealHeight: 540)
        .task {
            do {
                let update = try await model.prepareUpdate(request.file, of: request.theme)
                // The diff compares every image; not on the main thread.
                diff = await Task.detached { update.diff }.value
                prepared = update
            } catch {
                failure = error.localizedDescription
            }
        }
    }
}
