// Расширение контекстного меню Windows для упаковки проекта Android в ZIP.
// На одном COM-объекте реализованы два способа показа пункта:
//   1) IExplorerCommand  -> НОВОЕ контекстное меню Windows 11 (рядом с WinRAR,
//      без "Показать дополнительные параметры"). Показывается только расширениям
//      с package identity, поэтому CLSID объявлен в sparse-MSIX пакете
//      (AppxManifest.xml -> windows.fileExplorerContextMenus).
//   2) IShellExtInit + IContextMenu -> классическое меню ("Показать дополнительные
//      параметры"), включая несколько выделенных файлов/папок (через CF_HDROP).
// Так же построен RarExt.dll от WinRAR (проверено: поддерживает все три интерфейса).
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>
#include <shobjidl.h>
#include <shobjidl_core.h>
#include <shlobj.h>
#include <shellapi.h>
#include <objbase.h>
#include <string>
#include <vector>
#include <new>

#pragma comment(lib, "ole32.lib")
#pragma comment(lib, "user32.lib")
#pragma comment(lib, "shell32.lib")

#ifndef CMF_DEFAULTONLY
#define CMF_DEFAULTONLY 0x00000001
#endif
#ifndef GCS_VALIDATEA
#define GCS_VALIDATEA 0
#define GCS_VERBA     1
#define GCS_HELPTEXTA 2
#define GCS_VALIDATEW 4
#define GCS_VERBW     5
#define GCS_HELPTEXTW 6
#endif

static const GUID kCLSID_ArchiveCmd =
    { 0xa9c1e4f7, 0x6d2b, 0x4c8a, { 0x9e, 0x3f, 0x7b, 0x1d, 0x2c, 0x4e, 0x5a, 0x60 } };

static const wchar_t* kScriptPath = L"C:\\projects\\AndroidArchiver\\Archive-Android.ps1";

static const wchar_t* kMenuTitle = L"Архивировать проект (без сборки)";
static const wchar_t* kTooltip   = L"Упаковать исходники в ZIP, исключив сборочные файлы, кэши и мусор";
static const wchar_t* kVerbNameW = L"AndroidArchive";
static const char*    kVerbNameA = "AndroidArchive";

// В SDK 10.0.26100 enum _EXPCMDSTATE: ECS_ENABLED=0, ECS_DISABLED=1, ECS_HIDDEN=2.
// Ранее здесь стоял самодельный "ECS_VISIBLE=1", что на самом деле ECS_DISABLED -
// пункт выходил серым/неактивным. Видимый и рабочий пункт = ECS_ENABLED (0).
#ifndef ECS_ENABLED
#define ECS_ENABLED 0x00000000
#endif

static HRESULT DupStr(const wchar_t* s, LPWSTR* out)
{
    if (!out) return E_POINTER;
    SIZE_T len = (lstrlenW(s) + 1) * sizeof(wchar_t);
    wchar_t* buf = (wchar_t*)CoTaskMemAlloc(len);
    if (!buf) return E_OUTOFMEMORY;
    memcpy(buf, s, len);
    *out = buf;
    return S_OK;
}

// Все выбранные пути из IShellItemArray (новое меню Windows 11).
static std::vector<std::wstring> GetSelectedPaths(IShellItemArray* pArray)
{
    std::vector<std::wstring> out;
    if (!pArray) return out;

    DWORD count = 0;
    if (FAILED(pArray->GetCount(&count)) || count == 0 || count > 100000) return out;

    for (DWORD i = 0; i < count; i++)
    {
        IShellItem* pItem = nullptr;
        if (FAILED(pArray->GetItemAt(i, &pItem)) || !pItem) continue;

        PWSTR pszPath = nullptr;
        if (SUCCEEDED(pItem->GetDisplayName(SIGDN_FILESYSPATH, &pszPath)) && pszPath)
        {
            if (pszPath[0]) out.push_back(pszPath);
            CoTaskMemFree(pszPath);
        }
        pItem->Release();
    }
    return out;
}

