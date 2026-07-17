using System;
using System.Diagnostics;
using System.IO;
using System.Windows.Forms;

internal static class Program
{
    [STAThread]
    private static int Main()
    {
        if (Environment.GetEnvironmentVariable("GARMIN_SENDER_GUI_TEST") == "1")
        {
            return 0;
        }

        string root = AppDomain.CurrentDomain.BaseDirectory;
        string script = Path.Combine(root, "send_prg_gui.py");
        string[] candidates =
        {
            Path.Combine(root, ".runtime", "Scripts", "pythonw.exe"),
            Path.Combine(root, ".runtime", "Scripts", "python.exe"),
            Path.Combine(root, ".venv", "Scripts", "pythonw.exe"),
            Path.Combine(root, ".venv", "Scripts", "python.exe"),
        };

        string python = null;
        foreach (string candidate in candidates)
        {
            if (File.Exists(candidate))
            {
                python = candidate;
                break;
            }
        }

        if (python == null)
        {
            MessageBox.Show(
                "Python runtime was not found. Expected .runtime\\Scripts\\python.exe or .venv\\Scripts\\python.exe beside this launcher.",
                "Garmin PRG Sender",
                MessageBoxButtons.OK,
                MessageBoxIcon.Error
            );
            return 1;
        }

        if (!File.Exists(script))
        {
            MessageBox.Show(
                "send_prg_gui.py was not found beside this launcher.",
                "Garmin PRG Sender",
                MessageBoxButtons.OK,
                MessageBoxIcon.Error
            );
            return 1;
        }

        try
        {
            ProcessStartInfo startInfo = new ProcessStartInfo
            {
                FileName = python,
                Arguments = "\"" + script + "\"",
                WorkingDirectory = root,
                UseShellExecute = false,
                CreateNoWindow = true,
            };
            Process.Start(startInfo);
            return 0;
        }
        catch (Exception ex)
        {
            MessageBox.Show(
                "Could not start the sender GUI:\r\n" + ex.Message,
                "Garmin PRG Sender",
                MessageBoxButtons.OK,
                MessageBoxIcon.Error
            );
            return 1;
        }
    }
}
