using System;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using HidSharp;
using Microsoft.Win32;

// CirqueFix — restores Cirque/Sensel touchpad TrackPoint scroll after Windows lock/unlock.
// https://github.com/YOUR_USERNAME/CirqueFix
// MIT License

using System.Runtime.InteropServices;

class CirqueFix
{
    [DllImport("kernel32.dll")] static extern bool AllocConsole();
    [DllImport("kernel32.dll")] static extern bool AttachConsole(int pid);
    const int ATTACH_PARENT_PROCESS = -1;
    const int    SENSEL_VID        = 0x2C2F;
    const int    PRIMAX_VID        = 0x17EF;
    const ushort SENSEL_USAGE_PAGE = 0xFF00;
    const ushort SENSEL_USAGE      = 0x0001;
    const byte   REPORT_ID         = 9;

    // Register addresses (from Cirque/Sensel firmware register map)
    const ushort REG_PTP_BUTTONS_CONFIG          = 0x008A;
    const ushort REG_CLICK_FORCE_DIV2            = 0x0038;
    const ushort REG_LIFT_FORCE_DIV2             = 0x0090;
    const ushort REG_CLICK_FORCE_3HB_LEFT_DIV2   = 0x0091;
    const ushort REG_LIFT_FORCE_3HB_LEFT_DIV2    = 0x0092;
    const ushort REG_CLICK_FORCE_3HB_RIGHT_DIV2  = 0x0093;
    const ushort REG_LIFT_FORCE_3HB_RIGHT_DIV2   = 0x0094;
    const ushort REG_CLICK_FORCE_3HB_MIDDLE_DIV2 = 0x0095;
    const ushort REG_LIFT_FORCE_3HB_MIDDLE_DIV2  = 0x0096;

    const string REG_PATH   = @"Software\Cirque\Touchpad\Current";
    const double LIFT_RATIO = 0.65;

    enum ApplyResult { Success, DeviceBusy, FatalError }

    // Log only in Debug builds; Release is silent unless there's an error
    static void Log(string msg)
    {
#if VERBOSE_LOG
        Console.WriteLine(msg);
#endif
    }

    static int Main(string[] args)
    {
        bool once  = args.Contains("--once");
        bool watch = args.Contains("--watch");

        if (!once && !watch)
        {
            Console.WriteLine("CirqueFix — restores TrackPoint scroll after Windows lock/unlock");
            Console.WriteLine("Usage:");
            Console.WriteLine("  CirqueFix.exe --once     Apply settings once and exit");
            Console.WriteLine("  CirqueFix.exe --watch    Apply on startup, re-apply after unlock");
            return 1;
        }

        if (once)
        {
            // Attach to the calling console so output is visible when run manually
            if (!AttachConsole(ATTACH_PARENT_PROCESS)) AllocConsole();
            return Apply() == ApplyResult.Success ? 0 : 1;
        }

        Apply();

        // Coverage loop on boot — the Sensel UI and CirqueTouchpadSettingsHelper.exe
        // initialize at unpredictable times after logon and reset PTP_BUTTONS_CONFIG.
        // Keep re-applying for 30 seconds to ensure we're last to write.
        Task.Run(() =>
        {
            var deadline = DateTime.UtcNow.AddSeconds(30);
            while (DateTime.UtcNow < deadline)
            {
                Thread.Sleep(500);
                Apply();
            }
            Log($"[{DateTime.Now:T}] Boot coverage done.");
        });

        var ready = new ManualResetEventSlim(false);
        var thread = new Thread(() =>
        {
            SystemEvents.SessionSwitch += OnSessionSwitch;
            Log($"[{DateTime.Now:T}] Watcher active.");
            ready.Set();
            while (true) Thread.Sleep(Timeout.Infinite);
        });
        thread.SetApartmentState(ApartmentState.STA);
        thread.IsBackground = false;
        thread.Start();
        ready.Wait();
        thread.Join();
        return 0;
    }

