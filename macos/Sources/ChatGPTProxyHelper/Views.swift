import SwiftUI

struct ContentView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(spacing: 0) {
            TitleBarView()
            ScrollView {
                MainContent()
            }
        }
        .background(Palette.window.ignoresSafeArea())
        .background(WindowConfigurator())
        .onChange(of: state.config) { _ in state.persistConfig() }
    }
}

/// 隐藏绿色缩放按钮：为标题栏单行布局腾出空间（关闭+最小化保留在原生位置）
struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            view.window?.standardWindowButton(.zoomButton)?.isHidden = true
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        nsView.window?.standardWindowButton(.zoomButton)?.isHidden = true
    }
}

/// 主内容区：独立成视图，便于离屏渲染 UI 预览（ImageRenderer 渲染 ScrollView 内容不可靠）
struct MainContent: View {
    var body: some View {
        VStack(spacing: 12) {
            HeroCardView()
            HStack(alignment: .top, spacing: 14) {
                VStack(spacing: 12) {
                    ProxyCardView()
                    OptionsCardView()
                }
                .frame(width: 452)
                DetectionCardView()
            }
            ActionRowView()
            BoundaryCardView()
            LogCardView()
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
    }
}

/// 工具边界说明：独立全宽信息条（仅代理主程序联网，更新需临时系统代理）
struct BoundaryCardView: View {
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 14))
                .foregroundStyle(Palette.blue)
                .padding(.top, 1)
            Text("工具边界：本工具仅代理 ChatGPT 主程序的联网（聊天、登录等）；应用内「检查更新」不走本代理，需要更新时请临时开启系统代理。")
                .font(.system(size: 12.5))
                .foregroundStyle(Palette.secondaryText)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.subtle, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Palette.hairline))
    }
}

// MARK: - 标题栏

struct TitleBarView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        // 单行标题栏：关闭+最小化按钮占 x=9~43；logo 中心 x=49+13=62，
        // 与下方代理状态图标同轴，且与红绿灯同一水平中心线（y=14）
        HStack(spacing: 10) {
            AppIconView(size: 26)
                .padding(.leading, 49)
            Text("ChatGPT 代理助手")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Palette.primaryText)
            Text("免系统代理 / 免 TUN")
                .font(.system(size: 11))
                .foregroundStyle(Palette.secondaryText)
                .padding(.horizontal, 9)
                .padding(.vertical, 3)
                .background(Palette.card, in: Capsule())
                .overlay(Capsule().stroke(Palette.hairline))
            Spacer()
            ThemePickerView()
        }
        .padding(.trailing, 20)
        .frame(height: 28)
        .padding(.bottom, 2)
    }
}

struct AppIconView: View {
    var size: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
            .fill(LinearGradient(colors: [Color(red: 0.45, green: 0.47, blue: 0.98),
                                          Color(red: 0.33, green: 0.34, blue: 0.93)],
                                 startPoint: .top, endPoint: .bottom))
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: size * 0.62, weight: .semibold))
                    .foregroundStyle(.white)
            )
    }
}

struct ThemePickerView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        HStack(spacing: 2) {
            ForEach(AppTheme.allCases) { theme in
                let selected = state.config.theme == theme.rawValue
                Button {
                    state.setTheme(theme)
                } label: {
                    Image(systemName: theme.icon)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(selected ? Color.white : Palette.secondaryText)
                        .frame(width: 30, height: 24)
                        .background {
                            if selected {
                                RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Palette.primary)
                            }
                        }
                }
                .buttonStyle(.plain)
                .help(theme.label)
            }
        }
        .padding(1)
        .background(Palette.subtle, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(Palette.hairline))
    }
}

// MARK: - 卡片容器

struct CardView<Content: View>: View {
    @Environment(\.colorScheme) private var scheme
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Palette.hairline))
            .shadow(color: .black.opacity(scheme == .dark ? 0.20 : 0.05), radius: 8, y: 2)
    }
}

func cardTitle(_ text: String) -> some View {
    Text(text)
        .font(.system(size: 15, weight: .semibold))
        .foregroundStyle(Palette.primaryText)
}

// MARK: - 状态 Hero

struct HeroCardView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        let hero = state.hero
        CardView {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(hero.solid ? hero.tint : hero.tint.opacity(0.13))
                        .frame(width: 56, height: 56)
                    Image(systemName: hero.symbol)
                        .font(.system(size: hero.solid ? 23 : 25, weight: .semibold))
                        .foregroundStyle(hero.solid ? Color.white : hero.tint)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(hero.title)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(Palette.primaryText)
                    Text(hero.desc)
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.secondaryText)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        ForEach(hero.chips, id: \.text) { chip in
                            HStack(spacing: 5) {
                                Circle()
                                    .fill(chip.ok ? Palette.green : Palette.tertiaryText)
                                    .frame(width: 6, height: 6)
                                Text(chip.text)
                                    .font(.system(size: 12))
                                    .foregroundStyle(Palette.secondaryText)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Palette.subtle, in: Capsule())
                        }
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }
}

// MARK: - 代理地址