// Запуск архиватора: каждый путь целиком в кавычках (пути содержат пробелы).
static bool LaunchPowerShell(const std::vector<std::wstring>& paths)
{
    if (paths.empty()) return false;

    std::wstring quoted;
    quoted.reserve(paths.size() * 64 + 64);
    for (size_t i = 0; i < paths.size(); i++)
    {
        if (paths[i].empty()) continue;
        // Пробел МЕЖДУ путями обязателен: иначе PowerShell сольёт
        // "p1""p2" в один аргумент "p1p2" и скрипт не найдёт ни один путь.
        if (!quoted.empty()) quoted += L' ';
        quoted += L'"';
        for (size_t j = 0; j < paths[i].size(); j++)
        {
            if (paths[i][j] == L'"') continue;   // кавычки в путях не поддерживаем
            quoted += paths[i][j];
        }
        quoted += L'"';
    }
    if (quoted.empty()) return false;

    // полный путь к powershell: с lpApplicationName система НЕ ищет в PATH
    wchar_t sysdir[MAX_PATH];
    if (!GetSystemDirectoryW(sysdir, MAX_PATH)) return false;
    std::wstring exe = std::wstring(sysdir) + L"\\WindowsPowerShell\\v1.0\\powershell.exe";

    std::wstring cmd;
    cmd.reserve(quoted.size() + 300);
    cmd += L"-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -STA -File \"";
    cmd += kScriptPath;
    cmd += L"\" ";
    cmd += quoted;   // пути позиционные: -Path можно указать только один раз

    std::vector<wchar_t> buf(cmd.begin(), cmd.end());
    buf.push_back(L'\0');

    STARTUPINFOW si;
    ZeroMemory(&si, sizeof(si));
    si.cb = sizeof(si);
    si.dwFlags = STARTF_USESHOWWINDOW;
    si.wShowWindow = SW_HIDE;
    PROCESS_INFORMATION pi;
    ZeroMemory(&pi, sizeof(pi));

    if (CreateProcessW(exe.c_str(), buf.data(), NULL, NULL, FALSE,
                       CREATE_NO_WINDOW, NULL, NULL, &si, &pi))
    {
        CloseHandle(pi.hThread);
        CloseHandle(pi.hProcess);
        return true;
    }
    return false;
}

class CArchiveCommand : public IExplorerCommand, public IShellExtInit, public IContextMenu
{
public:
    // QueryInterface/AddRef/Release реализуют все три базовых интерфейса:
    // одинаковая сигнатура -> один набор методов перекрывает их все.
    IFACEMETHODIMP QueryInterface(REFIID riid, void** ppv)
    {
        if (!ppv) return E_POINTER;
        *ppv = NULL;
        if (IsEqualIID(riid, IID_IUnknown) ||
            IsEqualIID(riid, __uuidof(IExplorerCommand)) ||
            IsEqualIID(riid, kCLSID_ArchiveCmd))
        {
            *ppv = static_cast<IExplorerCommand*>(this);
        }
        else if (IsEqualIID(riid, __uuidof(IShellExtInit)))
        {
            *ppv = static_cast<IShellExtInit*>(this);
        }
        else if (IsEqualIID(riid, __uuidof(IContextMenu)))
        {
            *ppv = static_cast<IContextMenu*>(this);
        }
        else
        {
            return E_NOINTERFACE;
        }
        AddRef();
        return S_OK;
    }

    IFACEMETHODIMP_(ULONG) AddRef() { return InterlockedIncrement(&m_ref); }

    IFACEMETHODIMP_(ULONG) Release()
    {
        ULONG n = InterlockedDecrement(&m_ref);
        if (n == 0) delete this;
        return n;
    }

    // ---------------- IExplorerCommand: новое меню Windows 11 ----------------

    IFACEMETHODIMP GetTitle(IShellItemArray* pArray, LPWSTR* ppszName) override
    { return DupStr(kMenuTitle, ppszName); }

    IFACEMETHODIMP GetIcon(IShellItemArray* pArray, LPWSTR* ppszIcon) override
    {
        // новый меню Win11 не раскрывает переменные окружения - отдаём полный путь
        wchar_t sysdir[MAX_PATH];
        if (!GetSystemDirectoryW(sysdir, MAX_PATH)) return E_FAIL;
        std::wstring icon(sysdir);
        icon += L"\\imageres.dll,-102";
        return DupStr(icon.c_str(), ppszIcon);
    }

    IFACEMETHODIMP GetToolTip(IShellItemArray* pArray, LPWSTR* ppszTip) override
    { return DupStr(kTooltip, ppszTip); }

    IFACEMETHODIMP GetCanonicalName(GUID* pguid) override
    {
        if (!pguid) return E_POINTER;
        *pguid = kCLSID_ArchiveCmd;
        return S_OK;
    }

