using System;
using System.IO;
using System.Linq;
using System.Threading.Tasks;
using Avalonia;

namespace LogicRipper.Gui.Avalonia;

internal static class Program
{
    private const string VersionText = "LogicRipper.Gui 0.1.0";

    [STAThread]
    public static int Main(string[] args)
    {
        if (args.Contains("--version"))
        {
            Console.WriteLine(VersionText);
            return 0;
        }

        if (args.Contains("--bridge-smoke"))
        {
            return RunBridgeSmokeAsync(args).GetAwaiter().GetResult();
        }

        var envError = GetGraphicalEnvironmentError();
        if (envError is not null)
        {
            Console.Error.WriteLine(envError);
            return 2;
        }

        BuildAvaloniaApp().StartWithClassicDesktopLifetime(args);
        return 0;
    }

    public static AppBuilder BuildAvaloniaApp()
    {
        return AppBuilder.Configure<App>()
            .UsePlatformDetect()
            .LogToTrace();
    }

    private static string? GetGraphicalEnvironmentError()
    {
        if (OperatingSystem.IsLinux())
        {
            var display = Environment.GetEnvironmentVariable("DISPLAY");
            var wayland = Environment.GetEnvironmentVariable("WAYLAND_DISPLAY");
            var ssh = Environment.GetEnvironmentVariable("SSH_CONNECTION");
            if (string.IsNullOrWhiteSpace(display) && string.IsNullOrWhiteSpace(wayland))
            {
                return string.IsNullOrWhiteSpace(ssh)
                    ? "LogicRipper GUI needs an Ubuntu desktop session. DISPLAY and WAYLAND_DISPLAY are both missing."
                    : "LogicRipper GUI cannot open from this headless SSH session. Enable X forwarding or run it inside the Ubuntu desktop session.";
            }
        }

        return null;
    }

    private static async Task<int> RunBridgeSmokeAsync(string[] args)
    {
        var fixture = GetArg(args, "--fixture") ?? Path.Combine("tests", "Fixtures", "disable-user-accounts.workflow.json");
        var basePath = GetArg(args, "--base-path") ?? Path.Combine(Path.GetTempPath(), "logic-ripper-gui-smoke-" + Guid.NewGuid().ToString("n"));
        try
        {
            var bridge = new LogicRipperBackend();
            await bridge.RunSmokeAsync(fixture, basePath);
            Console.WriteLine("GUI backend bridge smoke passed.");
            return 0;
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine("GUI backend bridge smoke failed: " + ex.Message);
            return 1;
        }
    }

    private static string? GetArg(string[] args, string name)
    {
        for (var i = 0; i < args.Length - 1; i++)
        {
            if (args[i] == name) return args[i + 1];
        }

        return null;
    }
}
