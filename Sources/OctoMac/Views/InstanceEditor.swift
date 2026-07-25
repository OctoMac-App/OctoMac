import OctoPrintKit
import SwiftUI

/// Add / edit an OctoPrint server, including obtaining an API key via the Application Keys workflow.
struct InstanceEditor: View {
    @Environment(InstanceStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let target: EditorTarget
    var onSave: (UUID) -> Void = { _ in }

    @State private var name = ""
    @State private var address = ""
    @State private var apiKey = ""
    @State private var username = ""
    @State private var throttle = 1
    @State private var filamentHex: String?
    @State private var accessMode: AccessMode = .request
    @State private var status: Status = .idle
    @State private var work: Task<Void, Never>?
    @State private var confirmRemove = false

    enum Status: Equatable {
        case idle
        case working(String)
        case success(String)
        case failure(String)
    }

    enum AccessMode: String, CaseIterable {
        case request, paste
    }

    private var existing: Instance? {
        if case .edit(let instance) = target { return instance }
        return nil
    }

    private var url: URL? { Instance.normalisedURL(from: address) }
    private var filament: Color { filamentHex.flatMap(Color.init(hexString:)) ?? Palette.filaments[0] }
    private var canSave: Bool { url != nil && !name.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 28)
                .padding(.top, 26)
                .padding(.bottom, 20)

            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    serverSection
                    colourSection
                    accessSection
                    updatesSection
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 24)
            }

            footer
        }
        .frame(width: 560, height: 680)
        .background(Palette.extrusion)
        .onAppear(perform: load)
        .sheet(isPresented: $confirmRemove) {
            ConfirmSheet(symbol: "minus.circle", title: "Remove \(existing?.name ?? "this printer")?",
                         message: "OctoMac forgets this server and its API key. Nothing changes on the printer, and you can add it again later.",
                         confirmTitle: "Remove printer") {
                if let existing { store.remove(existing.id) }
                dismiss()
            }
        }
    }

    // MARK: Sections

    private var header: some View {
        HStack(spacing: 16) {
            BrandMark()
                .frame(width: 52, height: 52)
            VStack(alignment: .leading, spacing: 2) {
                Text(existing == nil ? "Add a printer" : "Edit \(existing?.name ?? "printer")")
                    .font(Typeface.title)
                    .foregroundStyle(Palette.paper)
                Text(existing == nil ? "Connect OctoMac to an OctoPrint server." : "Change how OctoMac reaches this OctoPrint server.")
                    .font(Typeface.body)
                    .foregroundStyle(Palette.dust)
            }
        }
    }

    private var serverSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            field("Name") {
                TextField("", text: $name, prompt: Text("Workshop Prusa").foregroundStyle(Palette.faint))
                    .plateField()
            }
            field("Address") {
                TextField("", text: $address, prompt: Text("octopi.local or https://printer.example.com").foregroundStyle(Palette.faint))
                    .plateField()
                if !address.isEmpty {
                    if let url {
                        Label("Connects to \(url.absoluteString)", systemImage: "arrow.right")
                            .font(Typeface.number(12))
                            .foregroundStyle(Palette.faint)
                    } else {
                        Label("That doesn't look like an address yet.", systemImage: "exclamationmark.circle")
                            .font(Typeface.caption)
                            .foregroundStyle(Palette.warm)
                    }
                }
            }
        }
    }

    private var colourSection: some View {
        field("Colour", detail: "Marks this printer in the sidebar and its progress") {
            HStack(spacing: 10) {
                ForEach(Palette.filaments.compactMap(\.hexString), id: \.self) { hex in
                    let selected = (filamentHex ?? Palette.filaments[0].hexString) == hex
                    Button { filamentHex = hex } label: {
                        Circle()
                            .fill(Color(hexString: hex) ?? .gray)
                            .frame(width: 26, height: 26)
                            .padding(4)
                            .overlay(Circle().strokeBorder(selected ? Palette.paper : .clear, lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                    .help(hex)
                }
                ColorPicker("Custom colour", selection: Binding(
                    get: { filament },
                    set: { filamentHex = $0.hexString }
                ), supportsOpacity: false)
                .labelsHidden()
                .help("Pick any colour")
            }
        }
    }

    private var accessSection: some View {
        field("Access", detail: "OctoMac needs an API key from this server") {
            HStack(spacing: 10) {
                accessOption(.request, title: "Request access", detail: "Approve it in OctoPrint's web page", symbol: "hand.raised.fill")
                accessOption(.paste, title: "Paste a key", detail: "From OctoPrint's settings", symbol: "key.horizontal.fill")
            }

            Group {
                switch accessMode {
                case .request:
                    HStack(spacing: 10) {
                        TextField("", text: $username, prompt: Text("OctoPrint username (optional)").foregroundStyle(Palette.faint))
                            .plateField()
                        Button(apiKey.isEmpty ? "Request access" : "Request again", action: requestKey)
                            .buttonStyle(.plate)
                            .disabled(url == nil || isWorking)
                    }
                case .paste:
                    SecureField("", text: $apiKey, prompt: Text("API key").foregroundStyle(Palette.faint))
                        .plateField()
                }
            }
            .padding(.top, 4)

            HStack(spacing: 10) {
                statusView
                Spacer()
                if isWorking {
                    Button("Stop") { work?.cancel() }.buttonStyle(.plateQuiet)
                }
                Button("Test connection", action: test)
                    .buttonStyle(.plateQuiet)
                    .disabled(url == nil || isWorking)
            }
            .controlSize(.small)
            .frame(minHeight: 30)
        }
    }

    private var updatesSection: some View {
        field("Live updates", detail: "How often OctoPrint sends temperatures and progress") {
            HStack(spacing: 8) {
                ForEach([(1, "Every 0.5s"), (2, "1s"), (4, "2s"), (10, "5s")], id: \.0) { value, title in
                    Chip(title: title, selected: throttle == value) { throttle = value }
                }
            }
            Text("Events like a print finishing always arrive instantly. Slow updates down only on a poor connection.")
                .font(Typeface.caption)
                .foregroundStyle(Palette.faint)
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if existing != nil {
                Button("Remove printer…") { confirmRemove = true }
                    .buttonStyle(.plain)
                    .font(Typeface.bodyStrong)
                    .foregroundStyle(Palette.hot)
            }
            Spacer()
            Button("Cancel") { work?.cancel(); dismiss() }
                .buttonStyle(.plateQuiet)
                .keyboardShortcut(.cancelAction)
            Button(existing == nil ? "Add printer" : "Save changes", action: save)
                .buttonStyle(.plate)
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 18)
        .background(Palette.graphite)
    }

    // MARK: Pieces

    private func field<Content: View>(_ title: String, detail: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title).font(Typeface.bodyStrong).foregroundStyle(Palette.paper)
                if let detail { Text(detail).font(Typeface.caption).foregroundStyle(Palette.faint) }
            }
            content()
        }
    }

    private func accessOption(_ mode: AccessMode, title: String, detail: String, symbol: String) -> some View {
        let selected = accessMode == mode
        return Button { accessMode = mode } label: {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(selected ? Palette.accent : Palette.faint)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(Typeface.bodyStrong).foregroundStyle(Palette.paper)
                    Text(detail).font(Typeface.caption).foregroundStyle(Palette.dust)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(selected ? Palette.extrusionHi : Palette.graphite))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(selected ? Palette.accent : Palette.edge, lineWidth: selected ? 1.5 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var statusView: some View {
        switch status {
        case .idle:
            if !apiKey.isEmpty {
                Label("Key saved", systemImage: "checkmark.seal.fill").font(Typeface.caption).foregroundStyle(Palette.ready)
            } else {
                Text("No key yet").font(Typeface.caption).foregroundStyle(Palette.faint)
            }
        case .working(let message):
            HStack(spacing: 8) {
                ProgressView().controlSize(.small).tint(Palette.accent)
                Text(message).font(Typeface.caption).foregroundStyle(Palette.dust)
            }
        case .success(let message):
            Label(message, systemImage: "checkmark.circle.fill").font(Typeface.caption).foregroundStyle(Palette.ready)
        case .failure(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill").font(Typeface.caption).foregroundStyle(Palette.hot)
                .lineLimit(2)
        }
    }

    private var isWorking: Bool {
        if case .working = status { return true }
        return false
    }

    // MARK: Actions

    private func load() {
        guard let existing else {
            filamentHex = store.suggestedFilamentHex()
            return
        }
        name = existing.name
        address = existing.baseURL.absoluteString
        apiKey = CredentialStore.apiKey(for: existing.id) ?? ""
        throttle = existing.pushThrottle
        filamentHex = existing.filamentHex
        accessMode = apiKey.isEmpty ? .request : .paste
    }

    private func requestKey() {
        guard let url else { return }
        status = .working("Approve the request in the OctoPrint page that just opened…")
        let user = username
        work = Task {
            do {
                apiKey = try await AppKeysAuthorizer(baseURL: url).requestKey(user: user) { dialog in
                    await MainActor.run { _ = NSWorkspace.shared.open(dialog) }
                }
                status = .success("Access granted")
                if name.isEmpty { name = url.host() ?? "OctoPrint" }
            } catch is CancellationError {
                status = .idle
            } catch {
                status = .failure(error.localizedDescription)
            }
        }
    }

    private func test() {
        guard let url else { return }
        status = .working("Connecting…")
        let client = OctoPrintClient(baseURL: url, apiKey: apiKey)
        work = Task {
            do {
                let version = try await client.version()
                let user = try? await client.currentUser()
                status = .success("OctoPrint \(version.server)" + (user?.name.map { ", signed in as \($0)" } ?? ""))
            } catch {
                status = .failure(error.localizedDescription)
            }
        }
    }

    private func save() {
        guard let url else { return }
        work?.cancel()
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        if var instance = existing {
            instance.name = trimmedName
            instance.baseURL = url
            instance.pushThrottle = throttle
            instance.filamentHex = filamentHex
            store.update(instance, apiKey: apiKey)
            onSave(instance.id)
        } else {
            let instance = Instance(name: trimmedName, baseURL: url, pushThrottle: throttle, filamentHex: filamentHex)
            store.add(instance, apiKey: apiKey)
            onSave(instance.id)
        }
        dismiss()
    }
}