struct ProxyCardView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        CardView {
            VStack(alignment: .leading, spacing: 12) {
                cardTitle("代理地址")
                HStack(alignment: .bottom, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        fieldLabel("主机")
                        TextField("127.0.0.1", text: $state.config.host)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 13))
                            .frame(maxWidth: .infinity)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        fieldLabel("端口")
                        TextField("7897", text: Binding(
                            get: { String(state.config.port) },
                            set: {
                                if let port = Int($0.filter(\.isNumber)), (1...65535).contains(port) {
                                    state.config.port = port
                                }
                            }
                        ))
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 13))
                        .frame(width: 84)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        fieldLabel("协议")
                        Picker("", selection: $state.config.scheme) {
                            ForEach(ProxyScheme.allCases) { scheme in
                                Text(scheme.label).tag(scheme)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(width: 138)
                    }
                }
                HStack(spacing: 10) {
                    Button {
                        Task { await state.testConnectivity() }
                    } label: {
                        HStack(spacing: 6) {
                            if state.testing {
                                ProgressView().controlSize(.small)
                            }
                            Text("测试连通性")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Palette.primaryText)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                    }
                    .buttonStyle(NeutralButtonStyle())
                    .disabled(state.testing)
                    .help("经本地代理向 chatgpt.com:443 发起一次真实请求")

                    if let ok = state.testOK, let text = state.testResult {
                        HStack(spacing: 5) {
                            Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundStyle(ok ? Palette.green : Palette.red)
                            Text(text)
                        }
                        .font(.system(size: 12.5))
                        .foregroundStyle(Palette.secondaryText)
                    } else {
                        Text("未测试")
                            .font(.system(size: 12.5))
                            .foregroundStyle(Palette.tertiaryText)
                    }
                    Spacer()
                }
            }
        }
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(Palette.secondaryText)
    }
}

// MARK: - 开启选项

struct OptionsCardView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        CardView {
            VStack(alignment: .leading, spacing: 11) {
                cardTitle("开启选项")
                Toggle(isOn: $state.config.createLauncher) {
                    Text("创建「ChatGPT（代理）」启动器到「应用程序」（原应用保持不动）")
                        .fixedSize(horizontal: false, vertical: true)
                }
                Toggle(isOn: $state.config.injectEnv) {
                    Text("启动时注入 HTTP(S)_PROXY 环境变量（覆盖非浏览器组件）")
                        .fixedSize(horizontal: false, vertical: true)
                }
                Toggle(isOn: $state.config.launchAfter) {
                    Text("开启后立即启动 ChatGPT")
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .font(.system(size: 13))
            .foregroundStyle(Palette.primaryText)
            .toggleStyle(.checkbox)
        }
    }
}

// MARK: - 环境检测

struct DetectionCardView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        CardView {
            VStack(alignment: .leading, spacing: 13) {
                HStack {
                    cardTitle("环境检测")
                    Spacer()
                    Button {
                        Task { await state.refresh(logMessage: "开始检测环境") }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Palette.secondaryText)
                            .frame(width: 26, height: 22)
                    }
                    .buttonStyle(NeutralButtonStyle())
                    .help("重新检测")
                }
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(state.detections) { item in
                        HStack(alignment: .firstTextBaseline, spacing: 9) {
                            Circle()
                                .fill(item.ok == true ? Palette.green : (item.ok == false ? Palette.red : Color.gray.opacity(0.45)))
                                .frame(width: 7, height: 7)
                            Text(item.label)
                                .font(.system(size: 13))
                                .foregroundStyle(Palette.secondaryText)
                                .frame(width: 96, alignment: .leading)
                            Text(item.value)
                                .font(.system(size: 13))
                                .foregroundStyle(Palette.primaryText)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                Rectangle().fill(Palette.hairline).frame(height: 1)
                Text("以上信息均在本机读取，仅用于本机代理配置")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.tertiaryText)
            }
        }
    }
}

// MARK: - 操作行

struct ActionRowView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        HStack(spacing: 12) {
            Button {
                Task { await state.enableAll() }
            } label: {
                Label("一键开启", systemImage: "power")
                    .font(.system(size: 14, weight: .semibold))
                    .padding(.horizontal, 22)
                    .padding(.vertical, 10)
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(state.busy)

            Button {
                Task { await state.launchChatGPT() }
            } label: {
                HStack(spacing: 6) {
                    if state.launching {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "play.fill")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    Text(state.launching ? "启动中…" : "启动 ChatGPT")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Palette.primaryText)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
            }
            .buttonStyle(NeutralButtonStyle())
            .disabled(state.launching)

            Button {
                Task { await state.restoreAll() }
            } label: {
                Label("一键还原", systemImage: "arrow.uturn.backward")
                    .font(.system(size: 14, weight: .semibold))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
            }
            .buttonStyle(DangerButtonStyle())
            .disabled(state.busy)

            Spacer()

            Text("当前状态：\(state.config.enabled ? "已开启" : "未开启")")
                .font(.system(size: 13))
                .foregroundStyle(Palette.secondaryText)
        }
    }
}

// MARK: - 运行日志

struct LogCardView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        CardView {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    cardTitle("运行日志")
                    Spacer()
                    Button {
                        state.copyLogs()
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Palette.secondaryText)
                            .frame(width: 26, height: 22)
                    }
                    .buttonStyle(NeutralButtonStyle())
                    .help("复制日志")
                }
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 3) {
                            ForEach(state.logs) { line in
                                HStack(alignment: .top, spacing: 8) {
                                    Text(line.time)
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundStyle(Palette.tertiaryText)
                                        .frame(width: 60, alignment: .leading)
                                        .lineLimit(1)
                                        .fixedSize(horizontal: true, vertical: false)
                                    Text(line.text)
                                        .font(.system(size: 11.5))
                                        .foregroundStyle(Palette.secondaryText)
                                        .textSelection(.enabled)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .id(line.id)
                            }
                        }
                        .padding(2)
                    }
                    .frame(height: 68)
                    .onChange(of: state.logs.count) { _ in
                        if let last = state.logs.last {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }
        }
    }
}
