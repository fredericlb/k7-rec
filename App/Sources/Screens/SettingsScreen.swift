// Settings: the lyrics lead, the headset microphone, the file server, iCloud and the About line.
import SwiftUI

struct SettingsScreen: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var prefs = model.prefs
        NavigationStack {
            Form {
                Section {
                    Stepper(value: $prefs.lyricsLead, in: 0...5, step: 0.5) { LabeledContent("Lyrics lead", value: String(format: "%.1f s", prefs.lyricsLead)) }
                } header: { Text("Playing") } footer: { Text("A tap on a timed lyric line starts the song this much before it.") }
                Section {
                    Toggle("Use the headset microphone", isOn: $prefs.headsetInput)
                } header: { Text("Recording") } footer: { Text("Off: takes use the phone's microphone and earphones keep full-quality sound. On: a Bluetooth headset's own microphone, in narrowband sound.") }
                serverSection
                if let sync = model.sync { syncSection(sync) }
                Section("About") { LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "") }
            }
            .navigationTitle("Settings")
        }
    }

    @ViewBuilder private func syncSection(_ sync: SyncDriver) -> some View {
        Section {
            LabeledContent("Files", value: sync.inCloud ? "iCloud Drive" : "This device only")
            if let report = sync.report {
                LabeledContent("Records", value: report.pending > 0 ? "\(report.records) (\(report.pending) still downloading)" : "\(report.records)")
            }
            if let last = sync.lastRun { LabeledContent("Last sync", value: last.formatted(date: .omitted, time: .standard)) }
            Button { sync.schedule(after: 0) } label: { if sync.running { ProgressView() } else { Text("Sync now") } }.disabled(sync.running)
        } header: { Text("iCloud") } footer: {
            Text(sync.inCloud ? "Songs and takes follow your iCloud account. A record written on another device can take a few minutes to arrive." : "iCloud is not available to the app: sign in to iCloud and turn on iCloud Drive, then relaunch.")
        }
    }

    @ViewBuilder private var serverSection: some View {
        @Bindable var server = model.server
        Section {
            if server.connected {
                LabeledContent("Protocol", value: server.kind.label)
                LabeledContent("Server", value: server.host)
                LabeledContent("Folder", value: server.folder)
                if let key = server.hostKey { LabeledContent("Host key", value: key).font(.footnote) }
                Button("Disconnect", role: .destructive) { server.disconnect() }
            } else {
                Picker("Protocol", selection: $server.kind) { ForEach(RemoteProtocol.allCases) { Text($0.label).tag($0) } }
                TextField("Address", text: $server.host).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                TextField("Port", text: $server.port).keyboardType(.numberPad)
                TextField("User", text: $server.user).textInputAutocapitalization(.never).autocorrectionDisabled()
                SecureField("Password", text: $server.password)
                TextField("Folder", text: $server.folder).textInputAutocapitalization(.never).autocorrectionDisabled()
                if server.kind != .sftp { Toggle("Accept an untrusted certificate", isOn: $server.trustAnyCertificate) }
                Button { Task { await server.connect() } } label: {
                    if server.busy { ProgressView() } else { Text("Connect") }
                }
                .disabled(server.busy || server.host.isEmpty)
                if let failure = server.failure { Text(failure).font(.footnote).foregroundStyle(.red) }
            }
        } header: { Text("File server") } footer: {
            Text("With a server connected, Songs can import its audio files. The connection is always encrypted: FTPS with TLS, or SFTP over SSH. An SFTP server's key is remembered at the first login and a different one is refused. Turn on the untrusted certificate option for a server with a self-signed one.")
        }
    }
}
