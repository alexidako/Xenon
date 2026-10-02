import SwiftUI

struct DetailView: View {
    enum Tab: String, CaseIterable {
        case overview = "Overview", atom = "Atom", isotopes = "Isotopes", spectrum = "Spectrum", misc = "Misc", links = "Links"
    }

    let element: Element
    @ObservedObject private var prefs = Preferences.shared
    @State private var tab: Tab = {
        // Debug hook: XENON_START="6:spectrum" opens element 6 on that tab.
        let parts = (ProcessInfo.processInfo.environment["XENON_START"] ?? "").split(separator: ":")
        return parts.count == 2 ? Tab(rawValue: parts[1].capitalized) ?? .overview : .overview
    }()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                Picker("", selection: $tab) {
                    ForEach(Tab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().controlSize(.small)

                switch tab {
                case .overview: overview
                case .atom: AtomModelView(element: element)
                case .isotopes: IsotopeListView(element: element)
                case .spectrum: SpectrumView(element: element)
                case .misc: misc
                case .links: links
                }
            }
            .padding(20)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack {
                Text("\(element.z)").font(.caption)
                Text(element.symbol).font(.system(size: 44, weight: .bold))
                Text(fmt(element.mass)).font(.caption)
            }
            .frame(width: 90, height: 90)
            .background(RoundedRectangle(cornerRadius: 8).fill(element.familyKind?.color ?? .gray.opacity(0.4)))
            .foregroundStyle(.black.opacity(0.85))
            VStack(alignment: .leading, spacing: 4) {
                Text(element.name).font(.largeTitle.bold())
                Text(element.familyKind?.label ?? "").foregroundStyle(.secondary)
            }
        }
    }

    // MARK: tabs

    private var overview: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let origin = element.nameOrigin, !origin.isEmpty {
                Text(origin).italic().foregroundStyle(.secondary)
            }
            GroupBox("Classification") {
                grid {
                    row("Group / period", "\(element.iupacGroup.map(String.init) ?? "—") / \(element.period.map(String.init) ?? "—")")
                    row("Block", element.block ?? "—")
                    row("Electron configuration", element.configuration.map(QuizEngine.pretty) ?? "—")
                    row("Oxidation states", element.oxidation.isEmpty ? "—"
                        : element.oxidation.map { $0 > 0 ? "+\($0)" : "\($0)" }.joined(separator: ", "))
                }
            }
            GroupBox("Mass & size") {
                grid {
                    row("Atomic mass", fmt(element.mass, "u"))
                    row("Exact mass", fmt(element.exactMass, "u"))
                    row("Covalent radius", prefs.lengthText(element.radiusCovalent))
                    row("Van der Waals radius", prefs.lengthText(element.radiusVDW))
                }
            }
            GroupBox("Energies") {
                grid {
                    row("Electronegativity (Pauling)", fmt(element.electronegativity))
                    row("First ionization energy", prefs.energyText(element.ionization))
                    row("Electron affinity", prefs.energyText(element.electronAffinity))
                }
            }
            GroupBox("Phase changes") {
                grid {
                    row("Melting point", prefs.temperatureText(element.meltingPoint))
                    row("Boiling point", prefs.temperatureText(element.boilingPoint))
                }
            }
        }
    }

    private static let countries = [
        "de": "Germany", "dk": "Denmark", "es": "Spain", "fi": "Finland", "fr": "France", "it": "Italy", "ru": "Russia",
        "se": "Sweden", "uk": "United Kingdom", "us": "United States", "ch": "Switzerland", "at": "Austria", "pl": "Poland",
        "nl": "Netherlands", "jp": "Japan", "ca": "Canada", "be": "Belgium", "no": "Norway", "ie": "Ireland", "hu": "Hungary",
        "ua": "Ukraine", "cz": "Czech Republic", "pt": "Portugal", "mx": "Mexico", "au": "Australia", "ar": "Argentina",
        "co": "Colombia", "sk": "Slovakia", "cn": "China", "in": "India", "ancient": "Known since antiquity",
    ]

    private var misc: some View {
        VStack(alignment: .leading, spacing: 14) {
            GroupBox("Discovery") {
                grid {
                    row("Year", element.discoveryYear.map { $0 == 0 ? "known since antiquity" : String(Int($0)) } ?? "known since antiquity")
                    row("Discovered by", element.discoverers.isEmpty ? "—" : element.discoverers.joined(separator: ", "))
                    row("Country", element.discoveryCountry.isEmpty ? "—"
                        : element.discoveryCountry.map { Self.countries[$0.lowercased()] ?? $0.uppercased() }.joined(separator: ", "))
                }
            }
            GroupBox("Name") {
                Text(element.nameOrigin ?? "—").frame(maxWidth: .infinity, alignment: .leading).padding(8).textSelection(.enabled)
            }
            if let use = ReferenceStore.data?.uses[String(element.z)] {
                GroupBox("Use") { Text(Markup.attributed(use)).frame(maxWidth: .infinity, alignment: .leading).padding(8) }
            }
        }
    }

    private var links: some View {
        let slug = element.name.lowercased()
        let jlab = String(format: "https://education.jlab.org/itselemental/ele%03d.html", element.z)
        return VStack(alignment: .leading, spacing: 10) {
            Text(tr("Look up {name} online", ["name": tr(element.name)])).foregroundStyle(.secondary)
            Link("Wikipedia", destination: URL(string: "https://en.wikipedia.org/wiki/\(element.name)")!)
            Link("Jefferson Lab – It's Elemental", destination: URL(string: jlab)!)
            Link("WebElements", destination: URL(string: "https://www.webelements.com/\(slug)/")!)
        }
    }

    // MARK: helpers

    private func grid<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) { content() }
            .padding(8).frame(maxWidth: .infinity, alignment: .leading)
    }

    private func row(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Text(value).textSelection(.enabled)
        }
    }

    private func fmt(_ v: Double?, _ unit: String = "") -> String {
        guard let v else { return "—" }
        let s = v.formatted(.number.precision(.fractionLength(0...4)))
        return unit.isEmpty ? s : "\(s) \(unit)"
    }
}
