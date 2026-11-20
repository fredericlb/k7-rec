// Settings as the design system's cards: the lyrics lead, the headset microphone, the file server, iCloud, About.
// One column on iPhone, two on iPad and the Mac (the file server alone on the right).
import SwiftUI

struct SettingsScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass
    private var metrics: Metrics { Metrics(sizeClass) }

    var body: some View {
        NavigationStack {
            ScrollView {
                if metrics.wide {
                    HStack(alignment: .top, spacing: K7Space.s24) {
                        VStack(spacing: K7Space.s24) { playing; recording; icloud; about }
                        VStack(spacing: K7Space.s24) { server }
                    }
                    .padding(.horizontal, metrics.margin).padding(.top, 8)
                } else {
                    VStack(spacing: K7Space.s24) { playing; recording; server; icloud; about }
                        .padding(.horizontal, metrics.margin).padding(.top, 8)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .screenBackground()
            .k7Header("Settings", subtitle: "K7 REC \(version)")
        }
    }

    private var version: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "" }

    private var playing: some View {
        let lead = model.prefs.lyricsLead
        return SettingsCard("Playing", note: "A tap on a timed lyric line starts the song this much before it.") {
            SettingRow("Lyrics lead") {
                StepperControl(
                    label: String(format: "%.1f s", lead), minusLabel: "Decrease lyrics lead", plusLabel: "Increase lyrics lead", valueInside: false,
                    minus: { model.prefs.lyricsLead = max(0, lead - 0.5) }, plus: { model.prefs.lyricsLead = min(5, lead + 0.5) })
            }
        }
    }

    private var recording: some View {
        @Bindable var prefs = model.prefs
        return SettingsCard("Recording", note: "Off: takes use the phone's microphone and earphones keep full-quality sound. On: a Bluetooth headset's own microphone, in narrowband sound.") {
            SettingRow("Use the headset microphone") { Toggle("Use the headset microphone", isOn: $prefs.headsetInput).labelsHidden() }
        }
    }

    @ViewBuilder private var icloud: some View {
        if let sync = model.sync {
            SettingsCard("iCloud", note: sync.inCloud
                ? "Songs and takes follow your iCloud account. A record written on another device can take a few minutes to arrive."
                : "iCloud is not available to the app: sign in to iCloud and turn on iCloud Drive, then relaunch.") {
                SettingRow("Files") { Value(sync.inCloud ? "iCloud Drive" : "This device only") }
                if let report = sync.report {
                    Separator()
                    SettingRow("Records") { Value(report.pending > 0 ? "\(report.records) (\(report.pending) still downloading)" : "\(report.records)") }
                }
                if let last = sync.lastRun {
                    Separator()
                    SettingRow("Last sync") { Value(last.formatted(date: .omitted, time: .standard)) }
                }
                Separator()
                ActionRow(title: "Sync now", busy: sync.running, enabled: !sync.running) { sync.schedule(after: 0) }
            }
        }
    }

    private var about: some View {
        SettingsCard("About") { SettingRow("Version") { Value(version) } }
    }

    private var server: some View {
        @Bindable var server = model.server
        return SettingsCard("File server", note: "With a server connected, Songs can import its audio files. The connection is always encrypted: FTPS with TLS, or SFTP over SSH. An SFTP server's key is remembered at the first login and a different one is refused. Turn on the untrusted certificate option for a server with a self-signed one.") {
            if server.connected {
                SettingRow("Protocol") { Value(server.kind.label) }
                Separator()
                SettingRow("Server") { Value(server.host) }
                Separator()
                SettingRow("Folder") { Value(server.folder) }
                if let key = server.hostKey {
                    Separator()
                    SettingRow("Host key") { Value(key).font(.footnote) }
                }
                Separator()
                ActionRow(title: "Disconnect", busy: false, enabled: true) { server.disconnect() }
            } else {
                SettingRow("Protocol") {
                    Menu {
                        Picker("Protocol", selection: $server.kind) { ForEach(RemoteProtocol.allCases) { Text($0.label).tag($0) } }
                    } label: {
                        HStack(spacing: 4) { Text(server.kind.label); Image(systemName: "chevron.up.chevron.down").font(.footnote) }
                            .foregroundStyle(k7.textSecondary).frame(minHeight: K7Size.touch)
                    }
                    .accessibilityLabel("Protocol, \(server.kind.label)")
                }
                Separator()
                FieldRow(label: "Address", text: $server.host, placeholder: "Server address", keyboard: .URL)
                Separator()
                FieldRow(label: "Port", text: $server.port, placeholder: "", keyboard: .numberPad)
                Separator()
                FieldRow(label: "User", text: $server.user, placeholder: "User name")
                Separator()
                FieldRow(label: "Password", text: $server.password, placeholder: "Password", secure: true)
                Separator()
                FieldRow(label: "Folder", text: $server.folder, placeholder: "/")
                if server.kind != .sftp {
                    Separator()
                    SettingRow("Accept an untrusted certificate") {
                        Toggle("Accept an untrusted certificate", isOn: $server.trustAnyCertificate).labelsHidden()
                    }
                }
                Separator()
                ActionRow(title: "Connect", busy: server.busy, enabled: !server.busy && !server.host.isEmpty) { Task { await server.connect() } }
                if let failure = server.failure {
                    Text(failure).font(.footnote).foregroundStyle(k7.statusError)
                        .padding(.horizontal, K7Space.s20).padding(.bottom, 12).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}