    IFACEMETHODIMP GetState(IShellItemArray* pArray, BOOL fOkToBeSlow, EXPCMDSTATE* pState) override
    {
        if (!pState) return E_POINTER;
        *pState = ECS_ENABLED;   // виден и активен, без Shift/Ctrl
        return S_OK;
    }

    IFACEMETHODIMP Invoke(IShellItemArray* pArray, IBindCtx* pbc) override
    {
        LaunchPowerShell(GetSelectedPaths(pArray));
        return S_OK;
    }

    IFACEMETHODIMP GetFlags(EXPCMDFLAGS* pFlags) override
    {
        if (!pFlags) return E_POINTER;
        *pFlags = ECF_DEFAULT;   // пункт виден всегда
        return S_OK;
    }

    IFACEMETHODIMP EnumSubCommands(IEnumExplorerCommand** ppEnum) override
    {
        if (ppEnum) *ppEnum = NULL;
        return E_NOTIMPL;   // подменю нет
    }

    // ---------------- IShellExtInit: получение выбранных объектов ----------------

    IFACEMETHODIMP Initialize(PCIDLIST_ABSOLUTE pidlFolder, IDataObject* pdtObj,
                              HKEY hkeyProgID) override
    {
        (void)pidlFolder;
        (void)hkeyProgID;
        m_paths.clear();
        if (!pdtObj) return E_INVALIDARG;

        FORMATETC fe = { CF_HDROP, NULL, DVASPECT_CONTENT, -1, TYMED_HGLOBAL };
        STGMEDIUM stm = { TYMED_HGLOBAL, { 0 }, NULL };
        HRESULT hr = pdtObj->GetData(&fe, &stm);
        if (FAILED(hr) || !stm.hGlobal) return hr;

        HDROP hdrop = (HDROP)GlobalLock(stm.hGlobal);
        if (hdrop)
        {
            UINT n = DragQueryFileW(hdrop, 0xFFFFFFFF, NULL, 0);
            if (n > 100000) n = 100000;
            for (UINT i = 0; i < n; i++)
            {
                UINT len = DragQueryFileW(hdrop, i, NULL, 0);
                if (len == 0 || len > 32767) continue;
                std::wstring buf(len + 1, L'\0');
                UINT got = DragQueryFileW(hdrop, i, &buf[0], len + 1);
                if (got == 0) continue;
                buf.resize(got);
                if (buf[0]) m_paths.push_back(buf);
            }
            GlobalUnlock(stm.hGlobal);
        }
        ReleaseStgMedium(&stm);

        // без путей пункт меню не показываем (иначе получится "мёртвая" кнопка)
        return m_paths.empty() ? E_FAIL : S_OK;
    }

    // ---------------- IContextMenu: классическое меню ----------------

    IFACEMETHODIMP QueryContextMenu(HMENU hmenu, UINT indexMenu, UINT idCmdFirst,
                                    UINT idCmdLast, UINT uFlags) override
    {
        if (!hmenu) return E_POINTER;
        if (uFlags & CMF_DEFAULTONLY) return MAKE_HRESULT(SEVERITY_SUCCESS, 0, 0);
        if (m_paths.empty()) return MAKE_HRESULT(SEVERITY_SUCCESS, 0, 0);
        if (idCmdLast < idCmdFirst) return E_INVALIDARG;
        if (idCmdLast - idCmdFirst < 1) return HRESULT_FROM_WIN32(ERROR_INSUFFICIENT_BUFFER);

        if (!InsertMenuW(hmenu, indexMenu, MF_BYPOSITION | MF_STRING, idCmdFirst, kMenuTitle))
            return HRESULT_FROM_WIN32(GetLastError());

        // LOWORD возвращаемого значения = число добавленных пунктов
        return MAKE_HRESULT(SEVERITY_SUCCESS, 0, 1);
    }

    IFACEMETHODIMP InvokeCommand(CMINVOKECOMMANDINFO* pici) override
    {
        if (!pici) return E_POINTER;

        UINT cmd = 0xFFFFFFFF;
        if (IS_INTRESOURCE(pici->lpVerb))
        {
            cmd = (UINT)LOWORD((ULONG_PTR)pici->lpVerb);   // обычный клик по пункту
        }
        else
        {
            bool ours = false;
            if (pici->cbSize >= sizeof(CMINVOKECOMMANDINFOEX))
            {
                CMINVOKECOMMANDINFOEX* ex = reinterpret_cast<CMINVOKECOMMANDINFOEX*>(pici);
                if (ex->lpVerbW && !IS_INTRESOURCE(ex->lpVerbW))
                    ours = (lstrcmpiW(ex->lpVerbW, kVerbNameW) == 0);
            }
            if (!ours && pici->lpVerb)
            {
                ours = (lstrcmpiA(pici->lpVerb, kVerbNameA) == 0 ||
                        lstrcmpA(pici->lpVerb, "0") == 0);
            }
            cmd = ours ? 0 : 0xFFFFFFFF;
        }

        if (cmd != 0) return E_INVALIDARG;   // это не наш пункт
        if (m_paths.empty()) return E_FAIL;

        LaunchPowerShell(m_paths);
        return S_OK;
    }

