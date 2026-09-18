// ChatGPT 代理助手 - 主窗口（加载 XAML、绑定事件、驱动检测与操作）
using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.IO;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Markup;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Shapes;
using System.Reflection;

namespace ChatGPTProxyManager
{
    internal enum HeroState { Idle, Ok, Warn, Error }

    internal class MainWindowController
    {
        private readonly Settings _settings;
        private readonly ObservableCollection<LogEntry> _logItems = new ObservableCollection<LogEntry>();
        private readonly Window _window;

        private TextBlock _heroTitle, _heroSubtitle, _heroBadge;
        private Ellipse _heroDisc, _heroHalo;
        private System.Windows.Shapes.Path _heroGlyph;
        private Ellipse _chipAppDot, _chipPortDot, _chipEnvDot;
        private TextBlock _chipAppText, _chipPortText, _chipEnvText;
        private TextBox _txtHost, _txtPort;
        private TextBlock _txtTestResult, _txtStatus, _txtActionHint;
        private Button _btnTest, _btnEnable, _btnLaunch, _btnRestore, _btnRefresh, _btnCopyLog, _btnClearLog, _btnMin, _btnClose;
        private CheckBox _chkShortcut, _chkEnv, _chkAutoLaunch;
        private StackPanel _detList;
        private ListBox _logList;
        private Grid _busyRing;
        private RotateTransform _busyRotate;
        private Border _fallbackBg, _rootBorder, _heroCard;
        private Grid _titleBar;

        private TextBlock _detApp, _detPort, _detSysProxy, _detTun, _detEnv, _detShortcut, _detRunning;
        private Ellipse _dotApp, _dotPort, _dotSysProxy, _dotTun, _dotEnv, _dotShortcut, _dotRunning;
        private bool _busy;
        private bool _backdropApplied;

        private ThemeMode _themeMode = ThemeMode.Light;
        private bool _isLight = true;
        private ResourceDictionary _themeDictionary;
        private ToggleButton _btnThemeLight, _btnThemeDark, _btnThemeSystem;
        private bool _suppressControlEvents;
        private DetectResult _lastDetect;
        private int _lastTestState;   // 0 未测试 / 1 可用 / 2 端口可达 / 3 失败

        private static readonly string[] GlyphOk = new string[] { "M5,11 L10,16 L19,5" };
        private static readonly string[] GlyphWarn = new string[] { "M11.5,4.5 L11.5,12.5 M11.5,16.4 L11.5,16.6" };
        private static readonly string[] GlyphError = new string[] { "M7,7 L15.5,15.5 M15.5,7 L7,15.5" };
        private static readonly string[] GlyphIdle = new string[] { "M6,12 L16.5,12" };

        public Window Window { get { return _window; } }

        public MainWindowController(Settings settings, string startupWarning)
        {
            _settings = settings;
            _themeMode = ThemeManager.Parse(settings.Theme);
            _window = LoadXaml();
            ApplyTheme();          // 先装主题字典，后面的 Resource() 才有值
            BindControls();
            WireEvents();
            ApplyBackdrop();
            LoadHistory();
            if (!string.IsNullOrEmpty(startupWarning))
                LogBus.Write("启动被阻止：" + startupWarning, LogKind.Warn);
            LogBus.Entry += OnLogEntry;
            _window.Closed += OnWindowClosed;
            _window.Loaded += OnWindowLoaded;
        }

        private Window LoadXaml()
        {
            string resourceName = "MainWindow.xaml";
            Stream stream = Assembly.GetExecutingAssembly().GetManifestResourceStream(resourceName);
            if (stream == null)
            {
                var names = Assembly.GetExecutingAssembly().GetManifestResourceNames();
                throw new InvalidOperationException("缺少界面资源 MainWindow.xaml，现有资源：" + string.Join(", ", names));
            }
            using (stream)
            {
                return (Window)XamlReader.Load(stream);
            }
        }

        private T Find<T>(string name) where T : class
        {
            return _window.FindName(name) as T;
        }