    static void OnSessionSwitch(object? sender, SessionSwitchEventArgs e)
    {
        Log($"[{DateTime.Now:T}] Session event: {e.Reason}");
        if (e.Reason != SessionSwitchReason.SessionUnlock) return;

        // Exponential backoff until first success
        bool everSucceeded = false;
        int[] delays = { 10, 20, 40, 100, 200, 500, 1000, 2000 };
        foreach (int delay in delays)
        {
            Thread.Sleep(delay);
            Log($"[{DateTime.Now:T}] Attempt after {delay}ms...");
            ApplyResult r = Apply();
            if (r == ApplyResult.FatalError) { Console.Error.WriteLine($"[{DateTime.Now:T}] Fatal error, giving up."); return; }
            if (r == ApplyResult.Success) { everSucceeded = true; break; }
        }

        if (!everSucceeded)
        {
            // Still busy (e.g. touchpad click held) — wait for device release event
            Log($"[{DateTime.Now:T}] Device busy, waiting for release...");
            WaitForDeviceReady(() =>
            {
                Log($"[{DateTime.Now:T}] Device available, retrying...");
                Apply();
            });
            return;
        }

        // Keep re-applying every 200ms for 3 seconds to outlast the Sensel UI's own
        // activation writes (Window_Activated fires at unpredictable time after unlock)
        var deadline = DateTime.UtcNow.AddSeconds(3);
        while (DateTime.UtcNow < deadline)
        {
            Thread.Sleep(200);
            Log($"[{DateTime.Now:T}] Coverage apply...");
            Apply();
        }
        Log($"[{DateTime.Now:T}] Done.");
    }

    static ApplyResult Apply()
    {
        Settings? s = ReadSettings();
        if (s == null) return ApplyResult.FatalError;

        Log($"[{DateTime.Now:T}] Applying: TrackPointButtons={s.TrackPointButtons}" +
            $" ClickForce={s.ClickForce} TrackPointClickForce={s.TrackPointClickForce}");

        try
        {
            HidDevice? device = FindDevice();
            if (device == null)
            {
                Console.Error.WriteLine("CirqueFix: No Cirque/Sensel device found.");
                return ApplyResult.FatalError;
            }

            var cfg = new OpenConfiguration();
            cfg.SetOption(OpenOption.Exclusive, true);
            HidStream stream;
            try { stream = device.Open(cfg); }
            catch (Exception ex) when (ex.Message.Contains("in use") || ex.Message.Contains("Access"))
            {
                Log($"[{DateTime.Now:T}] Device busy: {ex.Message}");
                return ApplyResult.DeviceBusy;
            }
            using (stream)
            {
                int regCount = 0;

                WriteReg(stream, REG_PTP_BUTTONS_CONFIG, (byte)(s.TrackPointButtons ? 1 : 0)); regCount++;

                if (s.ClickForce > 0)
                {
                    byte cfDiv2   = (byte)(s.ClickForce / 2);
                    byte liftDiv2 = (byte)(s.ClickForce / 2 * LIFT_RATIO);
                    WriteReg(stream, REG_CLICK_FORCE_DIV2, cfDiv2);   regCount++;
                    WriteReg(stream, REG_LIFT_FORCE_DIV2,  liftDiv2); regCount++;
                }

                if (s.TrackPointClickForce > 0)
                {
                    byte cfDiv2   = (byte)(s.TrackPointClickForce / 2);
                    byte liftDiv2 = (byte)(s.TrackPointClickForce / 2 * LIFT_RATIO);
                    WriteReg(stream, REG_CLICK_FORCE_3HB_LEFT_DIV2,   cfDiv2);   regCount++;
                    WriteReg(stream, REG_LIFT_FORCE_3HB_LEFT_DIV2,    liftDiv2); regCount++;
                    WriteReg(stream, REG_CLICK_FORCE_3HB_RIGHT_DIV2,  cfDiv2);   regCount++;
                    WriteReg(stream, REG_LIFT_FORCE_3HB_RIGHT_DIV2,   liftDiv2); regCount++;
                    WriteReg(stream, REG_CLICK_FORCE_3HB_MIDDLE_DIV2, cfDiv2);   regCount++;
                    WriteReg(stream, REG_LIFT_FORCE_3HB_MIDDLE_DIV2,  liftDiv2); regCount++;
                }

                DrainAcks(stream, regCount);
                Log($"[{DateTime.Now:T}] All settings applied.");
                return ApplyResult.Success;
            }
        }
        catch (Exception ex)
        {
            Log($"[{DateTime.Now:T}] Apply error: {ex.Message}");
            return ApplyResult.DeviceBusy;
        }
    }

