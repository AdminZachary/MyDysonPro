import SwiftUI

/// On-device onboarding: email code + password → pick Zone → fetch LTK → Keychain.
/// The password is only sent to Dyson and never stored.
struct ZoneLoginView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var settings = ZoneSettings.shared
    @State private var email = ""
    @State private var country = Locale.current.region?.identifier ?? "CN"
    @State private var code = ""
    @State private var password = ""
    @State private var challenge: String?
    @State private var token: String?
    @State private var accountId: String?
    @State private var devices: [ZoneCloudDevice] = []
    @State private var busy = false
    @State private var message: String?

    private var cloud: ZoneCloud { ZoneCloud(host: settings.cloudHost, country: country) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("用你的 MyDyson 账号登录一次，取回 Zone 的蓝牙密钥并存进本机钥匙串。密码只发送给 Dyson，不会保存。这是非官方接口，Dyson 更新后可能失效。")
                        .font(.footnote)
                }
                Section("1. 邮箱") {
                    TextField("MyDyson 邮箱", text: $email).textContentType(.username).keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                    TextField("国家/地区代码", text: $country).textInputAutocapitalization(.characters)
                    TextField("服务器", text: $settings.cloudHost).textInputAutocapitalization(.never)
                    Text("默认 \(ZoneCloud.defaultHost)。中国区账号若失败，可尝试中国区服务器（地址未验证）。")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("发送验证码") { run { challenge = try await cloud.beginLogin(email: email) } }
                        .disabled(email.isEmpty || busy)
                }
                if challenge != nil {
                    Section("2. 验证码和密码") {
                        TextField("邮件验证码", text: $code).keyboardType(.numberPad)
                        SecureField("MyDyson 密码（不保存）", text: $password).textContentType(.password)
                        Button("登录并读取设备") {
                            run {
                                let r = try await cloud.completeLogin(email: email, password: password, challengeId: challenge!, code: code)
                                password = ""
                                token = r.token; accountId = r.accountId
                                let all = try await cloud.devices(token: r.token)
                                devices = all.filter { $0.looksLikeZone }.isEmpty ? all : all.filter { $0.looksLikeZone }
                            }
                        }.disabled(code.isEmpty || password.isEmpty || busy)
                    }
                }
                if !devices.isEmpty {
                    Section("3. 选择你的 Zone") {
                        ForEach(devices) { d in
                            Button("\(d.name ?? "设备") · \(d.model ?? d.type ?? "") · …\(String((d.serialNumber ?? "").suffix(4)))") {
                                run {
                                    guard let serial = d.serialNumber, let token, let accountId else { return }
                                    let ltk = try await cloud.ltk(serial: serial, token: token)
                                    try ZoneKeychain.save(ZoneCredentials(email: email, accountId: accountId, serial: serial, ltk: ltk))
                                    message = "已保存到钥匙串 ✓"
                                    ZoneManager.shared.bootstrap()
                                    dismiss()
                                }
                            }
                        }
                    }
                }
                if busy { ProgressView() }
                if let message { Text(message).font(.footnote) }
            }
            .navigationTitle("登录 Dyson")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } } }
        }
    }

    private func run(_ work: @escaping () async throws -> Void) {
        busy = true; message = nil
        Task {
            do { try await work() } catch { message = error.localizedDescription }
            busy = false
        }
    }
}
