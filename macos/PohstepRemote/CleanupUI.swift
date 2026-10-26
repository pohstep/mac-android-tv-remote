#if ZAPBAR_ADVANCED
import SwiftUI

struct AdvancedCleanupSection: View {
    @ObservedObject var model: AppModel
    @State private var warningsOpen = false
    @State private var recoveryOpen = false
    @State private var extraName = ""

    var body: some View {
        DisclosureGroup(isExpanded: $model.advancedExpanded) {
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Clean up", isOn: $model.cleanupEnabled)
                    .font(.system(size: 12))
                Text("Off until you turn it on. Nothing is removed.")
                    .font(.system(size: 11))
                    .foregroundColor(Palette.tertiary)
                if model.cleanupEnabled {
                    cleanup
                }
            }
            .padding(.top, 6)
        } label: {
            Text("Advanced")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Palette.text)
        }
        .onChange(of: model.advancedExpanded) { _ in
            model.persistAdvancedFlags()
        }
        .onChange(of: model.cleanupEnabled) { _ in
            model.persistAdvancedFlags()
        }
        .onAppear {
            model.reloadCleanupUndo()
        }
    }

    private var cleanup: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Button("Look up packages") { model.refreshCleanup() }
                    .disabled(model.cleanupBusy)
                Button("Turn off selected") { model.applyCleanup() }
                    .disabled(model.cleanupBusy || selected.isEmpty)
                Button("Restore all") { model.restoreCleanupAll() }
                    .disabled(model.cleanupBusy || model.cleanupUndo.isEmpty)
            }
            .font(.system(size: 12))
            if !model.cleanupLine.isEmpty {
                Text(model.cleanupLine)
                    .font(.system(size: 11))
                    .foregroundColor(Palette.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(model.cleanupRows) { row in
                rowToggle(row, warning: false)
            }
            if !model.cleanupWarnings.isEmpty {
                DisclosureGroup(isExpanded: $warningsOpen) {
                    ForEach(model.cleanupWarnings) { row in
                        rowToggle(row, warning: true)
                    }
                } label: {
                    Text("Extra, with a warning")
                        .font(.system(size: 11, weight: .semibold))
                }
            }
            HStack(spacing: 8) {
                TextField("Add a package name", text: $extraName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { addName() }
                Button("Add") { addName() }
                    .disabled(model.cleanupBusy)
            }
            .font(.system(size: 12))
            if !model.cleanupUndo.isEmpty {
                Text("Turned off from this Mac")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Palette.text)
                ForEach(model.cleanupUndo, id: \.self) { name in
                    HStack {
                        Text(name)
                            .font(.system(size: 11))
                            .foregroundColor(Palette.secondary)
                        Spacer(minLength: 8)
                        Button("Turn back on") { model.restoreCleanupOne(name) }
                            .font(.system(size: 11))
                            .disabled(model.cleanupBusy)
                    }
                }
            }
            DisclosureGroup(isExpanded: $recoveryOpen) {
                Text(CleanupCopy.recoveryBody)
                    .font(.system(size: 11))
                    .foregroundColor(Palette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } label: {
                Text(CleanupCopy.recoveryTitle)
                    .font(.system(size: 11, weight: .semibold))
            }
        }
    }

    private var selected: [String] {
        model.cleanupRows.filter(\.ticked).map(\.name) + model.cleanupWarnings.filter(\.ticked).map(\.name)
    }

    private func addName() {
        let name = extraName.trimmingCharacters(in: .whitespacesAndNewlines)
        extraName = ""
        guard !name.isEmpty else { return }
        model.addCleanupPackage(name)
    }

    private func rowToggle(_ row: CleanupRow, warning: Bool) -> some View {
        Toggle(isOn: tick(row, warning: warning)) {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.name)
                    .font(.system(size: 11, weight: .medium))
                Text(row.reason)
                    .font(.system(size: 11))
                    .foregroundColor(Palette.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .disabled(model.cleanupBusy)
        .font(.system(size: 11))
    }

    private func tick(_ row: CleanupRow, warning: Bool) -> Binding<Bool> {
        Binding(
            get: {
                let rows = warning ? model.cleanupWarnings : model.cleanupRows
                return rows.first { $0.name == row.name }?.ticked ?? false
            },
            set: { model.setCleanupTick(row.name, on: $0, warning: warning) }
        )
    }
}

private enum CleanupFiles {
    static func rules() -> NeverTouchRuleSet? {
        guard let url = Bundle.main.url(forResource: "never-touch", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? NeverTouchRuleSet(data: data)
    }

    static func catalog() -> CleanupCatalog? {
        guard let url = Bundle.main.url(forResource: "cleanup-preview", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? CleanupCatalog(data: data)
    }
}

extension AppModel {
    func persistAdvancedFlags() {
        UserDefaults.standard.set(advancedExpanded, forKey: "zapbar.advanced.expanded")
        UserDefaults.standard.set(cleanupEnabled, forKey: "zapbar.cleanup.enabled")
    }

    func reloadCleanupUndo() {
        let id = settings.activeDeviceID
        guard !id.isEmpty else {
            cleanupUndo = []
            return
        }
        let store = UndoStore(directory: UndoStore.defaultDirectory())
        cleanupUndo = store.load(tvID: id)?.restorableNames ?? []
    }

    func setCleanupTick(_ name: String, on: Bool, warning: Bool) {
        if warning {
            cleanupWarnings = cleanupWarnings.map { row in
                guard row.name == name else { return row }
                return CleanupRow(name: row.name, reason: row.reason, ticked: on, warning: true)
            }
        } else {
            cleanupRows = cleanupRows.map { row in
                guard row.name == name else { return row }
                return CleanupRow(name: row.name, reason: row.reason, ticked: on, warning: false)
            }
        }
    }

    func addCleanupPackage(_ raw: String) {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard PackageName.isValid(name) else {
            cleanupLine = "That isn't a package name."
            return
        }
        if !cleanupExtras.contains(name) {
            cleanupExtras.append(name)
        }
        refreshCleanup()
    }

    func refreshCleanup() {
        guard !cleanupBusy else { return }
        cleanupBusy = true
        cleanupLine = "Looking up packages…"
        let extras = cleanupExtras
        let brand = settings.brand
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let outcome = self.loadPreview(extras: extras, brand: brand)
            DispatchQueue.main.async {
                self.cleanupBusy = false
                switch outcome {
                case .missingData:
                    self.cleanupLine = "Clean-up data is missing from this build."
                case .offline:
                    self.cleanupLine = "This needs a network debugging connection."
                case .ready(let preview):
                    self.cleanupRows = preview.rows
                    self.cleanupWarnings = preview.warnings
                    self.cleanupLine = self.previewLine(preview)
                }
                self.reloadCleanupUndo()
            }
        }
    }

    func applyCleanup() {
        let names = cleanupRows.filter(\.ticked).map(\.name) + cleanupWarnings.filter(\.ticked).map(\.name)
        guard !names.isEmpty else {
            cleanupLine = CleanupCopy.chooseOne
            return
        }
        runCleanup { runner, store, tvID, brand in
            runner.disable(names: names, brand: brand, tvID: tvID, store: store)
        }
    }

    func restoreCleanupAll() {
        runCleanup { runner, store, tvID, _ in
            runner.restore(names: nil, tvID: tvID, store: store)
        }
    }

    func restoreCleanupOne(_ name: String) {
        runCleanup { runner, store, tvID, _ in
            runner.restore(names: [name], tvID: tvID, store: store)
        }
    }

    private func runCleanup(_ work: @escaping (CleanupRunner, UndoStore, String, TvBrand) -> CleanupReport) {
        guard !cleanupBusy else { return }
        guard !jobBusy else {
            cleanupLine = "Wait for the other task to finish."
            return
        }
        let tvID = settings.activeDeviceID
        guard !tvID.isEmpty else {
            cleanupLine = "Save the TV first."
            return
        }
        let brand = settings.brand
        cleanupBusy = true
        cleanupLine = "Working…"
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let report: CleanupReport
            if let runner = self.makeCleanupRunner() {
                let store = UndoStore(directory: UndoStore.defaultDirectory())
                report = work(runner, store, tvID, brand)
            } else if CleanupFiles.rules() == nil || CleanupFiles.catalog() == nil {
                report = CleanupReport(sentence: "Clean-up data is missing from this build.", isError: true)
            } else {
                report = CleanupReport(sentence: "This needs a network debugging connection.", isError: true)
            }
            DispatchQueue.main.async {
                self.cleanupBusy = false
                self.cleanupLine = report.sentence
                self.reloadCleanupUndo()
            }
        }
    }

    private enum PreviewOutcome {
        case missingData
        case offline
        case ready(CleanupPreview)
    }

    private func loadPreview(extras: [String], brand: TvBrand) -> PreviewOutcome {
        guard let rules = CleanupFiles.rules(), let catalog = CleanupFiles.catalog() else {
            return .missingData
        }
        guard let link = session.cleanupConnection() else { return .offline }
        let runner = CleanupRunner(client: link.client, serial: link.serial, rules: rules, catalog: catalog)
        do {
            return .ready(try runner.preview(brand: brand, extras: extras))
        } catch {
            return .offline
        }
    }

    private func makeCleanupRunner() -> CleanupRunner? {
        guard let rules = CleanupFiles.rules(), let catalog = CleanupFiles.catalog() else { return nil }
        guard let link = session.cleanupConnection() else { return nil }
        return CleanupRunner(client: link.client, serial: link.serial, rules: rules, catalog: catalog)
    }

    private func previewLine(_ preview: CleanupPreview) -> String {
        var line = preview.note
        if preview.rejected.count == 1 {
            let item = preview.rejected[0]
            line += " \(item.name) was left out. \(item.reason)"
        } else if preview.rejected.count > 1 {
            line += " \(preview.rejected.count) names were left out."
        }
        return line
    }
}
#endif