    static void WriteReg(HidStream stream, ushort reg, byte value)
    {
        WriteHIDPipe(stream, BuildWriteCmd(reg, 1, new byte[] { value }));
        Log($"  reg 0x{reg:X4} = {value}");
    }

    static void DrainAcks(HidStream stream, int count)
    {
        stream.ReadTimeout = 30;
        for (int i = 0; i < count * 2; i++)
            try { ReadOneByte(stream); } catch { break; }
    }

    static void WaitForDeviceReady(Action action)
    {
        EventHandler<DeviceListChangedEventArgs>? handler = null;
        handler = (s, e) =>
        {
            DeviceList.Local.Changed -= handler;
            Thread.Sleep(50);
            action();
        };
        DeviceList.Local.Changed += handler;
    }

    class Settings
    {
        public bool TrackPointButtons    { get; set; }
        public int  ClickForce           { get; set; }
        public int  TrackPointClickForce { get; set; }
    }

    static Settings? ReadSettings()
    {
        try
        {
            using RegistryKey? key = Registry.CurrentUser.OpenSubKey(REG_PATH);
            if (key == null)
            {
                Console.Error.WriteLine($"CirqueFix: Registry key not found: HKCU\\{REG_PATH}");
                return null;
            }
            return new Settings
            {
                TrackPointButtons    = ((int?)key.GetValue("TrackPointButtons")    ?? 1) != 0,
                ClickForce           =  (int?)key.GetValue("ClickForce")           ?? 164,
                TrackPointClickForce =  (int?)key.GetValue("TrackPointClickForce") ?? 76,
            };
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine($"CirqueFix: Registry read error: {ex.Message}");
            return null;
        }
    }

    static HidDevice? FindDevice()
    {
        foreach (HidDevice dev in DeviceList.Local.GetHidDevices())
        {
            if (dev.VendorID != SENSEL_VID && dev.VendorID != PRIMAX_VID) continue;
            foreach (var report in dev.GetReportDescriptor().Reports)
            {
                if (report.ReportID != REPORT_ID) continue;
                foreach (uint raw in report.GetAllUsages())
                {
                    ushort page  = (ushort)(raw >> 16);
                    ushort usage = (ushort)(raw & 0xFFFF);
                    if (page == SENSEL_USAGE_PAGE && usage == SENSEL_USAGE
                        && dev.GetSerialPorts().Length == 0)
                        return dev;
                }
            }
        }
        return null;
    }

    static byte[] BuildWriteCmd(ushort reg, byte size, byte[] data)
    {
        byte cmd0 = (byte)(((reg & 0x3F00) >> 7) | 0x01);
        byte cmd1 = (byte)(reg & 0xFF);
        int checksum = 0;
        foreach (byte b in data) checksum += b;
        byte[] full = new byte[3 + data.Length + 1];
        full[0] = cmd0; full[1] = cmd1; full[2] = size;
        Array.Copy(data, 0, full, 3, data.Length);
        full[full.Length - 1] = (byte)(checksum & 0xFF);
        return full;
    }

    static void WriteHIDPipe(HidStream stream, byte[] data)
    {
        int offset = 0, remaining = data.Length;
        byte[] frame = new byte[21];
        while (remaining > 0)
        {
            int chunk = Math.Min(19, remaining);
            Array.Clear(frame, 0, frame.Length);
            frame[0] = REPORT_ID;
            frame[1] = (byte)chunk;
            Array.Copy(data, offset, frame, 2, chunk);
            stream.Write(frame, 0, frame.Length);
            offset += chunk; remaining -= chunk;
        }
    }

    static byte ReadOneByte(HidStream stream)
    {
        byte[] frame = new byte[21];
        int n = stream.Read(frame, 0, frame.Length);
        if (n != frame.Length || frame[0] != REPORT_ID)
            throw new Exception($"Bad frame (n={n}, id={frame[0]:X2})");
        if (frame[1] < 1) throw new Exception("Empty frame");
        return frame[2];
    }
}
