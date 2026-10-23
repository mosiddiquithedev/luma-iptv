import SwiftUI
import LumaCore

struct DiscoverSettingsView: View {
    @EnvironmentObject var store: AppStore
    @State private var deleting: DiscoverShelf?
    var selected: DiscoverShelf? { store.editingDiscoverShelfID.flatMap(store.shelf) }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Make Discover yours").font(.system(size: 24, weight: .semibold))
                    Text("Your sections, your categories. Changes save automatically for this provider.").font(.system(size: 11)).foregroundStyle(Theme.muted)
                }
                Spacer()
                Menu {
                    Button("Custom section") { store.addDiscoverShelf() }
                    Button("Favorite TV channels") { store.addDiscoverShelf(title: "Favorite TV Channels", favoritesOnly: true, kinds: [.live]) }
                    Button("Favorite movies") { store.addDiscoverShelf(title: "Favorite Movies", favoritesOnly: true, kinds: [.movie]) }
                    Button("Favorite series") { store.addDiscoverShelf(title: "Favorite Series", favoritesOnly: true, kinds: [.series]) }
                } label: { Label("Add section", systemImage: "plus") }.menuStyle(.borderlessButton).fixedSize().font(.system(size: 12)).foregroundStyle(Theme.accent)
                Button("Done") { store.showDiscoverSettings = false }.buttonStyle(QuietButton()).keyboardShortcut(.cancelAction)
            }.padding(24)
            Divider().overlay(Theme.border)
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("YOUR SECTIONS").font(.system(size: 9, weight: .semibold)).tracking(1.6).foregroundStyle(Theme.muted).padding(.horizontal, 12).padding(.top, 20)
                    ScrollView {
                        LazyVStack(spacing: 5) {
                            ForEach(store.discoverShelves) { shelf in
                                Button { store.editingDiscoverShelfID = shelf.id } label: {
                                    HStack(spacing: 9) {
                                        Image(systemName: shelf.favoritesOnly ? "heart" : "rectangle.stack").frame(width: 17)
                                        Text(shelf.displayTitle).font(.system(size: 12, weight: .medium)).lineLimit(2).multilineTextAlignment(.leading)
                                        Spacer(minLength: 0)
                                    }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                                        .background(selected?.id == shelf.id ? Theme.accent.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: 9))
                                        .foregroundStyle(selected?.id == shelf.id ? Theme.accent : Theme.text)
                                }.buttonStyle(.plain).help(shelf.displayTitle)
                            }
                        }.padding(.horizontal, 8)
                    }
                    if let selected {
                        HStack(spacing: 12) {
                            Button { store.moveDiscoverShelf(selected.id, by: -1) } label: { Image(systemName: "arrow.up") }.disabled(store.discoverShelves.first?.id == selected.id).help("Move section up")
                            Button { store.moveDiscoverShelf(selected.id, by: 1) } label: { Image(systemName: "arrow.down") }.disabled(store.discoverShelves.last?.id == selected.id).help("Move section down")
                            Spacer()
                            Button { deleting = selected } label: { Image(systemName: "trash") }.help("Remove this section")
                        }.buttonStyle(.plain).foregroundStyle(Theme.muted).padding(18)
                    }
                }.frame(width: 220).background(Theme.sidebar)
                Divider().overlay(Theme.border)
                if let selected {
                    DiscoverShelfEditor(shelf: selected).id(selected.id)
                } else {
                    VStack(spacing: 16) {
                        Image(systemName: "rectangle.stack.badge.plus").font(.system(size: 34, weight: .light)).foregroundStyle(Theme.accent)
                        Text("A section for anything you love").font(.system(size: 20, weight: .semibold))
                        Text("Add a section, name it, and choose content from Live TV, Movies, or Series.").font(.system(size: 12)).foregroundStyle(Theme.muted).multilineTextAlignment(.center).frame(maxWidth: 340)
                        Button("Add a section") { store.addDiscoverShelf() }.buttonStyle(AccentButton())
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }.frame(width: 910, height: 640).background(Theme.background).foregroundStyle(Theme.text)
            .onAppear {
                if selected == nil { store.editingDiscoverShelfID = store.discoverShelves.first?.id }
            }
            .confirmationDialog("Remove this Discover section?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
                Button("Remove section", role: .destructive) { if let deleting { store.deleteDiscoverShelf(deleting.id) }; deleting = nil }
                Button("Cancel", role: .cancel) { deleting = nil }
            } message: { Text("Only the Discover layout changes. Your provider content, favorites, and watch history stay saved.") }
    }
}

private enum ShelfBrowser: String, CaseIterable { case categories = "Categories", titles = "Individual titles" }

