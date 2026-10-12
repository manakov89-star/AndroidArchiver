using System;
using System.Runtime.InteropServices;
public static class PInvoke {
  [DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
  public static extern IntPtr LoadLibrary(string name);
  [DllImport("kernel32.dll")]
  public static extern IntPtr GetProcAddress(IntPtr hModule, string lpProcName);
  [DllImport("kernel32.dll")]
  public static extern bool FreeLibrary(IntPtr hModule);
}
public static class Program {
  public static void Main() {
    IntPtr h = PInvoke.LoadLibrary("C:\\projects\\AndroidArchiver\\AndroidArchiveCmd.dll");
    Console.WriteLine("LoadLibrary=0x" + h.ToString("x8"));
    if (h != IntPtr.Zero) {
      foreach (var n in new[] {"DllGetClassObject","DllCanUnloadNow","DllRegisterServer","DllUnregisterServer"}) {
        IntPtr p = PInvoke.GetProcAddress(h, n);
        Console.WriteLine("  " + n + "=0x" + p.ToString("x8"));
      }
      PInvoke.FreeLibrary(h);
    }
  }
}