        private void BindControls()
        {
            _heroTitle = Find<TextBlock>("HeroTitle");
            _heroSubtitle = Find<TextBlock>("HeroSubtitle");
            _heroBadge = Find<TextBlock>("HeroBadge");
            _heroDisc = Find<Ellipse>("HeroDisc");
            _heroHalo = Find<Ellipse>("HeroHalo");
            _heroGlyph = Find<System.Windows.Shapes.Path>("HeroGlyph");
            _chipAppDot = Find<Ellipse>("ChipAppDot");
            _chipPortDot = Find<Ellipse>("ChipPortDot");
            _chipEnvDot = Find<Ellipse>("ChipEnvDot");
            _chipAppText = Find<TextBlock>("ChipAppText");
            _chipPortText = Find<TextBlock>("ChipPortText");
            _chipEnvText = Find<TextBlock>("ChipEnvText");
            _txtHost = Find<TextBox>("TxtHost");
            _txtPort = Find<TextBox>("TxtPort");
            _txtTestResult = Find<TextBlock>("TxtTestResult");
            _txtStatus = Find<TextBlock>("TxtStatus");
            _txtActionHint = Find<TextBlock>("TxtActionHint");
            _btnTest = Find<Button>("BtnTest");
            _btnEnable = Find<Button>("BtnEnable");
            _btnLaunch = Find<Button>("BtnLaunch");
            _btnRestore = Find<Button>("BtnRestore");
            _btnRefresh = Find<Button>("BtnRefresh");
            _btnCopyLog = Find<Button>("BtnCopyLog");
            _btnClearLog = Find<Button>("BtnClearLog");
            _btnMin = Find<Button>("BtnMin");
            _btnClose = Find<Button>("BtnClose");
            _chkShortcut = Find<CheckBox>("ChkShortcut");
            _chkEnv = Find<CheckBox>("ChkEnv");
            _chkAutoLaunch = Find<CheckBox>("ChkAutoLaunch");
            _detList = Find<StackPanel>("DetList");
            _logList = Find<ListBox>("LogList");
            _busyRing = Find<Grid>("BusyRing");
            _busyRotate = Find<RotateTransform>("BusyRotate");
            _fallbackBg = Find<Border>("FallbackBg");
            _rootBorder = Find<Border>("RootBorder");
            _heroCard = Find<Border>("HeroCard");
            _titleBar = Find<Grid>("TitleBar");
            _btnThemeLight = Find<ToggleButton>("BtnThemeLight");
            _btnThemeDark = Find<ToggleButton>("BtnThemeDark");
            _btnThemeSystem = Find<ToggleButton>("BtnThemeSystem");

            _txtHost.Text = _settings.ProxyHost;
            _txtPort.Text = _settings.ProxyPort.ToString();
            _chkShortcut.IsChecked = _settings.OptTakeOverShortcut;
            _chkEnv.IsChecked = _settings.OptSetEnvVars;
            _chkAutoLaunch.IsChecked = _settings.OptAutoLaunch;

            _logList.ItemsSource = _logItems;
            Find<TextBlock>("TxtVersion").Text = "v" + AppConstants.Version + "  ·  .NET 4.8";

            BuildDetRows();
        }

        private void BuildDetRows()
        {
            AddDetRow("ChatGPT 应用", out _dotApp, out _detApp);
            AddDetRow("代理端口", out _dotPort, out _detPort);
            AddDetRow("系统代理", out _dotSysProxy, out _detSysProxy);
            AddDetRow("TUN 模式", out _dotTun, out _detTun);
            AddDetRow("环境变量", out _dotEnv, out _detEnv);
            AddDetRow("快捷方式", out _dotShortcut, out _detShortcut);
            AddDetRow("运行状态", out _dotRunning, out _detRunning);
        }

