import SwiftUI
import CapeKit

/// The cursor themes on pling.com (gnome-look.org) as a grid with search and order. A
/// double-click installs a theme; its details show all files, the licence and a link to
/// its page.
struct GalleryView: View {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow
    @State private var detailTheme: PlingTheme?
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
            ToolbarItem {
                Picker("Order", selection: $gallery.sort) {
                    ForEach(PlingCatalog.Sort.allCases) { Text($0.title).tag($0) }
                }
                .help("Order of the themes")
            }
        }
        .onChange(of: gallery.sort) { gallery.reload() }
        .task {
            if gallery.themes.isEmpty { gallery.reload() }
        }
        .sheet(item: $detailTheme) { theme in
            ThemeDetailView(theme: theme, gallery: gallery) { file in install(file, of: theme) }
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
                ContentUnavailableView.search(text: gallery.search)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 210, maximum: 280), spacing: 16)], spacing: 16) {
                    ForEach(gallery.themes) { theme in
                        ThemeCard(theme: theme, isDownloading: gallery.downloading.contains(theme.id))
                            .onTapGesture(count: 2) { installFirstFile(of: theme) }
                            .onTapGesture { detailTheme = theme }
                            .onAppear {
                                if theme.id == gallery.themes.last?.id { gallery.loadMore() }
                            }
                            .contextMenu {
                                Button("Install") { installFirstFile(of: theme) }
                                    .disabled(CursorGallery.installableFiles(of: theme).isEmpty)
                                Button("Details…") { detailTheme = theme }
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

    /// Installs, then brings the library forward: it shows the new cape, or asks whether to
    /// replace one with the same identifier.
    private func install(_ file: PlingTheme.File, of theme: PlingTheme) {
        Task {
            await model.install(file, of: theme)
            openWindow(id: "library")
        }
    }
}

/// One theme in the grid: preview, name, author, downloads and licence.
private struct ThemeCard: View {
    let theme: PlingTheme
    let isDownloading: Bool

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
        .help("Double-click to install; click for details")
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
                        Button("Install") {
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
