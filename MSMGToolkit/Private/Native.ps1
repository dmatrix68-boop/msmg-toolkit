# ---------------------------------------------------------------------------------------------
# Native helpers (compiled on first use only, so importing the module stays cheap)
#  - Token privileges (needed to take ownership of protected offline registry keys)
#  - IStream -> file writer (needed for the IMAPI2 ISO fallback)
# ---------------------------------------------------------------------------------------------

$script:TkNativeSource = @'
using System;
using System.IO;
using System.Runtime.InteropServices;
using System.Runtime.InteropServices.ComTypes;

namespace MsmgToolkitPS
{
    public static class TokenPrivilege
    {
        [StructLayout(LayoutKind.Sequential)]
        private struct LUID { public uint LowPart; public int HighPart; }

        [StructLayout(LayoutKind.Sequential)]
        private struct TOKEN_PRIVILEGES { public uint PrivilegeCount; public LUID Luid; public uint Attributes; }

        [DllImport("advapi32.dll", SetLastError = true)]
        private static extern bool OpenProcessToken(IntPtr processHandle, uint desiredAccess, out IntPtr tokenHandle);

        [DllImport("advapi32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
        private static extern bool LookupPrivilegeValue(string systemName, string name, out LUID luid);

        [DllImport("advapi32.dll", SetLastError = true)]
        private static extern bool AdjustTokenPrivileges(IntPtr tokenHandle, bool disableAll, ref TOKEN_PRIVILEGES newState,
            uint bufferLength, IntPtr previousState, IntPtr returnLength);

        [DllImport("kernel32.dll")]
        private static extern IntPtr GetCurrentProcess();

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool CloseHandle(IntPtr handle);

        private const uint TOKEN_ADJUST_PRIVILEGES = 0x0020;
        private const uint TOKEN_QUERY = 0x0008;
        private const uint SE_PRIVILEGE_ENABLED = 0x0002;

        public static bool Enable(string privilege)
        {
            IntPtr token;
            if (!OpenProcessToken(GetCurrentProcess(), TOKEN_ADJUST_PRIVILEGES | TOKEN_QUERY, out token)) return false;
            try
            {
                LUID luid;
                if (!LookupPrivilegeValue(null, privilege, out luid)) return false;
                TOKEN_PRIVILEGES tp = new TOKEN_PRIVILEGES { PrivilegeCount = 1, Luid = luid, Attributes = SE_PRIVILEGE_ENABLED };
                if (!AdjustTokenPrivileges(token, false, ref tp, 0, IntPtr.Zero, IntPtr.Zero)) return false;
                return Marshal.GetLastWin32Error() == 0;
            }
            finally
            {
                CloseHandle(token);
            }
        }
    }

    public static class BackupRegistry
    {
        [DllImport("advapi32.dll", CharSet = CharSet.Unicode)]
        private static extern int RegCreateKeyEx(IntPtr hKey, string subKey, int reserved, string lpClass, int options,
            int samDesired, IntPtr securityAttributes, out IntPtr result, out int disposition);

        private const int REG_OPTION_BACKUP_RESTORE = 0x4;
        private const int KEY_ALL_ACCESS = 0xF003F;

        // Opens/creates a key below HKEY_LOCAL_MACHINE ignoring its ACL (requires SeBackup/SeRestore privilege).
        // Used for keys owned by TrustedInstaller in offline hives - the ACL of the key stays unchanged.
        public static Microsoft.Win32.RegistryKey CreateKey(string subKey)
        {
            IntPtr hklm = new IntPtr(unchecked((int)0x80000002));
            IntPtr handle;
            int disposition;
            int rc = RegCreateKeyEx(hklm, subKey, 0, null, REG_OPTION_BACKUP_RESTORE, KEY_ALL_ACCESS, IntPtr.Zero, out handle, out disposition);
            if (rc != 0) throw new System.ComponentModel.Win32Exception(rc);
            return Microsoft.Win32.RegistryKey.FromHandle(new Microsoft.Win32.SafeHandles.SafeRegistryHandle(handle, true));
        }
    }

    public static class ComStreamWriter
    {
        public static long WriteToFile(object comStream, string path)
        {
            IStream stream = (IStream)comStream;
            byte[] buffer = new byte[1024 * 1024];
            IntPtr bytesRead = Marshal.AllocHGlobal(sizeof(int));
            long total = 0;
            try
            {
                using (FileStream file = new FileStream(path, FileMode.Create, FileAccess.Write, FileShare.None))
                {
                    while (true)
                    {
                        Marshal.WriteInt32(bytesRead, 0);
                        stream.Read(buffer, buffer.Length, bytesRead);
                        int read = Marshal.ReadInt32(bytesRead);
                        if (read <= 0) break;
                        file.Write(buffer, 0, read);
                        total += read;
                    }
                }
            }
            finally
            {
                Marshal.FreeHGlobal(bytesRead);
            }
            return total;
        }
    }
}
'@

function Initialize-TkNative {
    [CmdletBinding()]
    param()
    if (-not ('MsmgToolkitPS.TokenPrivilege' -as [type])) {
        Add-Type -TypeDefinition $script:TkNativeSource -Language CSharp
    }
}

function Enable-TkPrivilege {
    [CmdletBinding()]
    param(
        [string[]]$Name = @('SeTakeOwnershipPrivilege', 'SeRestorePrivilege', 'SeBackupPrivilege')
    )
    Initialize-TkNative
    foreach ($privilege in $Name) {
        if (-not [MsmgToolkitPS.TokenPrivilege]::Enable($privilege)) {
            throw "Could not enable privilege '$privilege'. Is the toolkit running as Administrator?"
        }
    }
}