        private void AddDetRow(string label, out Ellipse dot, out TextBlock value)
        {
            var grid = new Grid();
            grid.Margin = new Thickness(0, 0, 0, 15);
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(16) });
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(84) });
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });

            var dotEl = new Ellipse();
            dotEl.Width = 7;
            dotEl.Height = 7;
            dotEl.Fill = Resource("Neutral");
            dotEl.VerticalAlignment = VerticalAlignment.Center;
            Grid.SetColumn(dotEl, 0);
            grid.Children.Add(dotEl);

            var labelEl = new TextBlock();
            labelEl.Text = label;
            labelEl.FontSize = 12;
            labelEl.Foreground = Resource("TextMuted");
            labelEl.VerticalAlignment = VerticalAlignment.Center;
            Grid.SetColumn(labelEl, 1);
            grid.Children.Add(labelEl);

            var valueEl = new TextBlock();
            valueEl.Text = "—";
            valueEl.FontSize = 12;
            valueEl.Foreground = Resource("TextSecondary");
            valueEl.TextWrapping = TextWrapping.Wrap;
            valueEl.VerticalAlignment = VerticalAlignment.Center;
            Grid.SetColumn(valueEl, 2);
            grid.Children.Add(valueEl);

            _detList.Children.Add(grid);
            dot = dotEl;
            value = valueEl;
        }

        private Brush Resource(string key)
        {
            return (Brush)_window.FindResource(key);
        }

        private void WireEvents()
        {
            _btnMin.Click += delegate { _window.WindowState = WindowState.Minimized; };
            _btnClose.Click += delegate { _window.Close(); };
            _titleBar.MouseLeftButtonDown += OnTitleBarMouseDown;
            _btnRefresh.Click += OnRefreshClick;
            _btnTest.Click += OnTestClick;
            _btnEnable.Click += OnEnableClick;
            _btnLaunch.Click += OnLaunchClick;
            _btnRestore.Click += OnRestoreClick;
            _btnCopyLog.Click += OnCopyLogClick;
            _btnClearLog.Click += OnClearLogClick;
            _txtPort.PreviewTextInput += OnPortPreviewTextInput;
            _chkShortcut.Click += delegate { ReadSettingsFromUi(); };
            _chkEnv.Click += delegate { ReadSettingsFromUi(); };
            _chkAutoLaunch.Click += delegate { ReadSettingsFromUi(); };
            // ToggleButton/CheckBox 被辅助功能（automation）触发时只发 Checked/Unchecked，
            // 不发 Click，所以这里两种事件都接上，并用标志位避免回环
            _chkShortcut.Checked += OnOptionChanged;
            _chkShortcut.Unchecked += OnOptionChanged;
            _chkEnv.Checked += OnOptionChanged;
            _chkEnv.Unchecked += OnOptionChanged;
            _chkAutoLaunch.Checked += OnOptionChanged;
            _chkAutoLaunch.Unchecked += OnOptionChanged;
            _btnThemeLight.Checked += OnThemeSegmentToggled;
            _btnThemeLight.Unchecked += OnThemeSegmentToggled;
            _btnThemeDark.Checked += OnThemeSegmentToggled;
            _btnThemeDark.Unchecked += OnThemeSegmentToggled;
            _btnThemeSystem.Checked += OnThemeSegmentToggled;
            _btnThemeSystem.Unchecked += OnThemeSegmentToggled;
            try { Microsoft.Win32.SystemEvents.UserPreferenceChanged += OnUserPreferenceChanged; }
            catch { }
        }

        private void OnOptionChanged(object sender, RoutedEventArgs e)
        {
            if (_suppressControlEvents) return;
            ReadSettingsFromUi();
        }

        private void OnThemeSegmentToggled(object sender, RoutedEventArgs e)
        {
            if (_suppressControlEvents) return;
            if (sender == _btnThemeLight) SetThemeMode(ThemeMode.Light);
            else if (sender == _btnThemeDark) SetThemeMode(ThemeMode.Dark);
            else if (sender == _btnThemeSystem) SetThemeMode(ThemeMode.System);
        }

        // ================= 主题 =================
        private void OnUserPreferenceChanged(object sender, Microsoft.Win32.UserPreferenceChangedEventArgs e)
        {
            if (_themeMode != ThemeMode.System) return;
            if (ThemeManager.IsSystemLight() == _isLight) return;
            try { _window.Dispatcher.BeginInvoke(new Action(ApplyTheme)); }
            catch { }
        }

        private void SetThemeMode(ThemeMode mode)
        {
            _themeMode = mode;
            _settings.Theme = ThemeManager.ToSetting(mode);
            _settings.Save();
            ApplyTheme();
            LogBus.Write("主题已切换为「" + ThemeManager.Describe(mode) + "」", LogKind.Detail);
        }

        private ResourceDictionary LoadThemeDictionary(string resourceName)
        {
            Stream stream = Assembly.GetExecutingAssembly().GetManifestResourceStream(resourceName);
            if (stream == null) throw new InvalidOperationException("缺少主题资源 " + resourceName);
            using (stream)
            {
                return (ResourceDictionary)XamlReader.Load(stream);
            }
        }

        /// <summary>装载主题字典并刷新所有依赖主题的显示</summary>
        private void ApplyTheme()
        {
            bool light = ThemeManager.ResolveIsLight(_themeMode);
            ResourceDictionary dictionary = LoadThemeDictionary(light ? "ThemeLight.xaml" : "ThemeDark.xaml");

            var merged = _window.Resources.MergedDictionaries;
            if (_themeDictionary != null) merged.Remove(_themeDictionary);
            merged.Add(dictionary);
            _themeDictionary = dictionary;

            _isLight = light;
            UpdateWindowDarkMode();
            UpdateThemeButtons();
            RecolorLog();
            // 状态色是代码里取资源赋值的，重新套用一次即可跟随主题
            if (_lastDetect != null) ApplyDetect(_lastDetect);
            ApplyTestResultVisual();
        }

        private void UpdateThemeButtons()
        {
            if (_btnThemeLight == null) return;
            _suppressControlEvents = true;
            _btnThemeLight.IsChecked = _themeMode == ThemeMode.Light;
            _btnThemeDark.IsChecked = _themeMode == ThemeMode.Dark;
            _btnThemeSystem.IsChecked = _themeMode == ThemeMode.System;
            _suppressControlEvents = false;
        }

        private Brush ColorForKind(LogKind kind)
        {
            string key = "TextSecondary";
            if (kind == LogKind.Success) key = "Success";
            else if (kind == LogKind.Warn) key = "Warning";
            else if (kind == LogKind.Error) key = "Danger";
            else if (kind == LogKind.Detail) key = "TextMuted";
            return Resource(key);
        }

        private void RecolorLog()
        {
            if (_logList == null) return;
            foreach (LogEntry entry in _logItems) entry.Color = ColorForKind(entry.Kind);
        }

        private void ApplyTestResultVisual()
        {
            if (_txtTestResult == null) return;
            string key = "TextMuted";
            if (_lastTestState == 1) key = "Success";
            else if (_lastTestState == 2) key = "Warning";
            else if (_lastTestState == 3) key = "Danger";
            _txtTestResult.Foreground = Resource(key);
        }

        private void OnTitleBarMouseDown(object sender, MouseButtonEventArgs e)
        {
            if (e.ButtonState != MouseButtonState.Pressed) return;
            if (FindAncestor<Button>(e.OriginalSource as DependencyObject) != null) return;
            try { _window.DragMove(); }
            catch { }
        }

        private static T FindAncestor<T>(DependencyObject current) where T : DependencyObject
        {
            while (current != null)
            {
                T match = current as T;
                if (match != null) return match;
                current = VisualTreeHelper.GetParent(current);
            }
            return null;
        }

        private void OnPortPreviewTextInput(object sender, TextCompositionEventArgs e)
        {
            foreach (char c in e.Text)
            {
                if (!char.IsDigit(c)) { e.Handled = true; return; }
            }
        }

        private void OnWindowLoaded(object sender, RoutedEventArgs e)
        {
            ApplyBackdrop();
            PlayIntroAnimation();
            StartDetect();
        }

        private void OnWindowClosed(object sender, EventArgs e)
        {
            LogBus.Entry -= OnLogEntry;
            try { Microsoft.Win32.SystemEvents.UserPreferenceChanged -= OnUserPreferenceChanged; }
            catch { }
            try { ReadSettingsFromUi(); } catch { }
        }

        // ================= 视觉 =================
        private void PlayIntroAnimation()
        {
            _window.Opacity = 0;
            var fade = new DoubleAnimation(0, 1, TimeSpan.FromMilliseconds(280));
            fade.EasingFunction = new CubicEase { EasingMode = EasingMode.EaseOut };
            _window.BeginAnimation(UIElement.OpacityProperty, fade);

            var shift = new TranslateTransform(0, 12);
            _rootBorder.RenderTransform = shift;
            var move = new DoubleAnimation(12, 0, TimeSpan.FromMilliseconds(360));
            move.EasingFunction = new CubicEase { EasingMode = EasingMode.EaseOut };
            shift.BeginAnimation(TranslateTransform.YProperty, move);
        }

        private void ApplyBackdrop()
        {
            if (_backdropApplied) return;
            _backdropApplied = true;
            try
            {
                IntPtr hwnd = new WindowInteropHelper(_window).Handle;
                if (hwnd == IntPtr.Zero) { _backdropApplied = false; return; }
                UpdateWindowDarkMode(hwnd);                                      // 边框明暗跟随主题
                int corner = 2;
                Native.DwmSetWindowAttribute(hwnd, 33, ref corner, sizeof(int)); // 圆角

                // 把 DWM 边框扩展到整个客户区，Mica 材质才能从透明像素透出来
                var margins = new Native.MARGINS();
                margins.cxLeftWidth = -1;
                margins.cxRightWidth = -1;
                margins.cyTopHeight = -1;
                margins.cyBottomHeight = -1;
                int extendResult = Native.DwmExtendFrameIntoClientArea(hwnd, ref margins);

                int backdrop = 2;                                               // DWMWA_SYSTEMBACKDROP_TYPE = Mica
                int result = Native.DwmSetWindowAttribute(hwnd, 38, ref backdrop, sizeof(int));
                if (result == 0) _fallbackBg.Visibility = Visibility.Collapsed;
                else LogBus.Write("系统不支持 Mica 材质，改用自绘背景（不影响功能）", LogKind.Detail);
            }
            catch (Exception ex)
            {
                LogBus.Write("窗口材质设置失败：" + ex.Message, LogKind.Detail);
            }
        }

        private void UpdateWindowDarkMode()
        {
            try
            {
                IntPtr hwnd = new WindowInteropHelper(_window).Handle;
                if (hwnd != IntPtr.Zero) UpdateWindowDarkMode(hwnd);
            }
            catch { }
        }

        private void UpdateWindowDarkMode(IntPtr hwnd)
        {
            int dark = _isLight ? 0 : 1;
            Native.DwmSetWindowAttribute(hwnd, 20, ref dark, sizeof(int));   // DWMWA_USE_IMMERSIVE_DARK_MODE
        }

        private void SetHero(HeroState state, string title, string subtitle)
        {
            Brush badge;
            string glyph;
            switch (state)
            {
                case HeroState.Ok: badge = Resource("BadgeOk"); glyph = GlyphOk[0]; break;
                case HeroState.Warn: badge = Resource("BadgeWarn"); glyph = GlyphWarn[0]; break;
                case HeroState.Error: badge = Resource("BadgeError"); glyph = GlyphError[0]; break;
                default: badge = Resource("BadgeIdle"); glyph = GlyphIdle[0]; break;
            }
            _heroTitle.Text = title;
            _heroSubtitle.Text = subtitle;
            _heroGlyph.Data = Geometry.Parse(glyph);
            _heroDisc.Fill = badge;
            _heroHalo.Stroke = badge;
            _heroHalo.Opacity = 0.16;

            var pulse = new DoubleAnimation(0.06, 0.16, TimeSpan.FromMilliseconds(300));
            pulse.EasingFunction = new CubicEase { EasingMode = EasingMode.EaseOut };
            _heroHalo.BeginAnimation(UIElement.OpacityProperty, pulse);
        }

        private void SetChip(Ellipse dot, TextBlock text, bool ok, bool warn, string label)
        {
            Brush color = ok ? Resource("Success") : (warn ? Resource("Warning") : Resource("Neutral"));
            dot.Fill = color;
            text.Text = label;
        }

        private void SetBusy(bool busy, string status)
        {
            _busy = busy;
            _busyRing.Visibility = busy ? Visibility.Visible : Visibility.Collapsed;
            if (busy)
            {
                var spin = new DoubleAnimation(0, 360, TimeSpan.FromMilliseconds(900));
                spin.RepeatBehavior = RepeatBehavior.Forever;
                _busyRotate.BeginAnimation(RotateTransform.AngleProperty, spin);
            }
            else
            {
                _busyRotate.BeginAnimation(RotateTransform.AngleProperty, null);
            }
            _btnEnable.IsEnabled = !busy;
            _btnLaunch.IsEnabled = !busy;
            _btnRestore.IsEnabled = !busy;
            _btnTest.IsEnabled = !busy;
            _btnRefresh.IsEnabled = !busy;
            if (status != null) _txtStatus.Text = status;
        }

        private void Log(string text, LogKind kind)
        {
            LogBus.Write(text, kind);
        }

        private void OnLogEntry(LogEntry entry)
        {
            if (!_window.Dispatcher.CheckAccess())
            {
                _window.Dispatcher.BeginInvoke(new Action<LogEntry>(OnLogEntry), entry);
                return;
            }
            entry.Color = ColorForKind(entry.Kind);
            _logItems.Add(entry);
            while (_logItems.Count > 400) _logItems.RemoveAt(0);
            if (_logItems.Count > 0) _logList.ScrollIntoView(_logItems[_logItems.Count - 1]);
        }

        private void LoadHistory()
        {
            try
            {
                if (!File.Exists(Paths.LogFile)) return;
                string[] lines = File.ReadAllLines(Paths.LogFile, Encoding.UTF8);
                int start = Math.Max(0, lines.Length - 25);
                for (int i = start; i < lines.Length; i++)
                {
                    string line = lines[i];
                    if (string.IsNullOrEmpty(line)) continue;
                    string text = line;
                    string time = "";
                    int cut = line.IndexOf("  ", StringComparison.Ordinal);
                    if (cut > 0)
                    {
                        string stamp = line.Substring(0, cut);
                        time = stamp.Length >= 8 ? stamp.Substring(stamp.Length - 8) : stamp;
                        text = line.Substring(cut + 2);
                    }
                    var entry = new LogEntry();
                    entry.Time = time;
                    entry.Text = text;
                    entry.Kind = LogKind.Detail;
                    entry.Color = ColorForKind(LogKind.Detail);
                    _logItems.Add(entry);
                }
                if (_logItems.Count > 0) _logList.ScrollIntoView(_logItems[_logItems.Count - 1]);
            }
            catch { }
        }

        // ================= 设置 =================
        private void ReadSettingsFromUi()
        {
            string host = _txtHost.Text == null ? "" : _txtHost.Text.Trim();
            _settings.ProxyHost = host.Length == 0 ? "127.0.0.1" : host;
            int port;
            if (int.TryParse(_txtPort.Text == null ? "" : _txtPort.Text.Trim(), out port) && port > 0 && port < 65536)
                _settings.ProxyPort = port;
            _settings.OptTakeOverShortcut = _chkShortcut.IsChecked == true;
            _settings.OptSetEnvVars = _chkEnv.IsChecked == true;
            _settings.OptAutoLaunch = _chkAutoLaunch.IsChecked == true;
            _settings.Save();
        }

        // ================= 检测 =================
        private void StartDetect()
        {
            SetBusy(true, "正在检测环境…");
            Log("开始检测环境", LogKind.Info);
            var settings = _settings;
            Task.Factory.StartNew(delegate { return Detector.Run(settings); })
                .ContinueWith(delegate(Task<DetectResult> t)
                {
                    if (t.IsFaulted)
                    {
                        Log("检测失败：" + (t.Exception == null ? "未知错误" : t.Exception.GetBaseException().Message), LogKind.Error);
                        SetBusy(false, "检测失败");
                        return;
                    }
                    ApplyDetect(t.Result);
                    SetBusy(false, "检测完成");
                }, TaskScheduler.FromCurrentSynchronizationContext());
        }

        private void ApplyDetect(DetectResult d)
        {
            _lastDetect = d;
            string proxyDesc = _settings.Endpoint;

            // —— 应用
            if (d.App == null)
            {
                _dotApp.Fill = Resource("Danger");
                _detApp.Text = "未找到桌面版";
                _detApp.ToolTip = "未检测到 MSIX 打包安装或常见路径下的 ChatGPT.exe";
            }
            else
            {
                string kind = d.App.IsPackaged ? "MSIX 打包" : "独立安装";
                _dotApp.Fill = Resource("Success");
                _detApp.Text = d.App.VersionText + " · " + kind;
                _detApp.ToolTip = d.App.InstallPath;
            }

            // —— 端口
            if (d.PortListening)
            {
                _dotPort.Fill = Resource("Success");
                _detPort.Text = d.PortOwnerName == null
                    ? proxyDesc + " 监听中"
                    : proxyDesc + " · " + d.PortOwnerName + (d.PortOwnerPid > 0 ? " (PID " + d.PortOwnerPid + ")" : "");
            }
            else
            {
                _dotPort.Fill = Resource("Danger");
                _detPort.Text = proxyDesc + " 未监听";
            }

            // —— 系统代理 / TUN
            if (d.SystemProxyEnabled)
            {
                _dotSysProxy.Fill = Resource("Warning");
                _detSysProxy.Text = "已开启" + (string.IsNullOrEmpty(d.SystemProxyServer) ? "" : "：" + d.SystemProxyServer);
            }
            else
            {
                _dotSysProxy.Fill = Resource("Success");
                _detSysProxy.Text = d.PacConfigured ? "已关闭（存在 PAC 脚本）" : "已关闭（无需开启）";
            }
            if (d.TunAdapters.Count > 0)
            {
                _dotTun.Fill = Resource("Warning");
                _detTun.Text = "已启用：" + string.Join("、", d.TunAdapters.ToArray());
            }
            else
            {
                _dotTun.Fill = Resource("Success");
                _detTun.Text = "未启用（无需开启）";
            }

            // —— 环境变量
            if (d.EnvMatches)
            {
                _dotEnv.Fill = Resource("Success");
                _detEnv.Text = d.EnvProxyUrl;
            }
            else if (!string.IsNullOrEmpty(d.EnvProxyUrl))
            {
                _dotEnv.Fill = Resource("Warning");
                _detEnv.Text = d.EnvProxyUrl + "（与当前设置不一致）";
            }
            else
            {
                _dotEnv.Fill = Resource("Neutral");
                _detEnv.Text = "未设置";
            }

            // —— 快捷方式
            int lnkCount = (d.ManagedDesktopLnk ? 1 : 0) + (d.ManagedStartMenuLnk ? 1 : 0);
            if (lnkCount == 2)
            {
                _dotShortcut.Fill = Resource("Success");
                _detShortcut.Text = "已创建（桌面 + 开始菜单）";
            }
            else if (lnkCount == 1)
            {
                _dotShortcut.Fill = Resource("Warning");
                _detShortcut.Text = "部分创建（缺少" + (d.ManagedDesktopLnk ? "开始菜单" : "桌面") + "）";
            }
            else
            {
                _dotShortcut.Fill = Resource("Neutral");
                _detShortcut.Text = "未创建";
            }
            if (d.DesktopTakenOver)
                _detShortcut.Text += " · 桌面 ChatGPT 已接管";
            else if (d.DesktopLnkTarget != null && d.DesktopLnkTarget.Length > 0)
                _detShortcut.Text += " · 桌面 ChatGPT 指向其它程序";

            // —— 运行状态
            if (!d.AppRunning)
            {
                _dotRunning.Fill = Resource("Neutral");
                _detRunning.Text = "未运行";
            }
            else if (d.AppRunningWithProxy)
            {
                _dotRunning.Fill = Resource("Success");
                _detRunning.Text = "运行中 · 已通过代理";
            }
            else
            {
                _dotRunning.Fill = Resource("Warning");
                _detRunning.Text = "运行中 · 未走代理";
            }

            // —— 顶部状态
            bool configured = d.EnvMatches && lnkCount > 0;
            SetChip(_chipAppDot, _chipAppText, d.App != null, false, d.App != null ? "ChatGPT 已安装" : "未找到 ChatGPT");
            SetChip(_chipPortDot, _chipPortText, d.PortListening, false, d.PortListening ? "代理端口正常" : "代理端口未监听");
            SetChip(_chipEnvDot, _chipEnvText, configured, true, configured ? "启动配置完成" : "启动配置未完成");

            if (d.App == null)
            {
                SetHero(HeroState.Error, "未找到 ChatGPT 桌面版",
                    "请在 Microsoft Store 安装 ChatGPT 桌面应用后点击「重新检测」。");
                _txtActionHint.Text = "缺少应用";
            }
            else if (!d.PortListening)
            {
                SetHero(HeroState.Error, "代理端口未监听",
                    "无法连接 " + proxyDesc + "，请先启动代理客户端（如 Clash Verge），或修改为其它代理地址后重新检测。");
                _txtActionHint.Text = "请先启动代理客户端";
            }
            else if (configured)
            {
                SetHero(HeroState.Ok, "代理已就绪",
                    "双击桌面或开始菜单中的「ChatGPT」即可启动，流量经 " + _settings.ProxyUrl +
                    " 转发，无需再开启系统代理或 TUN 模式。");
                _txtActionHint.Text = "当前状态：已开启";
            }
            else if (d.EnvMatches || lnkCount > 0 || d.DesktopTakenOver)
            {
                SetHero(HeroState.Warn, "配置不完整",
                    "部分设置缺失，点击「一键开启」即可补齐。");
                _txtActionHint.Text = "推荐操作：一键开启";
            }
            else
            {
                SetHero(HeroState.Idle, "尚未开启",
                    "点击「一键开启」后，ChatGPT 将通过 " + _settings.ProxyUrl + " 启动，无需系统代理或 TUN。");
                _txtActionHint.Text = "推荐操作：一键开启";
            }

            _heroBadge.Text = "";
        }

        // ================= 操作 =================
        private void OnRefreshClick(object sender, RoutedEventArgs e)
        {
            if (_busy) return;
            ReadSettingsFromUi();
            StartDetect();
        }

        private async void OnTestClick(object sender, RoutedEventArgs e)
        {
            if (_busy) return;
            ReadSettingsFromUi();
            SetBusy(true, "正在测试代理连通性…");
            _txtTestResult.Text = "测试中…";
            _txtTestResult.Foreground = Resource("TextMuted");
            Log("测试代理 " + _settings.Endpoint + " …", LogKind.Info);

            string host = _settings.ProxyHost;
            int port = _settings.ProxyPort;
            var task = Task.Factory.StartNew(delegate { return ProxyTester.Test(host, port); });
            ProxyTestResult result = await task;

            if (result.ConnectOk)
            {
                _lastTestState = 1;
                _txtTestResult.Text = "可用 · " + result.LatencyMs + " ms";
                Log("代理测试通过：" + result.Detail + "（" + result.LatencyMs + " ms）", LogKind.Success);
            }
            else if (result.TcpOk)
            {
                _lastTestState = 2;
                _txtTestResult.Text = "端口可达，但代理未响应";
                Log("代理测试警告：" + result.Detail, LogKind.Warn);
            }
            else
            {
                _lastTestState = 3;
                _txtTestResult.Text = "不可用";
                Log("代理测试失败：" + result.Detail, LogKind.Error);
            }
            ApplyTestResultVisual();
            SetBusy(false, "测试完成");
        }

        private async void OnEnableClick(object sender, RoutedEventArgs e)
        {
            if (_busy) return;
            ReadSettingsFromUi();
            SetBusy(true, "正在开启…");
            Log("=== 一键开启 ===", LogKind.Info);

            var settings = _settings;
            EnableOutcome outcome = await Task.Factory.StartNew(delegate { return Operations.Enable(settings); });

            DetectResult detect = await Task.Factory.StartNew(delegate { return Detector.Run(settings); });
            ApplyDetect(detect);
            SetBusy(false, "已开启 · 代理 " + settings.Endpoint);
        }

        private async void OnLaunchClick(object sender, RoutedEventArgs e)
        {
            if (_busy) return;
            ReadSettingsFromUi();
            SetBusy(true, "正在启动 ChatGPT…");
            var settings = _settings;
            string error = await Task.Factory.StartNew(delegate
            {
                try { Operations.LaunchNow(settings, true); return null; }
                catch (Exception ex) { return ex.Message; }
            });
            if (error != null)
            {
                Log("启动失败：" + error, LogKind.Error);
                MessageBox.Show(_window, error, AppConstants.ProductName, MessageBoxButton.OK, MessageBoxImage.Warning);
                SetBusy(false, "启动失败");
            }
            else
            {
                SetBusy(false, "已启动");
                DetectResult detect = await Task.Factory.StartNew(delegate { return Detector.Run(settings); });
                ApplyDetect(detect);
            }
        }

        private async void OnRestoreClick(object sender, RoutedEventArgs e)
        {
            if (_busy) return;
            var confirm = MessageBox.Show(_window,
                "将移除环境变量、删除本程序创建的快捷方式，并恢复桌面原始「ChatGPT」快捷方式。\n\n是否继续？",
                AppConstants.ProductName, MessageBoxButton.YesNo, MessageBoxImage.Question);
            if (confirm != MessageBoxResult.Yes) return;

            bool running = System.Diagnostics.Process.GetProcessesByName("ChatGPT").Length > 0;
            bool closeApp = false;
            if (running)
            {
                var ask = MessageBox.Show(_window, "检测到 ChatGPT 正在运行，是否同时关闭它？",
                    AppConstants.ProductName, MessageBoxButton.YesNo, MessageBoxImage.Question);
                closeApp = ask == MessageBoxResult.Yes;
            }

            SetBusy(true, "正在还原…");
            Log("=== 一键还原 ===", LogKind.Info);
            var settings = _settings;
            await Task.Factory.StartNew(delegate { Operations.Restore(settings, closeApp); });

            DetectResult detect = await Task.Factory.StartNew(delegate { return Detector.Run(settings); });
            ApplyDetect(detect);
            SetBusy(false, "已还原");
        }

        private void OnCopyLogClick(object sender, RoutedEventArgs e)
        {
            var sb = new StringBuilder();
            foreach (LogEntry entry in _logItems) sb.AppendLine(entry.Time + "  " + entry.Text);
            try
            {
                Clipboard.SetText(sb.ToString());
                _txtStatus.Text = "日志已复制到剪贴板";
            }
            catch { _txtStatus.Text = "复制失败"; }
        }

        private void OnClearLogClick(object sender, RoutedEventArgs e)
        {
            _logItems.Clear();
            Log("日志已清空", LogKind.Detail);
        }
    }
}
