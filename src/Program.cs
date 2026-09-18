// ChatGPT 代理助手 - 入口（普通模式打开界面；--launch 模式静默带代理启动 ChatGPT）
using System;
using System.Diagnostics;
using System.Windows;

namespace ChatGPTProxyManager
{
    internal static class Program
    {
        [STAThread]
        private static int Main(string[] args)
        {
            try
            {
                return RunCore(args);
            }
            catch (Exception ex)
            {
                ReportCrash(ex);
                MessageBox.Show("程序启动失败：" + ex.Message + "\n\n详细信息已写入：\n" + Paths.DataDir + "\\crash.log",
                    AppConstants.ProductName, MessageBoxButton.OK, MessageBoxImage.Error);
                return 1;
            }
        }

        private static void ReportCrash(Exception ex)
        {
            try
            {
                System.IO.Directory.CreateDirectory(Paths.DataDir);
                string text = DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss") + "  " + ex.ToString() + "\r\n\r\n";
                System.IO.File.AppendAllText(Paths.DataDir + "\\crash.log", text);
            }
            catch { }
        }

        private static int RunCore(string[] args)
        {
            bool launchMode = false;
            bool enableMode = false;
            bool restoreMode = false;
            bool testMode = false;
            bool detectMode = false;
            foreach (string arg in args)
            {
                if (string.Equals(arg, "--launch", StringComparison.OrdinalIgnoreCase)) launchMode = true;
                else if (string.Equals(arg, "--enable", StringComparison.OrdinalIgnoreCase)) enableMode = true;
                else if (string.Equals(arg, "--restore", StringComparison.OrdinalIgnoreCase)) restoreMode = true;
                else if (string.Equals(arg, "--test", StringComparison.OrdinalIgnoreCase)) testMode = true;
                else if (string.Equals(arg, "--detect", StringComparison.OrdinalIgnoreCase)) detectMode = true;
            }

            Settings settings = Settings.Load();

            // 命令行模式（便于脚本调用与自动化验证）
            if (enableMode)
            {
                LogBus.Write("=== 命令行一键开启 ===", LogKind.Info);
                Operations.Enable(settings);
                return 0;
            }
            if (restoreMode)
            {
                LogBus.Write("=== 命令行一键还原 ===", LogKind.Info);
                Operations.Restore(settings, false);
                return 0;
            }
            if (testMode)
            {
                LogBus.Write("=== 命令行代理测试 " + settings.Endpoint + " ===", LogKind.Info);
                ProxyTestResult result = ProxyTester.Test(settings.ProxyHost, settings.ProxyPort);
                LogBus.Write((result.ConnectOk ? "通过：" : "未通过：") + result.Detail, result.ConnectOk ? LogKind.Success : LogKind.Error);
                return result.ConnectOk ? 0 : 2;
            }
            if (detectMode)
            {
                DetectResult detect = Detector.Run(settings);
                LogBus.Write("=== 命令行环境检测 ===", LogKind.Info);
                LogBus.Write("ChatGPT: " + (detect.App == null ? "未找到" : detect.App.VersionText + " (" + detect.App.InstallPath + ")"), LogKind.Info);
                LogBus.Write("代理端口 " + settings.Endpoint + ": " + (detect.PortListening ? "监听中 (" + detect.PortOwnerName + ")" : "未监听"), LogKind.Info);
                LogBus.Write("系统代理: " + (detect.SystemProxyEnabled ? "已开启" : "已关闭") + "，TUN: " + (detect.TunAdapters.Count > 0 ? string.Join("、", detect.TunAdapters.ToArray()) : "未启用"), LogKind.Info);
                LogBus.Write("环境变量: " + (detect.EnvProxyUrl == null ? "未设置" : detect.EnvProxyUrl), LogKind.Info);
                LogBus.Write("快捷方式: 管理快捷方式=" + ((detect.ManagedDesktopLnk ? 1 : 0) + (detect.ManagedStartMenuLnk ? 1 : 0)) + "/2，桌面接管=" + detect.DesktopTakenOver, LogKind.Info);
                LogBus.Write("运行状态: " + (detect.AppRunning ? (detect.AppRunningWithProxy ? "运行中（已走代理）" : "运行中（未走代理）") : "未运行"), LogKind.Info);
                return 0;
            }

            if (launchMode)
            {
                string error = TryLaunch(settings);
                if (error == null) return 0;
                // 启动条件不满足时打开主界面，把原因显示清楚
                return RunManager(settings, error);
            }
            return RunManager(settings, null);
        }

        /// <summary>返回 null 表示已成功启动（或已在运行并切到前台），否则返回错误说明</summary>
        private static string TryLaunch(Settings settings)
        {
            try
            {
                if (!NetUtil.IsListening(settings.ProxyHost, settings.ProxyPort, 900))
                    return "代理端口 " + settings.Endpoint + " 未监听，请先启动代理客户端（如 Clash Verge）。";

                AppInfo app = AppFinder.Find();
                if (app == null || string.IsNullOrEmpty(app.ExePath))
                    return "未找到 ChatGPT 桌面版，请确认已安装。";

                EnvUtil.ApplyProcessEnv(settings.ProxyUrl);

                if (Process.GetProcessesByName("ChatGPT").Length > 0)
                {
                    if (!AppLauncher.AnyRunningWithProxy())
                    {
                        MessageBoxResult answer = MessageBox.Show(
                            "ChatGPT 已经在运行，但它不是通过代理启动的，界面可能会一直停在启动画面。\n\n" +
                            "要关闭它并以代理方式重新启动吗？",
                            AppConstants.ProductName, MessageBoxButton.YesNo, MessageBoxImage.Question);
                        if (answer != MessageBoxResult.Yes)
                        {
                            AppLauncher.RestoreWindow(3);
                            return null;
                        }
                        AppLauncher.CloseAll(6000);
                    }
                    else
                    {
                        AppLauncher.ActivateToFront(app, settings.ProxyUrl);
                        return null;
                    }
                }

                LogBus.Write("以代理 " + settings.Endpoint + " 启动 ChatGPT（快捷方式启动）", LogKind.Info);
                AppLauncher.Launch(app, settings.ProxyUrl);
                return null;
            }
            catch (Exception ex)
            {
                LogBus.Write("启动失败：" + ex.Message, LogKind.Error);
                return ex.Message;
            }
        }

        private static int RunManager(Settings settings, string startupWarning)
        {
            var application = new Application();
            application.ShutdownMode = ShutdownMode.OnMainWindowClose;
            application.DispatcherUnhandledException += delegate(object s, System.Windows.Threading.DispatcherUnhandledExceptionEventArgs e)
            {
                LogBus.Write("界面异常：" + e.Exception.Message, LogKind.Error);
                MessageBox.Show(e.Exception.Message, AppConstants.ProductName, MessageBoxButton.OK, MessageBoxImage.Error);
                e.Handled = true;
            };
            var controller = new MainWindowController(settings, startupWarning);
            application.Run(controller.Window);
            return 0;
        }
    }
}
