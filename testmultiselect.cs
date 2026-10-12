// Тест IExplorerCommand с реальным IShellItemArray из 3 файлов (multi-select).
// Собирается:  cl /utf-8 testmultiselect.cs /Fe:mt.exe   (или dotnet-script)
using System;
using System.Runtime.InteropServices;

[ComImport, Guid("a08ce4d0-fa25-44ab-b57c-c7b1c323e0b9"),
 InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IExplorerCommand {
    [PreserveSig] int GetTitle(IntPtr psi, out IntPtr psz);
    [PreserveSig] int GetIcon(IntPtr psi, out IntPtr psz);
    [PreserveSig] int GetToolTip(IntPtr psi, out IntPtr psz);
    [PreserveSig] int GetCanonicalName(out Guid pguid);
    [PreserveSig] int GetState(IntPtr psi, [MarshalAs(UnmanagedType.Bool)] bool fOkToBeSlow, out uint pCmdState);
    [PreserveSig] int Invoke(IntPtr psi, IntPtr pbc);
    [PreserveSig] int GetFlags(out uint pFlags);
    [PreserveSig] int EnumSubCommands(out IntPtr ppEnum);
}

public static class Native {
    [DllImport("ole32.dll")] public static extern int CoInitializeEx(IntPtr p, uint f);
    [DllImport("ole32.dll")] public static extern int CoCreateInstance(ref Guid clsid, IntPtr outer, uint ctx, ref Guid iid, out IntPtr ppv);
    [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
    public static extern int SHParseDisplayName(string name, IntPtr pbc, out IntPtr ppidl, uint sfgaoIn, out uint sfgaoOut);
    [DllImport("shell32.dll")]
    public static extern int SHCreateShellItemArrayFromIDLists(uint cidl, IntPtr[] apidl, out IntPtr pArray);
    [DllImport("ole32.dll")] public static extern void CoTaskMemFree(IntPtr p);
}

public static class Program {
    public static int Main() {
        Native.CoInitializeEx(IntPtr.Zero, 2); // STA

        string[] files = {
            @"C:\projects\_menutest\parent\child\f1.txt",
            @"C:\projects\_menutest\parent\child\f2.txt",
            @"C:\projects\AndroidArchiver\build.bat"
        };

        IntPtr[] pidls = new IntPtr[files.Length];
        for (int i = 0; i < files.Length; i++) {
            uint attr;
            int hrParse = Native.SHParseDisplayName(files[i], IntPtr.Zero, out pidls[i], 0, out attr);
            if (hrParse != 0 || pidls[i] == IntPtr.Zero) {
                Console.WriteLine("FAIL SHParseDisplayName " + files[i] + " hr=0x" + hrParse.ToString("X8"));
                return 2;
            }
        }
        IntPtr arr;
        int hrArr = Native.SHCreateShellItemArrayFromIDLists((uint)pidls.Length, pidls, out arr);
        foreach (IntPtr p in pidls) Native.CoTaskMemFree(p);
        Console.WriteLine("SHCreateShellItemArrayFromIDLists = 0x" + hrArr.ToString("X8") + " ptr=" + arr);
        if (hrArr != 0 || arr == IntPtr.Zero) { Console.WriteLine("FAIL array"); return 2; }

        Guid clsid = new Guid("a9c1e4f7-6d2b-4c8a-9e3f-7b1d2c4e5a60");
        Guid iid = new Guid("a08ce4d0-fa25-44ab-b57c-c7b1c323e0b9");
        IntPtr pUnk;
        int hr = Native.CoCreateInstance(ref clsid, IntPtr.Zero, 1 /*INPROC_SERVER*/, ref iid, out pUnk);
        Console.WriteLine("CoCreateInstance = 0x" + hr.ToString("X8"));
        if (hr != 0) { Console.WriteLine("FAIL cocreate"); return 2; }

        IExplorerCommand ec = (IExplorerCommand)Marshal.GetObjectForIUnknown(pUnk);
        Marshal.Release(pUnk);

        uint state; int hrS;
        hrS = ec.GetState(arr, true, out state);
        string txt = state == 0 ? "ENABLED (виден и активен)" :
                     state == 1 ? "DISABLED (СЕРЫЙ!)" :
                     state == 2 ? "HIDDEN (НЕ ВИДЕН!)" : ("неизвестно 0x" + state.ToString("X"));
        Console.WriteLine("GetState(multi)  = hr 0x" + hrS.ToString("X8") + "  state=" + state + " -> " + txt);

        IntPtr ps; int hrT = ec.GetTitle(arr, out ps);
        string title = ps != IntPtr.Zero ? Marshal.PtrToStringUni(ps) : "";
        if (ps != IntPtr.Zero) Marshal.FreeCoTaskMem(ps);
        Console.WriteLine("GetTitle(multi)  = hr 0x" + hrT.ToString("X8") + "  title=[" + title + "]");

        uint st2; ec.GetState(IntPtr.Zero, true, out st2);
        Console.WriteLine("GetState(single) = state=" + st2);

        uint fl; ec.GetFlags(out fl);
        Console.WriteLine("GetFlags         = flags=0x" + fl.ToString("X"));

        // классический путь: QI IContextMenu (IID {000214E4-...})
        Guid iidIcm = new Guid("000214E4-0000-0000-C000-000000000046");
        IntPtr pIcm;
        int hrIcm = Native.CoCreateInstance(ref clsid, IntPtr.Zero, 1, ref iidIcm, out pIcm);
        Console.WriteLine("QI IContextMenu  = 0x" + hrIcm.ToString("X8"));
        if (pIcm != IntPtr.Zero) Marshal.Release(pIcm);

        Native.CoTaskMemFree(arr);

        bool pass = (state == 0) && title.IndexOf("Архивировать", StringComparison.Ordinal) >= 0;
        Console.WriteLine(pass
            ? "PASS: multi-select -> пункт ВИДЕН и АКТИВЕН"
            : "FAIL: state=" + state + " title=[" + title + "]");
        return pass ? 0 : 1;
    }
}