    IFACEMETHODIMP GetCommandString(UINT_PTR idCmd, UINT uType, UINT* pReserved,
                                    CHAR* pszName, UINT cchMax) override
    {
        (void)pReserved;
        if (idCmd != 0 || !pszName || cchMax == 0) return E_INVALIDARG;

        switch (uType)
        {
        case GCS_VALIDATEA:
        case GCS_VALIDATEW:
            return S_OK;

        case GCS_VERBA:
            lstrcpynA(pszName, kVerbNameA, cchMax);
            return S_OK;

        case GCS_VERBW:
            lstrcpynW(reinterpret_cast<LPWSTR>(pszName), kVerbNameW, cchMax);
            return S_OK;

        case GCS_HELPTEXTA:
        {
            int need = WideCharToMultiByte(CP_ACP, 0, kTooltip, -1, NULL, 0, NULL, NULL);
            if (need <= 0) return E_FAIL;
            WideCharToMultiByte(CP_ACP, 0, kTooltip, -1, pszName,
                                (int)((UINT)need < cchMax ? need : cchMax), NULL, NULL);
            return S_OK;
        }

        case GCS_HELPTEXTW:
            lstrcpynW(reinterpret_cast<LPWSTR>(pszName), kTooltip, cchMax);
            return S_OK;

        default:
            return E_INVALIDARG;
        }
    }

private:
    volatile LONG m_ref = 1;
    std::vector<std::wstring> m_paths;   // заполняется в Initialize (классическое меню)
};

class CArchiveClassFactory : public IClassFactory
{
public:
    IFACEMETHODIMP QueryInterface(REFIID riid, void** ppv)
    {
        if (!ppv) return E_POINTER;
        if (IsEqualIID(riid, IID_IUnknown) || IsEqualIID(riid, IID_IClassFactory))
        {
            *ppv = static_cast<IClassFactory*>(this);
            AddRef();
            return S_OK;
        }
        *ppv = NULL;
        return E_NOINTERFACE;
    }
    IFACEMETHODIMP_(ULONG) AddRef() { return InterlockedIncrement(&m_ref); }
    IFACEMETHODIMP_(ULONG) Release()
    {
        ULONG n = InterlockedDecrement(&m_ref);
        if (n == 0) delete this;
        return n;
    }

    IFACEMETHODIMP CreateInstance(IUnknown* pOuter, REFIID riid, void** ppv) override
    {
        if (!ppv) return E_POINTER;
        *ppv = NULL;
        if (pOuter) return CLASS_E_NOAGGREGATION;

        CArchiveCommand* obj = new (std::nothrow) CArchiveCommand();
        if (!obj) return E_OUTOFMEMORY;
        HRESULT hr = obj->QueryInterface(riid, ppv);
        obj->Release();
        return hr;
    }

    IFACEMETHODIMP LockServer(BOOL fLock) override { return S_OK; }

private:
    volatile LONG m_ref = 1;
};

STDAPI DllGetClassObject(REFCLSID rclsid, REFIID riid, void** ppv)
{
    if (!ppv) return E_POINTER;
    *ppv = NULL;
    if (IsEqualCLSID(rclsid, kCLSID_ArchiveCmd) == FALSE) return CLASS_E_CLASSNOTAVAILABLE;

    CArchiveClassFactory* cf = new (std::nothrow) CArchiveClassFactory();
    if (!cf) return E_OUTOFMEMORY;
    HRESULT hr = cf->QueryInterface(riid, ppv);
    cf->Release();
    return hr;
}

STDAPI DllCanUnloadNow() { return S_FALSE; }
STDAPI DllRegisterServer() { return S_OK; }
STDAPI DllUnregisterServer() { return S_OK; }

BOOL APIENTRY DllMain(HMODULE, DWORD, LPVOID) { return TRUE; }
