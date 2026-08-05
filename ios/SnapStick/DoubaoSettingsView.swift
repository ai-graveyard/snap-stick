//
//  DoubaoSettingsView.swift
//  SnapStick
//
//  用户自带火山方舟 / 豆包 Key。App 不提供统一后端，也不内置开发者 Key。
//

import SwiftUI

struct DoubaoSettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    @State private var showAPIKey = false
    @State private var testPhase: TestPhase = .idle
    @State private var testTask: Task<Void, Never>?
    /// 本次测试是否由「开启 AI 抠图」触发（通过则顺势打开开关，失败则弹窗）
    @State private var enabling = false
    @State private var enableFailure: EnableFailure?

    /// 连通性测试的状态机。失败时 reason 是中文文案 key（走本地化表），detail 原样展示。
    private enum TestPhase: Equatable {
        case idle
        case running
        case success(String)
        case failure(reason: String, detail: String?)
    }

    /// 开启 AI 抠图失败的弹窗内容。reason 是文案 key，detail（服务器原话）原样展示。
    private struct EnableFailure: Identifiable {
        let id = UUID()
        let reason: String
        let detail: String?
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        if showAPIKey {
                            TextField("请输入火山方舟 API Key", text: $settings.doubaoAPIKey)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        } else {
                            SecureField("请输入火山方舟 API Key", text: $settings.doubaoAPIKey)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        }
                        Button {
                            showAPIKey.toggle()
                        } label: {
                            Image(systemName: showAPIKey ? "eye.slash" : "eye")
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(Palette.klein)
                        .accessibilityLabel(Text(showAPIKey ? "隐藏 API Key" : "显示 API Key"))
                    }
                } header: {
                    Text("API Key")
                } footer: {
                    Text("API Key 只保存在本机钥匙串。识别时会从这台设备直接请求火山方舟，不经过拍立贴统一后端。")
                }

                Section {
                    TextField("例如 doubao-seed-2-0-mini-…", text: $settings.doubaoModelID)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("对话模型 ID")
                } footer: {
                    Text("连接测试用它发一句「hi」，验证 API Key 与接口连通性。")
                }

                Section {
                    TextField("例如 doubao-seedream-5-0-…", text: $settings.doubaoImageModelID)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("生成模型 ID")
                } footer: {
                    Text("AI 卡通贴纸用它把照片生成冰箱贴风格的卡片，需要你的火山方舟账号已开通对应模型。")
                }

                Section {
                    TextField("接口地址", text: $settings.doubaoBaseURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    Button("恢复默认接口地址") {
                        settings.doubaoBaseURL = AppSettings.defaultDoubaoBaseURL
                    }
                } header: {
                    Text("高级")
                } footer: {
                    Text("通常不用修改。默认使用火山方舟北京区 API 根地址，调用时会自动拼接对话与生图端点。")
                }

                Section {
                    Label(settings.doubaoConfigured ? "已配置" : "未配置完整",
                          systemImage: settings.doubaoConfigured ? "checkmark.circle.fill" : "exclamationmark.circle")
                        .foregroundColor(settings.doubaoConfigured ? .green : .secondary)
                }

                Section {
                    Toggle(isOn: aiCartoonBinding) {
                        HStack(spacing: 8) {
                            Text("AI 卡通贴纸")
                            if enabling && testPhase == .running {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(testPhase == .running)
                } footer: {
                    Text("开启后，拍照会先请生成模型把照片变成冰箱贴风格的卡通贴纸卡片，再在本机抠出主体做成贴纸；生成失败自动回退本地抠图。开启前会自动进行一次连接测试，修改上方配置会自动关闭开关。")
                }

                Section {
                    Button {
                        runTest()
                    } label: {
                        HStack {
                            Text("测试连接")
                            Spacer()
                            if testPhase == .running {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(!settings.doubaoConfigured || testPhase == .running)

                    switch testPhase {
                    case .success(let reply):
                        testResultRow(icon: "checkmark.circle.fill", tint: .green,
                                      title: "连接成功", reason: nil, detail: reply)
                    case .failure(let reason, let detail):
                        testResultRow(icon: "xmark.circle.fill", tint: .red,
                                      title: "连接失败", reason: reason, detail: detail)
                    case .idle, .running:
                        EmptyView()
                    }
                } header: {
                    Text("连接测试")
                } footer: {
                    Text(settings.doubaoConfigured
                         ? "向豆包发送一句「hi」，验证 API Key、模型与接口地址是否可用。"
                         : "请先填写 API Key 和模型 ID。")
                }
            }
            .onChange(of: settings.doubaoAPIKey) { old, new in configChanged(old, new) }
            .onChange(of: settings.doubaoModelID) { old, new in configChanged(old, new) }
            .onChange(of: settings.doubaoImageModelID) { old, new in configChanged(old, new) }
            .onChange(of: settings.doubaoBaseURL) { old, new in configChanged(old, new) }
            .alert("AI 配置有问题",
                   isPresented: Binding(get: { enableFailure != nil },
                                        set: { if !$0 { enableFailure = nil } }),
                   presenting: enableFailure) { _ in
                Button("知道了", role: .cancel) {}
            } message: { failure in
                enableFailureMessage(failure)
            }
            .navigationTitle("豆包 API")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        normalize()
                        dismiss()
                    }
                }
            }
            .onDisappear {
                testTask?.cancel()
                normalize()
            }
        }
    }

    private func testResultRow(icon: String, tint: Color, title: LocalizedStringKey,
                               reason: String?, detail: String?) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                if let reason {
                    Text(LocalizedStringKey(reason))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if let detail, !detail.isEmpty {
                    Text(verbatim: detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        } icon: {
            Image(systemName: icon)
                .foregroundStyle(tint)
        }
    }

    /// AI 卡通贴纸开关：打开必须先过连通性测试（测试通过才真正落到 settings），关闭随时可以。
    private var aiCartoonBinding: Binding<Bool> {
        Binding(
            get: { settings.doubaoAICartoonEnabled },
            set: { on in
                if on {
                    requestEnableAICartoon()
                } else {
                    settings.doubaoAICartoonEnabled = false
                }
            }
        )
    }

    private func requestEnableAICartoon() {
        normalize()
        guard settings.doubaoConfigured else {
            enableFailure = EnableFailure(reason: "请先填写 API Key 和模型 ID。", detail: nil)
            return
        }
        // 本次会话里刚测过且配置没改过（改动会 resetTest），直接开
        if case .success = testPhase {
            settings.doubaoAICartoonEnabled = true
            return
        }
        runTest(enableOnSuccess: true)
    }

    private func enableFailureMessage(_ failure: EnableFailure) -> Text {
        let reason = Text(LocalizedStringKey(failure.reason))
        let hint = Text("请检查 API Key、模型与接口地址后重试。")
        if let detail = failure.detail, !detail.isEmpty {
            return Text("\(reason)\n\(Text(verbatim: detail))\n\(hint)")
        }
        return Text("\(reason)\n\(hint)")
    }

    private func runTest(enableOnSuccess: Bool = false) {
        normalize()
        guard settings.doubaoConfigured else { return }
        testPhase = .running
        enabling = enableOnSuccess
        testTask = Task {
            defer { enabling = false }
            do {
                let reply = try await DoubaoAPI.sayHi(apiKey: settings.doubaoAPIKey,
                                                      modelID: settings.doubaoModelID,
                                                      baseURL: settings.doubaoBaseURL)
                testPhase = .success(reply)
                if enableOnSuccess { settings.doubaoAICartoonEnabled = true }
            } catch is CancellationError {
                return
            } catch let error as DoubaoAPI.APIError {
                let reason = Self.failureReason(for: error)
                let detail = Self.failureDetail(for: error)
                testPhase = .failure(reason: reason, detail: detail)
                if enableOnSuccess { enableFailure = EnableFailure(reason: reason, detail: detail) }
            } catch {
                testPhase = .failure(reason: "网络请求失败", detail: error.localizedDescription)
                if enableOnSuccess {
                    enableFailure = EnableFailure(reason: "网络请求失败",
                                                  detail: error.localizedDescription)
                }
            }
        }
    }

    private func resetTest() {
        testTask?.cancel()
        testPhase = .idle
    }

    /// 配置一变，旧的测试结果和「测试通过才开」的 AI 卡通贴纸开关都作废。
    /// 按去掉首尾空白后的语义值比较：normalize() 只做 trim，不应误伤刚发起的开启测试。
    private func configChanged(_ old: String, _ new: String) {
        let ws = CharacterSet.whitespacesAndNewlines
        guard old.trimmingCharacters(in: ws) != new.trimmingCharacters(in: ws) else { return }
        resetTest()
        settings.doubaoAICartoonEnabled = false
    }

    private static func failureReason(for error: DoubaoAPI.APIError) -> String {
        switch error {
        case .badURL: "接口地址无效"
        case .http: "服务器返回错误"
        case .badResponse: "返回内容无法解析"
        }
    }

    private static func failureDetail(for error: DoubaoAPI.APIError) -> String? {
        guard case .http(let code, let message) = error else { return nil }
        if let message, !message.isEmpty {
            return "HTTP \(code) · \(message)"
        }
        return "HTTP \(code)"
    }

    private func normalize() {
        settings.doubaoAPIKey = settings.doubaoAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        settings.doubaoModelID = settings.doubaoModelID.trimmingCharacters(in: .whitespacesAndNewlines)
        settings.doubaoImageModelID = settings.doubaoImageModelID.trimmingCharacters(in: .whitespacesAndNewlines)
        settings.doubaoBaseURL = settings.doubaoBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
