using System;
using System.Runtime.InteropServices;
public static class Test {
  [DllImport("ole32.dll")]
  public static extern int CoInitialize(IntPtr p);
  [DllImport("ole32.dll")]
  public static extern void CoUninitialize();
  [DllImport("ole32.dll")]
  public static extern int CoCreateInstance(ref Guid clsid, IntPtr pUnk, uint dwClsContext, ref Guid iid, out IntPtr p);
  [Guid("a9c1e4f7-6d2b-4c8a-9e3f-7b1d2c4e5a60")]
  public struct CLSID {}
  [Guid("000214e2-0000-0000-c000-000000000046")]
  public struct IUnknown {}
}
public static class Program {
  public static void Main() {
    int hr = Test.CoInitialize(IntPtr.Zero);
    Console.WriteLine("CoInitialize=0x" + hr.ToString("x8"));
    Guid clsid = new Guid("a9c1e4f7-6d2b-4c8a-9e3f-7b1d2c4e5a60");
    Guid iid = new Guid("000214e2-0000-0000-c000-000000000046");
    IntPtr ptr;
    int hr2 = Test.CoCreateInstance(ref clsid, IntPtr.Zero, 1, ref iid, out ptr);
    Console.WriteLine("CoCreateInstance=0x" + hr2.ToString("x8") + " ptr=" + ptr);
    Test.CoUninitialize();
  }
}