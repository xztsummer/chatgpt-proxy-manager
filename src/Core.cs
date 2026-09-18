// ChatGPT 代理助手 - 核心逻辑（检测 / 开启 / 还原 / 代理测试 / 启动）
// 目标框架：.NET Framework 4.8（Windows 10/11 自带），C# 5 语法
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Management;
using System.Net.Sockets;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using System.Windows.Media;
using Microsoft.Win32;

namespace ChatGPTProxyManager
{
    internal static class AppConstants
    {
        public const string ProductName = "ChatGPT 代理助手";
        public const string Version = "1.0";
        public const string ManagedShortcutName = "ChatGPT（本地代理）.lnk";
        public const string AppShortcutName = "ChatGPT.lnk";
        public const string PackagePrefix = "OpenAI.Codex_";
        public const string LegacyDirName = "ChatGPTProxy";
    }

    internal static class Paths
    {
        public static string DataDir
        {
            get
            {
                return Path.Combine(
                    Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                    "ChatGPTProxyManager");
            }
        }
        public static string LogFile { get { return Path.Combine(DataDir, "manager.log"); } }
        public static string SettingsFile { get { return Path.Combine(DataDir, "settings.ini"); } }
        public static string BackupDir { get { return Path.Combine(DataDir, "original-shortcut"); } }
        public static string ShortcutBackup { get { return Path.Combine(BackupDir, AppConstants.AppShortcutName); } }
        public static string LegacyBackup
        {
            get
            {
                return Path.Combine(
                    Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                    AppConstants.LegacyDirName, "desktop-original-shortcut", AppConstants.AppShortcutName);
            }
        }
        public static string ExePath
        {
            get
            {
                try { return Assembly.GetEntryAssembly().Location; }
                catch { return Process.GetCurrentProcess().MainModule.FileName; }
            }
        }
        public static string Desktop { get { return Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory); } }
        public static string StartMenu { get { return Environment.GetFolderPath(Environment.SpecialFolder.Programs); } }
        public static string DesktopAppLnk { get { return Path.Combine(Desktop, AppConstants.AppShortcutName); } }
        public static string DesktopManagedLnk { get { return Path.Combine(Desktop, AppConstants.ManagedShortcutName); } }
        public static string StartMenuManagedLnk { get { return Path.Combine(StartMenu, AppConstants.ManagedShortcutName); } }
    }

    // 注意：WPF 数据绑定只认属性，不认公开字段
    public class LogEntry : System.ComponentModel.INotifyPropertyChanged
    {
        private string _time;
        private string _text;
        private Brush _color;
        private LogKind _kind;

        public event System.ComponentModel.PropertyChangedEventHandler PropertyChanged;

        public string Time { get { return _time; } set { _time = value; } }
        public string Text { get { return _text; } set { _text = value; } }
        public LogKind Kind { get { return _kind; } set { _kind = value; } }

        // 主题切换时需要重新着色，所以要能通知界面
        public Brush Color
        {
            get { return _color; }
            set
            {
                _color = value;
                System.ComponentModel.PropertyChangedEventHandler handler = PropertyChanged;
                if (handler != null) handler(this, new System.ComponentModel.PropertyChangedEventArgs("Color"));
            }
        }
    }

    public enum LogKind { Info, Success, Warn, Error, Detail }

    internal static class LogBus
    {
        public static event Action<LogEntry> Entry;

        public static void Write(string text, LogKind kind)
        {
            var entry = new LogEntry();
            entry.Time = DateTime.Now.ToString("HH:mm:ss");
            entry.Text = text;
            entry.Kind = kind;
            var handler = Entry;
            if (handler != null) handler(entry);
            AppendFile(entry);
        }

        private static void AppendFile(LogEntry entry)
        {
            try
            {
                Directory.CreateDirectory(Paths.DataDir);
                string line = DateTime.Now.ToString("yyyy-MM-dd ") + entry.Time + "  " + entry.Text + Environment.NewLine;
                File.AppendAllText(Paths.LogFile, line, Encoding.UTF8);
            }
            catch { }
        }
    }

    internal class Settings
    {
        public string ProxyHost = "127.0.0.1";
        public int ProxyPort = 7897;
        public bool OptTakeOverShortcut = true;
        public bool OptSetEnvVars = true;
        public bool OptAutoLaunch = true;
        public string Theme = "light";    // light / dark / system

        public string Endpoint { get { return ProxyHost + ":" + ProxyPort.ToString(); } }
        public string ProxyUrl { get { return "http://" + ProxyHost + ":" + ProxyPort.ToString(); } }

        public static Settings Load()
        {
            var s = new Settings();
            try
            {
                if (File.Exists(Paths.SettingsFile))
                {
                    foreach (string raw in File.ReadAllLines(Paths.SettingsFile, Encoding.UTF8))
                    {
                        string line = raw.Trim();
                        if (line.Length == 0 || line.StartsWith("#")) continue;
                        int i = line.IndexOf('=');
                        if (i <= 0) continue;
                        string k = line.Substring(0, i).Trim();
                        string v = line.Substring(i + 1).Trim();
                        if (k == "proxyHost" && v.Length > 0) s.ProxyHost = v;
                        else if (k == "proxyPort")
                        {
                            int p;
                            if (int.TryParse(v, out p) && p > 0 && p < 65536) s.ProxyPort = p;
                        }
                        else if (k == "optTakeOverShortcut") s.OptTakeOverShortcut = v == "1";
                        else if (k == "optSetEnvVars") s.OptSetEnvVars = v == "1";
                        else if (k == "optAutoLaunch") s.OptAutoLaunch = v == "1";
                        else if (k == "theme" && v.Length > 0) s.Theme = v;
                    }
                }
            }
            catch { }
            return s;
        }

        public void Save()
        {
            try
            {
                Directory.CreateDirectory(Paths.DataDir);
                var sb = new StringBuilder();
                sb.AppendLine("# ChatGPT 代理助手设置");
                sb.AppendLine("proxyHost=" + ProxyHost);
                sb.AppendLine("proxyPort=" + ProxyPort.ToString());
                sb.AppendLine("optTakeOverShortcut=" + (OptTakeOverShortcut ? "1" : "0"));
                sb.AppendLine("optSetEnvVars=" + (OptSetEnvVars ? "1" : "0"));
                sb.AppendLine("optAutoLaunch=" + (OptAutoLaunch ? "1" : "0"));
                sb.AppendLine("theme=" + Theme);
                File.WriteAllText(Paths.SettingsFile, sb.ToString(), Encoding.UTF8);
            }
            catch { }
        }
    }

    internal enum ThemeMode { Light, Dark, System }

    internal static class ThemeManager
    {
        public static ThemeMode Parse(string value)
        {
            if (string.Equals(value, "dark", StringComparison.OrdinalIgnoreCase)) return ThemeMode.Dark;
            if (string.Equals(value, "system", StringComparison.OrdinalIgnoreCase)) return ThemeMode.System;
            return ThemeMode.Light;
        }

        public static string ToSetting(ThemeMode mode)
        {
            if (mode == ThemeMode.Dark) return "dark";
            if (mode == ThemeMode.System) return "system";
            return "light";
        }

        public static string Describe(ThemeMode mode)
        {
            if (mode == ThemeMode.Dark) return "深色";
            if (mode == ThemeMode.System) return "跟随系统";
            return "浅色";
        }

        /// <summary>Windows 应用主题：AppsUseLightTheme = 1 表示浅色</summary>
        public static bool IsSystemLight()
        {
            try
            {
                using (RegistryKey key = Registry.CurrentUser.OpenSubKey(
                    @"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize"))
                {
                    if (key != null)
                    {
                        object value = key.GetValue("AppsUseLightTheme");
                        if (value != null) return Convert.ToInt32(value) != 0;
                    }
                }
            }
            catch { }
            return true;
        }

        public static bool ResolveIsLight(ThemeMode mode)
        {
            if (mode == ThemeMode.Light) return true;
            if (mode == ThemeMode.Dark) return false;
            return IsSystemLight();
        }
    }

    internal static class Native
    {
        [DllImport("user32.dll", CharSet = CharSet.Auto, SetLastError = true)]
        public static extern IntPtr SendMessageTimeout(IntPtr hWnd, uint msg, IntPtr wParam, string lParam,
            uint flags, uint timeout, out IntPtr result);

        [DllImport("dwmapi.dll")]
        public static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int value, int size);

        [StructLayout(LayoutKind.Sequential)]
        public struct MARGINS
        {
            public int cxLeftWidth;
            public int cxRightWidth;
            public int cyTopHeight;
            public int cyBottomHeight;
        }

        [DllImport("dwmapi.dll")]
        public static extern int DwmExtendFrameIntoClientArea(IntPtr hwnd, ref MARGINS margins);

        [DllImport("user32.dll")]
        public static extern bool ShowWindow(IntPtr hWnd, int cmdShow);

        [DllImport("user32.dll")]
        public static extern bool SetForegroundWindow(IntPtr hWnd);

        [DllImport("user32.dll")]
        public static extern bool IsIconic(IntPtr hWnd);

        [DllImport("user32.dll")]
        public static extern bool IsWindowVisible(IntPtr hWnd);

        [DllImport("user32.dll")]
        public static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);

        [StructLayout(LayoutKind.Sequential)]
        public struct RECT
        {
            public int Left;
            public int Top;
            public int Right;
            public int Bottom;
        }
    }

    internal static class EnvUtil
    {
        public static readonly string[] ProxyVarNames = new string[] { "HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY" };
        public const string NoProxyName = "NO_PROXY";
        public const string DefaultNoProxy = "localhost,127.0.0.1,::1,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16";

        public static string GetUser(string name)
        {
            try { return Environment.GetEnvironmentVariable(name, EnvironmentVariableTarget.User); }
            catch { return null; }
        }

        // 直接写注册表：Environment.SetEnvironmentVariable(..., User) 每次都会做一次跨进程广播，
        // 单个变量耗时可达秒级，这里改为统一由 Broadcast() 通知一次。
        public static void SetUser(string name, string value)
        {
            using (RegistryKey key = Registry.CurrentUser.CreateSubKey("Environment"))
            {
                if (key != null) key.SetValue(name, value, RegistryValueKind.String);
            }
        }

        public static void DeleteUser(string name)
        {
            using (RegistryKey key = Registry.CurrentUser.OpenSubKey("Environment", true))
            {
                if (key != null) key.DeleteValue(name, false);
            }
        }

        public static void ApplyProcessEnv(string url)
        {
            try
            {
                Environment.SetEnvironmentVariable("HTTP_PROXY", url);
                Environment.SetEnvironmentVariable("HTTPS_PROXY", url);
                Environment.SetEnvironmentVariable("ALL_PROXY", url);
                Environment.SetEnvironmentVariable("NO_PROXY", DefaultNoProxy);
            }
            catch { }
        }

        public static void Broadcast()
        {
            try
            {
                IntPtr result;
                Native.SendMessageTimeout(new IntPtr(0xffff), 0x001A, IntPtr.Zero, "Environment",
                    0x0002, 3000, out result);
            }
            catch { }
        }

        public static string CurrentProxyUrl()
        {
            string v = GetUser("HTTPS_PROXY");
            if (string.IsNullOrEmpty(v)) v = GetUser("HTTP_PROXY");
            return v;
        }

        public static bool MatchesProxy(string proxyUrl)
        {
            string v = CurrentProxyUrl();
            return v != null && string.Equals(v.Trim(), proxyUrl, StringComparison.OrdinalIgnoreCase);
        }
    }

    internal static class NetUtil
    {
        public static bool IsListening(string host, int port, int timeoutMs)
        {
            try
            {
                using (var client = new TcpClient())
                {
                    IAsyncResult ar = client.BeginConnect(host, port, null, null);
                    if (!ar.AsyncWaitHandle.WaitOne(timeoutMs)) return false;
                    client.EndConnect(ar);
                    return true;
                }
            }
            catch { return false; }
        }

        public static void GetPortOwner(int port, out int pid, out string processName)
        {
            pid = 0;
            processName = null;
            string output = RunHidden("netstat.exe", "-ano -p tcp");
            if (output == null) return;
            foreach (string line in output.Split('\n'))
            {
                string t = line.Trim();
                if (t.Length == 0) continue;
                string[] parts = t.Split(new char[] { ' ', '\t' }, StringSplitOptions.RemoveEmptyEntries);
                if (parts.Length < 5) continue;
                if (!parts[0].Equals("TCP", StringComparison.OrdinalIgnoreCase)) continue;
                string local = parts[1];
                int colon = local.LastIndexOf(':');
                if (colon < 0) continue;
                int p;
                if (!int.TryParse(local.Substring(colon + 1), out p) || p != port) continue;
                if (!parts[3].Equals("LISTENING", StringComparison.OrdinalIgnoreCase)) continue;
                int owner;
                if (!int.TryParse(parts[4], out owner)) continue;
                pid = owner;
                try
                {
                    using (Process pr = Process.GetProcessById(owner)) { processName = pr.ProcessName; }
                }
                catch { }
                return;
            }
        }

        public static string RunHidden(string file, string arguments)
        {
            try
            {
                var psi = new ProcessStartInfo(file, arguments);
                psi.UseShellExecute = false;
                psi.CreateNoWindow = true;
                psi.RedirectStandardOutput = true;
                psi.RedirectStandardError = true;
                using (Process p = Process.Start(psi))
                {
                    if (p == null) return null;
                    string text = null;
                    Task<string> reader = Task.Factory.StartNew<string>(delegate { return p.StandardOutput.ReadToEnd(); });
                    if (reader.Wait(4000)) text = reader.Result;
                    try { if (!p.HasExited) p.Kill(); } catch { }
                    return text;
                }
            }
            catch { return null; }
        }
    }

    internal class ProxyTestResult
    {
        public bool TcpOk;
        public bool ConnectOk;
        public string Detail;
        public int LatencyMs;
    }

    internal static class ProxyTester
    {
        public static ProxyTestResult Test(string host, int port)
        {
            var result = new ProxyTestResult();
            var sw = Stopwatch.StartNew();
            if (!NetUtil.IsListening(host, port, 1500))
            {
                result.LatencyMs = (int)sw.ElapsedMilliseconds;
                result.Detail = "无法连接 " + host + ":" + port.ToString();
                return result;
            }
            result.TcpOk = true;
            result.LatencyMs = (int)sw.ElapsedMilliseconds;
            try
            {
                using (var client = new TcpClient())
                {
                    IAsyncResult ar = client.BeginConnect(host, port, null, null);
                    if (!ar.AsyncWaitHandle.WaitOne(1500))
                    {
                        result.Detail = "端口可达，但代理连接超时";
                        return result;
                    }
                    client.EndConnect(ar);
                    client.SendTimeout = 5000;
                    client.ReceiveTimeout = 8000;
                    NetworkStream ns = client.GetStream();
                    byte[] req = Encoding.ASCII.GetBytes(
                        "CONNECT chatgpt.com:443 HTTP/1.1\r\nHost: chatgpt.com:443\r\nProxy-Connection: Keep-Alive\r\n\r\n");
                    ns.Write(req, 0, req.Length);

                    var sb = new StringBuilder();
                    byte[] buf = new byte[256];
                    DateTime deadline = DateTime.UtcNow.AddSeconds(8);
                    while (DateTime.UtcNow < deadline)
                    {
                        int n;
                        try { n = ns.Read(buf, 0, buf.Length); }
                        catch (IOException) { break; }
                        if (n <= 0) break;
                        sb.Append(Encoding.ASCII.GetString(buf, 0, n));
                        if (sb.ToString().IndexOf("\r\n") >= 0) break;
                    }
                    string resp = sb.ToString();
                    if (resp.StartsWith("HTTP/1.1 200") || resp.StartsWith("HTTP/1.0 200"))
                    {
                        result.ConnectOk = true;
                        result.Detail = "代理可用，已成功打通道 chatgpt.com:443";
                    }
                    else if (resp.Length == 0)
                    {
                        result.Detail = "端口可达，但代理无响应（可能是纯 SOCKS 端口）";
                    }
                    else
                    {
                        string first = resp.Split('\n')[0].Trim();
                        if (first.Length > 60) first = first.Substring(0, 60);
                        result.Detail = "端口可达，但代理返回：" + first;
                    }
                }
            }
            catch (Exception ex)
            {
                result.Detail = "测试失败：" + ex.Message;
            }
            result.LatencyMs = (int)sw.ElapsedMilliseconds;
            return result;
        }
    }

    internal static class ShellShortcut
    {
        private static object NewShell()
        {
            Type t = Type.GetTypeFromProgID("WScript.Shell");
            if (t == null) throw new InvalidOperationException("无法创建 WScript.Shell");
            return Activator.CreateInstance(t);
        }

        public static void Create(string lnkPath, string target, string arguments, string iconPath,
            string workDir, string description)
        {
            object shell = NewShell();
            try
            {
                object lnk = shell.GetType().InvokeMember("CreateShortcut", BindingFlags.InvokeMethod, null,
                    shell, new object[] { lnkPath });
                Type t = lnk.GetType();
                t.InvokeMember("TargetPath", BindingFlags.SetProperty, null, lnk, new object[] { target });
                t.InvokeMember("Arguments", BindingFlags.SetProperty, null, lnk, new object[] { arguments });
                if (!string.IsNullOrEmpty(iconPath))
                    t.InvokeMember("IconLocation", BindingFlags.SetProperty, null, lnk, new object[] { iconPath });
                if (!string.IsNullOrEmpty(workDir))
                    t.InvokeMember("WorkingDirectory", BindingFlags.SetProperty, null, lnk, new object[] { workDir });
                t.InvokeMember("Description", BindingFlags.SetProperty, null, lnk, new object[] { description });
                t.InvokeMember("Save", BindingFlags.InvokeMethod, null, lnk, null);
                Marshal.ReleaseComObject(lnk);
            }
            finally
            {
                Marshal.ReleaseComObject(shell);
            }
        }

        public static string Target(string lnkPath)
        {
            try
            {
                if (!File.Exists(lnkPath)) return null;
                object shell = NewShell();
                try
                {
                    object lnk = shell.GetType().InvokeMember("CreateShortcut", BindingFlags.InvokeMethod, null,
                        shell, new object[] { lnkPath });
                    object tp = lnk.GetType().InvokeMember("TargetPath", BindingFlags.GetProperty, null, lnk, null);
                    Marshal.ReleaseComObject(lnk);
                    return tp as string;
                }
                finally
                {
                    Marshal.ReleaseComObject(shell);
                }
            }
            catch { return null; }
        }

        public static bool PointsTo(string lnkPath, string exePath)
        {
            string target = Target(lnkPath);
            return !string.IsNullOrEmpty(target) &&
                   string.Equals(target, exePath, StringComparison.OrdinalIgnoreCase);
        }

        /// <summary>判断是否为“指向打包应用的原始快捷方式”（这类快捷方式没有 TargetPath）</summary>
        public static bool IsPackagedAppShortcut(string lnkPath)
        {
            try
            {
                if (!File.Exists(lnkPath)) return false;
                byte[] bytes = File.ReadAllBytes(lnkPath);
                string ascii = Encoding.ASCII.GetString(bytes);
                string uni = Encoding.Unicode.GetString(bytes);
                return ascii.IndexOf("AppsFolder", StringComparison.OrdinalIgnoreCase) >= 0 ||
                       uni.IndexOf("AppsFolder", StringComparison.OrdinalIgnoreCase) >= 0 ||
                       uni.IndexOf("OpenAI.Codex", StringComparison.OrdinalIgnoreCase) >= 0 ||
                       uni.IndexOf("OpenAI.ChatGPT", StringComparison.OrdinalIgnoreCase) >= 0;
            }
            catch { return false; }
        }
    }

    [ComImport, Guid("2e941141-7f97-4756-ba1d-9decde894a3d"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface IApplicationActivationManager
    {
        int ActivateApplication([In, MarshalAs(UnmanagedType.LPWStr)] string appUserModelId,
                                [In, MarshalAs(UnmanagedType.LPWStr)] string arguments,
                                [In] int options,
                                [Out, MarshalAs(UnmanagedType.U4)] out uint processId);

        int ActivateForFile([In, MarshalAs(UnmanagedType.LPWStr)] string appUserModelId,
                            [In, MarshalAs(UnmanagedType.LPWStr)] string itemArray,
                            [In, MarshalAs(UnmanagedType.LPWStr)] string verb,
                            [Out, MarshalAs(UnmanagedType.U4)] out uint processId);

        int ActivateForProtocol([In, MarshalAs(UnmanagedType.LPWStr)] string appUserModelId,
                                [In, MarshalAs(UnmanagedType.LPWStr)] string itemArray,
                                [Out, MarshalAs(UnmanagedType.U4)] out uint processId);
    }

    internal class AppInfo
    {
        public string DisplayName = "ChatGPT";
        public string PackageFullName;
        public string FamilyName;
        public string Version;
        public string InstallPath;
        public string AppId = "App";
        public string ExePath;

        public bool IsPackaged { get { return !string.IsNullOrEmpty(FamilyName); } }
        public string Aumid
        {
            get { return IsPackaged ? FamilyName + "!" + AppId : null; }
        }
        public string VersionText
        {
            get { return string.IsNullOrEmpty(Version) ? "已安装" : Version; }
        }
    }

    internal static class AppFinder
    {
        private static readonly string[] FallbackExePaths = new string[]
        {
            @"%LOCALAPPDATA%\Programs\ChatGPT\ChatGPT.exe",
            @"%LOCALAPPDATA%\Programs\chatgpt\ChatGPT.exe",
            @"%LOCALAPPDATA%\ChatGPT\ChatGPT.exe",
            @"%ProgramFiles%\ChatGPT\ChatGPT.exe",
            @"%ProgramFiles(x86)%\ChatGPT\ChatGPT.exe"
        };

        public static AppInfo Find()
        {
            AppInfo packaged = FindPackaged();
            if (packaged != null) return packaged;
            return FindUnpackaged();
        }

        private static AppInfo FindPackaged()
        {
            try
            {
                string repoPath = @"Software\Classes\Local Settings\Software\Microsoft\Windows\CurrentVersion\AppModel\Repository\Packages";
                using (RegistryKey key = Registry.CurrentUser.OpenSubKey(repoPath))
                {
                    if (key == null) return null;
                    AppInfo best = null;
                    foreach (string subName in key.GetSubKeyNames())
                    {
                        bool isCodex = subName.StartsWith(AppConstants.PackagePrefix, StringComparison.OrdinalIgnoreCase);
                        bool isChatGpt = subName.StartsWith("OpenAI.ChatGPT", StringComparison.OrdinalIgnoreCase);
                        if (!isCodex && !isChatGpt) continue;
                        using (RegistryKey sub = key.OpenSubKey(subName))
                        {
                            if (sub == null) continue;
                            var info = new AppInfo();
                            info.PackageFullName = subName;
                            string[] parts = subName.Split('_');
                            if (parts.Length >= 5)
                            {
                                info.Version = parts[1];
                                info.FamilyName = parts[0] + "_" + parts[parts.Length - 1];
                            }
                            info.InstallPath = sub.GetValue("PackageRootFolder") as string;
                            if (string.IsNullOrEmpty(info.InstallPath) || !Directory.Exists(info.InstallPath)) continue;

                            string manifest = Path.Combine(info.InstallPath, "AppxManifest.xml");
                            if (File.Exists(manifest))
                            {
                                try
                                {
                                    var doc = new System.Xml.XmlDocument();
                                    doc.Load(manifest);
                                    System.Xml.XmlNode appNode = doc.SelectSingleNode("/Package/Applications/Application");
                                    if (appNode != null && appNode.Attributes != null)
                                    {
                                        if (appNode.Attributes["Id"] != null) info.AppId = appNode.Attributes["Id"].Value;
                                        if (appNode.Attributes["Executable"] != null)
                                        {
                                            string rel = appNode.Attributes["Executable"].Value.Replace('/', '\\');
                                            string exe = Path.Combine(info.InstallPath, rel);
                                            if (File.Exists(exe)) info.ExePath = exe;
                                        }
                                    }
                                    System.Xml.XmlNode dn = doc.SelectSingleNode("/Package/Properties/DisplayName");
                                    if (dn != null && !string.IsNullOrEmpty(dn.InnerText) &&
                                        !dn.InnerText.StartsWith("ms-resource", StringComparison.OrdinalIgnoreCase))
                                        info.DisplayName = dn.InnerText;
                                }
                                catch { }
                            }
                            if (string.IsNullOrEmpty(info.ExePath))
                            {
                                string guess = Path.Combine(info.InstallPath, "app\\ChatGPT.exe");
                                if (File.Exists(guess)) info.ExePath = guess;
                            }
                            if (best == null || string.Compare(info.Version, best.Version, StringComparison.Ordinal) > 0)
                                best = info;
                        }
                    }
                    return best;
                }
            }
            catch { return null; }
        }

        private static AppInfo FindUnpackaged()
        {
            foreach (string raw in FallbackExePaths)
            {
                string path = Environment.ExpandEnvironmentVariables(raw);
                if (!File.Exists(path)) continue;
                var info = new AppInfo();
                info.ExePath = path;
                info.InstallPath = Path.GetDirectoryName(path);
                info.FamilyName = null;
                info.Version = "";
                return info;
            }
            return null;
        }
    }

    internal class DetectResult
    {
        public AppInfo App;
        public bool PortListening;
        public int PortOwnerPid;
        public string PortOwnerName;
        public bool SystemProxyEnabled;
        public string SystemProxyServer;
        public bool PacConfigured;
        public List<string> TunAdapters = new List<string>();
        public string EnvProxyUrl;
        public bool EnvMatches;
        public bool AppRunning;
        public bool AppRunningWithProxy;
        public bool ManagedDesktopLnk;
        public bool ManagedStartMenuLnk;
        public bool DesktopTakenOver;
        public string DesktopLnkTarget;
        public bool HasOriginalBackup;
    }

    internal static class Detector
    {
        public static DetectResult Run(Settings settings)
        {
            var result = new DetectResult();
            result.App = AppFinder.Find();
            result.PortListening = NetUtil.IsListening(settings.ProxyHost, settings.ProxyPort, 800);
            if (result.PortListening)
                NetUtil.GetPortOwner(settings.ProxyPort, out result.PortOwnerPid, out result.PortOwnerName);

            try
            {
                using (RegistryKey key = Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Internet Settings"))
                {
                    if (key != null)
                    {
                        object enabled = key.GetValue("ProxyEnable");
                        result.SystemProxyEnabled = enabled != null && Convert.ToInt32(enabled) == 1;
                        result.SystemProxyServer = key.GetValue("ProxyServer") as string;
                        object pac = key.GetValue("AutoConfigURL");
                        result.PacConfigured = pac != null && !string.IsNullOrEmpty(pac.ToString());
                    }
                }
            }
            catch { }

            try
            {
                foreach (System.Net.NetworkInformation.NetworkInterface ni in
                         System.Net.NetworkInformation.NetworkInterface.GetAllNetworkInterfaces())
                {
                    string text = (ni.Name + " " + ni.Description).ToLowerInvariant();
                    if (text.Contains("tun") || text.Contains("wintun") || text.Contains("mihomo") ||
                        text.Contains("clash") || text.Contains("singbox") || text.Contains("sing-box") ||
                        text.Contains("tap"))
                    {
                        result.TunAdapters.Add(ni.Name);
                    }
                }
            }
            catch { }

            result.EnvProxyUrl = EnvUtil.CurrentProxyUrl();
            result.EnvMatches = EnvUtil.MatchesProxy(settings.ProxyUrl);

            result.ManagedDesktopLnk = ShellShortcut.PointsTo(Paths.DesktopManagedLnk, Paths.ExePath);
            result.ManagedStartMenuLnk = ShellShortcut.PointsTo(Paths.StartMenuManagedLnk, Paths.ExePath);
            result.DesktopLnkTarget = ShellShortcut.Target(Paths.DesktopAppLnk);
            result.DesktopTakenOver = ShellShortcut.PointsTo(Paths.DesktopAppLnk, Paths.ExePath);
            result.HasOriginalBackup = File.Exists(Paths.ShortcutBackup) || File.Exists(Paths.LegacyBackup);

            Process[] procs = Process.GetProcessesByName("ChatGPT");
            result.AppRunning = procs.Length > 0;
            if (result.AppRunning) result.AppRunningWithProxy = AppLauncher.AnyRunningWithProxy();
            return result;
        }
    }

    internal static class AppLauncher
    {
        public static bool AnyRunningWithProxy()
        {
            try
            {
                using (var searcher = new ManagementObjectSearcher(
                    "SELECT ProcessId, CommandLine FROM Win32_Process WHERE Name = 'ChatGPT.exe'"))
                {
                    foreach (ManagementBaseObject o in searcher.Get())
                    {
                        string cmd = o["CommandLine"] as string;
                        if (cmd != null && cmd.IndexOf("--proxy-server", StringComparison.OrdinalIgnoreCase) >= 0)
                            return true;
                    }
                }
            }
            catch { }
            return false;
        }

        public static void CloseAll(int waitMs)
        {
            Process[] procs = Process.GetProcessesByName("ChatGPT");
            foreach (Process p in procs)
            {
                try { p.CloseMainWindow(); }
                catch { }
            }
            DateTime deadline = DateTime.UtcNow.AddMilliseconds(waitMs);
            while (DateTime.UtcNow < deadline && Process.GetProcessesByName("ChatGPT").Length > 0)
                Thread.Sleep(250);
            foreach (Process p in Process.GetProcessesByName("ChatGPT")) { try { p.Kill(); } catch { } }
            foreach (Process p in Process.GetProcessesByName("codex")) { try { p.Kill(); } catch { } }
            Thread.Sleep(600);
        }

        /// <summary>带代理参数启动 ChatGPT，并确保窗口正常显示</summary>
        public static void Launch(AppInfo app, string proxyUrl)
        {
            string switchArg = "--proxy-server=" + proxyUrl;
            if (app != null && app.IsPackaged)
            {
                AppActivatorActivate(app.Aumid, switchArg);
            }
            else
            {
                string exe = app != null ? app.ExePath : null;
                if (string.IsNullOrEmpty(exe)) throw new InvalidOperationException("未找到 ChatGPT 可执行文件");
                var psi = new ProcessStartInfo(exe, switchArg);
                psi.UseShellExecute = false;
                psi.WorkingDirectory = Path.GetDirectoryName(exe);
                Process.Start(psi);
            }
            RestoreWindow(12);
        }

        private static void AppActivatorActivate(string aumid, string arguments)
        {
            Type t = Type.GetTypeFromCLSID(new Guid("45BA127D-10A8-46EA-8AB7-56EA9078943C"));
            object o = Activator.CreateInstance(t);
            IApplicationActivationManager mgr = (IApplicationActivationManager)o;
            uint pid;
            int hr = mgr.ActivateApplication(aumid, arguments, 0, out pid);
            Marshal.ReleaseComObject(mgr);
            if (hr != 0) Marshal.ThrowExceptionForHR(hr);
        }

        /// <summary>找到该应用最合适的窗口：可见且面积最大的那个（避免误选隐藏的辅助窗口）</summary>
        private static IntPtr FindBestWindow()
        {
            IntPtr best = IntPtr.Zero;
            int bestArea = 0;
            foreach (Process p in Process.GetProcessesByName("ChatGPT"))
            {
                try
                {
                    IntPtr hwnd = p.MainWindowHandle;
                    if (hwnd == IntPtr.Zero) continue;
                    if (!Native.IsWindowVisible(hwnd)) continue;
                    Native.RECT rect;
                    if (!Native.GetWindowRect(hwnd, out rect)) continue;
                    int area = (rect.Right - rect.Left) * (rect.Bottom - rect.Top);
                    if (area > bestArea)
                    {
                        bestArea = area;
                        best = hwnd;
                    }
                }
                catch { }
            }
            return best;
        }

        /// <summary>让已运行的实例把窗口显示出来：打包应用再次激活会转交给已运行实例处理</summary>
        public static void ActivateToFront(AppInfo app, string proxyUrl)
        {
            if (app != null && app.IsPackaged)
            {
                try { AppActivatorActivate(app.Aumid, "--proxy-server=" + proxyUrl); }
                catch { }
            }
            RestoreWindow(6);
        }

        public static void RestoreWindow(int seconds)
        {
            DateTime deadline = DateTime.UtcNow.AddSeconds(seconds);
            while (DateTime.UtcNow < deadline)
            {
                IntPtr hwnd = FindBestWindow();
                if (hwnd != IntPtr.Zero)
                {
                    if (Native.IsIconic(hwnd)) Native.ShowWindow(hwnd, 9);   // SW_RESTORE
                    Native.SetForegroundWindow(hwnd);
                    return;
                }
                Thread.Sleep(250);
            }
        }
    }

    internal class EnableOutcome
    {
        public bool EnvDone;
        public bool ShortcutsDone;
        public bool TakeOverDone;
        public bool Launched;
        public string Message;
    }

    /// <summary>一键开启 / 一键还原 / 启动：全部逻辑集中在这里，界面只负责调用</summary>
    internal static class Operations
    {
        public static EnableOutcome Enable(Settings settings)
        {
            var outcome = new EnableOutcome();
            settings.Save();
            LogBus.Write("设置已保存：代理 " + settings.Endpoint, LogKind.Detail);

            if (settings.OptSetEnvVars)
            {
                foreach (string name in EnvUtil.ProxyVarNames) EnvUtil.SetUser(name, settings.ProxyUrl);
                EnvUtil.SetUser(EnvUtil.NoProxyName, EnvUtil.DefaultNoProxy);
                EnvUtil.Broadcast();
                EnvUtil.ApplyProcessEnv(settings.ProxyUrl);
                outcome.EnvDone = true;
                LogBus.Write("已设置用户环境变量 HTTP_PROXY / HTTPS_PROXY / ALL_PROXY = " + settings.ProxyUrl, LogKind.Success);
            }
            else
            {
                LogBus.Write("已跳过环境变量设置", LogKind.Detail);
            }

            string args = "--launch";
            string icon = Paths.ExePath;
            try
            {
                ShellShortcut.Create(Paths.DesktopManagedLnk, Paths.ExePath, args, icon, Paths.DataDir,
                    "以本地代理 " + settings.Endpoint + " 启动 ChatGPT（无需系统代理/TUN）");
                ShellShortcut.Create(Paths.StartMenuManagedLnk, Paths.ExePath, args, icon, Paths.DataDir,
                    "以本地代理 " + settings.Endpoint + " 启动 ChatGPT（无需系统代理/TUN）");
                outcome.ShortcutsDone = true;
                LogBus.Write("已创建快捷方式：桌面、开始菜单（ChatGPT（本地代理））", LogKind.Success);
            }
            catch (Exception ex)
            {
                LogBus.Write("创建快捷方式失败：" + ex.Message, LogKind.Error);
            }

            if (settings.OptTakeOverShortcut)
            {
                try
                {
                    if (File.Exists(Paths.DesktopAppLnk) && !ShellShortcut.PointsTo(Paths.DesktopAppLnk, Paths.ExePath))
                    {
                        Directory.CreateDirectory(Paths.BackupDir);
                        bool needBackup = ShellShortcut.IsPackagedAppShortcut(Paths.DesktopAppLnk);
                        if (needBackup)
                        {
                            File.Copy(Paths.DesktopAppLnk, Paths.ShortcutBackup, true);
                            LogBus.Write("原「ChatGPT」快捷方式已备份", LogKind.Detail);
                        }
                        else if (!File.Exists(Paths.ShortcutBackup) && File.Exists(Paths.LegacyBackup))
                        {
                            // 之前由脚本方案处理的，沿用它的原始快捷方式备份
                            File.Copy(Paths.LegacyBackup, Paths.ShortcutBackup, true);
                        }
                        File.Delete(Paths.DesktopAppLnk);
                    }
                    ShellShortcut.Create(Paths.DesktopAppLnk, Paths.ExePath, args, icon, Paths.DataDir,
                        "以本地代理 " + settings.Endpoint + " 启动 ChatGPT（无需系统代理/TUN）");
                    outcome.TakeOverDone = true;
                    LogBus.Write("桌面「ChatGPT」快捷方式已接管", LogKind.Success);
                }
                catch (Exception ex)
                {
                    LogBus.Write("接管桌面快捷方式失败：" + ex.Message, LogKind.Error);
                }
            }

            if (settings.OptAutoLaunch)
            {
                try
                {
                    LaunchNow(settings, true);
                    outcome.Launched = true;
                }
                catch (Exception ex)
                {
                    LogBus.Write("启动 ChatGPT 失败：" + ex.Message, LogKind.Error);
                }
            }

            outcome.Message = "已开启";
            return outcome;
        }

        public static void Restore(Settings settings, bool closeApp)
        {
            bool removed = false;
            foreach (string name in EnvUtil.ProxyVarNames)
            {
                string cur = EnvUtil.GetUser(name);
                if (cur != null && string.Equals(cur.Trim(), settings.ProxyUrl, StringComparison.OrdinalIgnoreCase))
                {
                    EnvUtil.DeleteUser(name);
                    removed = true;
                }
            }
            string noProxy = EnvUtil.GetUser(EnvUtil.NoProxyName);
            if (noProxy != null && string.Equals(noProxy.Trim(), EnvUtil.DefaultNoProxy, StringComparison.OrdinalIgnoreCase))
            {
                EnvUtil.DeleteUser(EnvUtil.NoProxyName);
                removed = true;
            }
            if (removed)
            {
                EnvUtil.Broadcast();
                LogBus.Write("已移除环境变量 HTTP_PROXY / HTTPS_PROXY / ALL_PROXY / NO_PROXY", LogKind.Success);
            }
            else
            {
                LogBus.Write("环境变量无需清理（不是本程序设置的值）", LogKind.Detail);
            }

            RemoveIfOurs(Paths.DesktopManagedLnk, "桌面快捷方式（本地代理）");
            RemoveIfOurs(Paths.StartMenuManagedLnk, "开始菜单快捷方式（本地代理）");

            try
            {
                if (ShellShortcut.PointsTo(Paths.DesktopAppLnk, Paths.ExePath))
                {
                    if (File.Exists(Paths.ShortcutBackup))
                    {
                        File.Delete(Paths.DesktopAppLnk);
                        File.Copy(Paths.ShortcutBackup, Paths.DesktopAppLnk, true);
                        LogBus.Write("已恢复桌面原始「ChatGPT」快捷方式", LogKind.Success);
                    }
                    else if (File.Exists(Paths.LegacyBackup))
                    {
                        File.Delete(Paths.DesktopAppLnk);
                        File.Copy(Paths.LegacyBackup, Paths.DesktopAppLnk, true);
                        LogBus.Write("已恢复桌面原始「ChatGPT」快捷方式（旧方案备份）", LogKind.Success);
                    }
                    else
                    {
                        File.Delete(Paths.DesktopAppLnk);
                        LogBus.Write("未找到原始快捷方式备份，已移除接管的快捷方式", LogKind.Warn);
                    }
                }
            }
            catch (Exception ex)
            {
                LogBus.Write("恢复原始快捷方式失败：" + ex.Message, LogKind.Error);
            }

            if (closeApp && Process.GetProcessesByName("ChatGPT").Length > 0)
            {
                LogBus.Write("正在关闭 ChatGPT…", LogKind.Detail);
                AppLauncher.CloseAll(4000);
                LogBus.Write("ChatGPT 已关闭", LogKind.Success);
            }
            LogBus.Write("还原完成，系统恢复为“不使用代理直连”的状态", LogKind.Success);
        }

        private static void RemoveIfOurs(string lnkPath, string label)
        {
            try
            {
                if (ShellShortcut.PointsTo(lnkPath, Paths.ExePath))
                {
                    File.Delete(lnkPath);
                    LogBus.Write("已删除" + label, LogKind.Detail);
                }
            }
            catch (Exception ex)
            {
                LogBus.Write("删除" + label + "失败：" + ex.Message, LogKind.Warn);
            }
        }

        /// <summary>启动 ChatGPT（带代理）。restartIfNeeded 为真时会处理已在运行的实例。</summary>
        public static void LaunchNow(Settings settings, bool restartIfNeeded)
        {
            AppInfo app = AppFinder.Find();
            if (app == null || string.IsNullOrEmpty(app.ExePath))
                throw new InvalidOperationException("未找到 ChatGPT 桌面版");

            EnvUtil.ApplyProcessEnv(settings.ProxyUrl);

            if (!NetUtil.IsListening(settings.ProxyHost, settings.ProxyPort, 900))
                throw new InvalidOperationException("代理端口 " + settings.Endpoint + " 未监听");

            if (Process.GetProcessesByName("ChatGPT").Length > 0 && !AppLauncher.AnyRunningWithProxy())
            {
                if (!restartIfNeeded)
                {
                    LogBus.Write("ChatGPT 已在运行（未启用代理），请先退出后重试", LogKind.Warn);
                    return;
                }
                LogBus.Write("检测到未启用代理的实例，正在重启…", LogKind.Warn);
                AppLauncher.CloseAll(6000);
            }
            else if (Process.GetProcessesByName("ChatGPT").Length > 0)
            {
                LogBus.Write("ChatGPT 已在运行（已启用代理），正在切换到前台", LogKind.Detail);
                AppLauncher.ActivateToFront(app, settings.ProxyUrl);
                return;
            }

            LogBus.Write("正在以代理 " + settings.Endpoint + " 启动 ChatGPT…", LogKind.Info);
            AppLauncher.Launch(app, settings.ProxyUrl);
            LogBus.Write("ChatGPT 已启动，Chromium 网络栈走 " + settings.ProxyUrl, LogKind.Success);
        }
    }
}
