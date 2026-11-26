import SwiftUI

/// One row of a searchable country list: a country, or a special choice (e.g. "申根区" or "自动").
struct CountryChoice: Identifiable, Hashable {
    let code: String
    let flag: String
    let name: String
    /// Lowercased names in Chinese, English, and extra aliases (matches anywhere).
    let names: [String]
    /// ISO code, Chinese full pinyin, and pinyin initials (matches from start).
    let shorthands: [String]

    var id: String { code }

    init(code: String, flag: String? = nil, name: String, alsoFoundBy extra: [String] = []) {
        self.code = code
        self.flag = flag ?? (code.isEmpty ? "" : CountryText.flag(for: code))
        self.name = name
        var words = [name] + extra
        if !code.isEmpty {
            for locale in ["zh-Hans", "en"] {
                if let other = Locale(identifier: locale).localizedString(forRegionCode: code) {
                    words.append(other)
                }
            }
        }
        var shorthands = [Self.folded(code)]
        for word in words where Self.hasHan(word) {
            let syllables = (word.applyingTransform(.toLatin, reverse: false) ?? "")
                .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
                .split(separator: " ")
            shorthands.append(syllables.joined())
            shorthands.append(String(syllables.compactMap(\.first)))
        }
        self.names = words.map(Self.folded).filter { !$0.isEmpty }
        self.shorthands = shorthands.filter { !$0.isEmpty }
    }

    private static func hasHan(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            (0x4E00...0x9FFF).contains(scalar.value) || (0x3400...0x4DBF).contains(scalar.value)
        }
    }

    /// Lowercased, without accents or spaces: "Côte d'Ivoire" is found by "cote".
    static func folded(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: nil)
            .replacingOccurrences(of: " ", with: "")
    }

    /// Prefix matches come before substring matches.
    static func search(_ choices: [CountryChoice], for text: String) -> [CountryChoice] {
        let query = folded(text.trimmingCharacters(in: .whitespaces))
        guard !query.isEmpty else { return choices }
        let starting = choices.filter { choice in
            (choice.names + choice.shorthands).contains { $0.hasPrefix(query) }
        }
        let startingSet = Set(starting)
        let containing = choices.filter { choice in
            !startingSet.contains(choice) && choice.names.contains { $0.contains(query) }
        }
        return starting + containing
    }

    /// All ISO countries/regions sorted by localized Chinese name (computed once).
    static let all: [CountryChoice] = {
        let codes = WorldContinent.all.flatMap(\.regions)
        let unique = Array(Set(codes))
        let mapped = unique.map { code in
            CountryChoice(code: code, name: CountryText.localizedName(code: code))
        }
        return mapped.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }()
}

/// A form row that opens a searchable country list (supports Chinese, English, pinyin, initials, and ISO code).
struct CountryPickerRow: View {
    let title: String
    @Binding var selection: String
    var leading: [CountryChoice] = []

    @State private var choices: [CountryChoice] = []

    private var current: CountryChoice? {
        leading.first { $0.code == selection } ?? choices.first { $0.code == selection }
    }

    var body: some View {
        NavigationLink {
            CountrySearchListView(title: title, selection: $selection, leading: leading, countries: choices.isEmpty ? CountryChoice.all : choices)
        } label: {
            HStack {
                Text(title)
                    .foregroundColor(.primary)
                Spacer(minLength: 8)
                if let current {
                    Text([current.flag, current.name].filter { !$0.isEmpty }.joined(separator: " "))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                } else if !selection.isEmpty {
                    Text("\(CountryText.flag(for: selection)) \(CountryText.localizedName(code: selection))")
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .task {
            if choices.isEmpty {
                choices = await Task.detached(priority: .userInitiated) { CountryChoice.all }.value
            }
        }
    }
}

private struct CountrySearchListView: View {
    let title: String
    @Binding var selection: String
    let leading: [CountryChoice]
    let countries: [CountryChoice]

    @State private var query = ""
    @Environment(\.dismiss) private var dismiss

    private var searching: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }
    private var found: [CountryChoice] { CountryChoice.search(leading + countries, for: query) }

    var body: some View {
        List {
            if searching {
                if found.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.title2)
                            .foregroundColor(.secondary)
                        Text("未找到“\(query)”")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Text("支持中文、英文、拼音、首字母或国家代码（如 JP）")
                            .font(.caption)
                            .foregroundColor(Color(.tertiaryLabel))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 28)
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(found) { row($0) }
                }
            } else {
                if !leading.isEmpty {
                    Section {
                        ForEach(leading) { row($0) }
                    }
                }
                Section {
                    ForEach(countries) { row($0) }
                }
            }
        }
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "搜索国家或地区（中文/英文/拼音/代码）")
        .autocorrectionDisabled()
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ choice: CountryChoice) -> some View {
        Button {
            UISelectionFeedbackGenerator().selectionChanged()
            selection = choice.code
            dismiss()
        } label: {
            HStack(spacing: 10) {
                if !choice.flag.isEmpty {
                    Text(choice.flag)
                }
                Text(choice.name)
                    .foregroundColor(.primary)
                Spacer()
                if choice.code == selection {
                    Image(systemName: "checkmark")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.accentColor)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