struct DiscoverShelfEditor: View {
    @EnvironmentObject var store: AppStore
    let shelf: DiscoverShelf
    @State private var kind = MediaKind.live
    @State private var browser = ShelfBrowser.categories
    @State private var search = ""
    @State private var selectedOnly = false
    var categories: [LumaCore.Category] {
        store.library.categories.filter { $0.kind == kind && (search.isEmpty || $0.name.localizedStandardContains(search)) && (!selectedOnly || shelf.categoryIDs.contains($0.id)) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    var titles: [MediaItem] {
        Array(store.library.items.lazy.filter { $0.kind == kind && (search.isEmpty || $0.title.localizedStandardContains(search)) && (!selectedOnly || shelf.itemIDs.contains($0.id)) }.prefix(200))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 7) {
                Text("SECTION NAME").font(.system(size: 9, weight: .semibold)).tracking(1.4).foregroundStyle(Theme.muted)
                TextField("Section name", text: Binding(get: { shelf.title }, set: { value in store.updateDiscoverShelf(shelf.id) { $0.title = value } }))
                    .textFieldStyle(.plain).font(.system(size: 20, weight: .semibold)).padding(11).background(Theme.surface, in: RoundedRectangle(cornerRadius: 9))
                    .accessibilityLabel("Discover section name")
            }
            Picker("Content source", selection: Binding(get: { shelf.favoritesOnly }, set: { value in store.updateDiscoverShelf(shelf.id) { $0.favoritesOnly = value } })) {
                Text("Selected categories & titles").tag(false)
                Text("Favorites").tag(true)
            }.font(.system(size: 12))
            if shelf.favoritesOnly { favoritesEditor }
            else { selectionEditor }
        }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .onAppear {
                kind = store.library.categories.first(where: { shelf.categoryIDs.contains($0.id) })?.kind
                    ?? store.library.items.first(where: { shelf.itemIDs.contains($0.id) })?.kind
                    ?? DiscoverSection(rawValue: shelf.id)?.kind ?? .live
            }
    }
    var favoritesEditor: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Automatically show items you favorite in the library. Choose the content types to include.").font(.system(size: 12)).foregroundStyle(Theme.muted).lineSpacing(4)
            ForEach(MediaKind.allCases, id: \.self) { kind in
                Toggle(kind.title, isOn: Binding(get: { shelf.favoriteKinds.contains(kind) }, set: { enabled in
                    store.updateDiscoverShelf(shelf.id) { updated in
                        if enabled { updated.favoriteKinds.insert(kind) } else { updated.favoriteKinds.remove(kind) }
                    }
                })).toggleStyle(.checkbox).font(.system(size: 13))
            }
            let count = store.library.items.filter { shelf.includes($0, favorites: store.user.favorites) }.count
            Label("\(count) favorites in this section", systemImage: "heart").font(.system(size: 12)).foregroundStyle(Theme.accent)
            Spacer()
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading).background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
    }
    var selectionEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Combine categories and individual titles from any tab. Category selections include all titles in those categories.").font(.system(size: 11)).foregroundStyle(Theme.muted).lineSpacing(3)
            Picker("Browse content type", selection: $kind) { ForEach(MediaKind.allCases, id: \.self) { Text($0.title).tag($0) } }.pickerStyle(.segmented).labelsHidden().onChange(of: kind) { search = "" }
            HStack {
                Picker("Select", selection: $browser) { ForEach(ShelfBrowser.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.labelsHidden().fixedSize().onChange(of: browser) { search = "" }
                Spacer()
                Toggle("Selected only", isOn: $selectedOnly).toggleStyle(.checkbox).font(.system(size: 11))
            }
            HStack(spacing: 9) {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.muted)
                TextField(browser == .categories ? "Search categories" : "Search channels or titles", text: $search).textFieldStyle(.plain).font(.system(size: 12))
                    .accessibilityLabel("Search Discover content")
                if !search.isEmpty { Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).foregroundStyle(Theme.muted) }
            }.padding(10).background(Theme.surface, in: RoundedRectangle(cornerRadius: 9))
            HStack {
                Text("\(shelf.categoryIDs.count) categories · \(shelf.itemIDs.count) individual titles").font(.system(size: 10)).foregroundStyle(Theme.muted)
                Spacer()
                Button("Clear selection") { store.updateDiscoverShelf(shelf.id) { $0.categoryIDs = []; $0.itemIDs = [] } }.buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(Theme.accent).disabled(shelf.isEmptySelection)
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if browser == .categories {
                        ForEach(categories) { category in
                            Toggle(category.name, isOn: Binding(get: { shelf.categoryIDs.contains(category.id) }, set: { selected in
                                store.updateDiscoverShelf(shelf.id) { updated in
                                    if selected { updated.categoryIDs.insert(category.id) } else { updated.categoryIDs.remove(category.id) }
                                }
                            })).toggleStyle(.checkbox).font(.system(size: 12)).padding(.vertical, 10)
                        }
                        if categories.isEmpty { emptyResults }
                    } else {
                        ForEach(titles) { item in
                            Toggle(isOn: Binding(get: { shelf.itemIDs.contains(item.id) }, set: { selected in
                                store.updateDiscoverShelf(shelf.id) { updated in
                                    if selected { updated.itemIDs.insert(item.id) } else { updated.itemIDs.remove(item.id) }
                                }
                            })) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.title).font(.system(size: 12)).lineLimit(2)
                                    Text(store.library.categories.first(where: { $0.id == item.categoryID })?.name ?? item.kind.title).font(.system(size: 10)).foregroundStyle(Theme.muted).lineLimit(1)
                                }
                            }.toggleStyle(.checkbox).padding(.vertical, 9)
                        }
                        if titles.isEmpty { emptyResults }
                        if titles.count == 200 { Text("Showing the first 200 matches. Narrow your search to find another title.").font(.system(size: 10)).foregroundStyle(Theme.muted).padding(.vertical, 12) }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
    var emptyResults: some View { Text(selectedOnly ? "No selected content matches this tab and search." : "No matching content from this provider.").font(.system(size: 12)).foregroundStyle(Theme.muted).padding(.vertical, 25) }
}
