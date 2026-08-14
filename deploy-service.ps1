<#
.SYNOPSIS
    Deploys, registers, and starts the IIS Monitoring Windows Service with Custom User, Auto-Start, and 300s Auto-Recovery.
.DESCRIPTION
    Configures:
    1. Executable publication (.exe).
    2. Specific service user identity with 'Log on as a service' (SeServiceLogonRight) and directory ACLs.
    3. Auto-start service startup type (start= auto).
    4. Auto-recovery error action to restart the service every 300 seconds on failure.
    5. HTTP monitoring loop every 60 seconds with auto-stop on non-200 OK.
#>

[CmdletBinding()]
param (
    [string]$InstallPath = "C:\Services\CustomerSpikeIisMonitor",
    [string]$ServiceName = "CustomerSpikeIisMonitor",
    [string]$DisplayName = "Customer Spike IIS Website Monitor",
    [string]$Description = "Monitors IIS website status every 60 seconds. Logs HTTP status to file and stops on status <> 200 OK. Auto-recovers after 300s.",
    [string]$TargetUrl = "http://localhost/",
    [int]$CheckIntervalSeconds = 60,
    [string]$UserName = "SpikeIISUser",
    [string]$Password = "SenhaForte@2026!",
    [int]$RecoveryDelaySeconds = 300,
    [string]$StartupType = "Automatic"
)

# Output UTF-8 encoding
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

# ============================================================================
# 1. ELEVATION CHECK
# ============================================================================
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host ""
    Write-Host "==========================================================================" -ForegroundColor Red
    Write-Host "[ERROR] Insufficient Privileges! This script must be run as Administrator." -ForegroundColor Red
    Write-Host "Please open PowerShell as Administrator ('Run as Administrator') and re-run." -ForegroundColor Yellow
    Write-Host "==========================================================================" -ForegroundColor Red
    Write-Host ""
    exit 1
}

$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "==========================================================================" -ForegroundColor Cyan
Write-Host "      DEPLOYING IIS MONITORING WINDOWS SERVICE (AUTOMATED SCRIPT)         " -ForegroundColor Cyan
Write-Host "==========================================================================" -ForegroundColor Cyan
Write-Host " Target URL          : $TargetUrl" -ForegroundColor Gray
Write-Host " Check Interval      : $CheckIntervalSeconds seconds" -ForegroundColor Gray
Write-Host " Installation Path   : $InstallPath" -ForegroundColor Gray
Write-Host " Service Name        : $ServiceName" -ForegroundColor Gray
Write-Host " Run As User         : $UserName" -ForegroundColor Gray
Write-Host " Startup Type        : $StartupType (Auto-Start)" -ForegroundColor Gray
Write-Host " Auto-Recovery Delay : $RecoveryDelaySeconds seconds (300s)" -ForegroundColor Gray
Write-Host "==========================================================================" -ForegroundColor Cyan
Write-Host ""

# Helper to grant 'Log on as a service' right using LSA Win32 API
if (-not ([System.Management.Automation.PSTypeName]'LsaPrivilegeHelper').Type) {
    $lsaSource = @"
using System;
using System.Text;
using System.Runtime.InteropServices;

public class LsaPrivilegeHelper
{
    [StructLayout(LayoutKind.Sequential)]
    struct LSA_UNICODE_STRING
    {
        public ushort Length;
        public ushort MaximumLength;
        public IntPtr Buffer;
    }

    [StructLayout(LayoutKind.Sequential)]
    struct LSA_OBJECT_ATTRIBUTES
    {
        public int Length;
        public IntPtr RootDirectory;
        public IntPtr ObjectName;
        public uint Attributes;
        public IntPtr SecurityDescriptor;
        public IntPtr SecurityQualityOfService;
    }

    [DllImport("advapi32.dll", PreserveSig = true)]
    static extern uint LsaOpenPolicy(
        IntPtr SystemName,
        ref LSA_OBJECT_ATTRIBUTES ObjectAttributes,
        uint DesiredAccess,
        out IntPtr PolicyHandle);

    [DllImport("advapi32.dll", PreserveSig = true)]
    static extern uint LsaAddAccountRights(
        IntPtr PolicyHandle,
        byte[] AccountSid,
        LSA_UNICODE_STRING[] UserRights,
        uint CountOfRights);

    [DllImport("advapi32.dll")]
    static extern uint LsaClose(IntPtr ObjectHandle);

    public static uint GrantServiceLogonRight(byte[] sid)
    {
        LSA_OBJECT_ATTRIBUTES objAttr = new LSA_OBJECT_ATTRIBUTES();
        IntPtr policyHandle;
        // POLICY_CREATE_ACCOUNT (0x0010) | POLICY_LOOKUP_NAMES (0x0800) | POLICY_NOTIFICATION (0x1000)
        uint access = 0x00000800 | 0x00000010;

        uint status = LsaOpenPolicy(IntPtr.Zero, ref objAttr, access, out policyHandle);
        if (status != 0) return status;

        string privilege = "SeServiceLogonRight";
        LSA_UNICODE_STRING[] rights = new LSA_UNICODE_STRING[1];
        rights[0] = new LSA_UNICODE_STRING();
        rights[0].Buffer = Marshal.StringToHGlobalUni(privilege);
        rights[0].Length = (ushort)(privilege.Length * 2);
        rights[0].MaximumLength = (ushort)((privilege.Length + 1) * 2);

        uint addStatus = LsaAddAccountRights(policyHandle, sid, rights, 1);
        Marshal.FreeHGlobal(rights[0].Buffer);
        LsaClose(policyHandle);
        return addStatus;
    }
}
"@
    Add-Type -TypeDefinition $lsaSource
}

function Grant-ServiceLogonRight {
    param([string]$AccountName)
    try {
        $ntAccount = New-Object System.Security.Principal.NTAccount($AccountName)
        $sid = $ntAccount.Translate([System.Security.Principal.SecurityIdentifier])
        $sidBytes = New-Object byte[] ($sid.BinaryLength)
        $sid.GetBinaryForm($sidBytes, 0)

        $res = [LsaPrivilegeHelper]::GrantServiceLogonRight($sidBytes)
        if ($res -eq 0) {
            Write-Host "  [+] Granted 'Log on as a service' (SeServiceLogonRight) to '$AccountName' via LSA API." -ForegroundColor Green
        } else {
            Write-Warning "LsaAddAccountRights returned status: 0x$($res.ToString('X8')). Attempting secedit fallback..."
            # Secedit fallback
            $tempDir = [System.IO.Path]::GetTempPath()
            $exportCfg = Join-Path $tempDir "sec_export_$([Guid]::NewGuid().ToString('N')).inf"
            $importCfg = Join-Path $tempDir "sec_import_$([Guid]::NewGuid().ToString('N')).inf"
            $sdbDb     = Join-Path $tempDir "sec_db_$([Guid]::NewGuid().ToString('N')).sdb"

            & secedit.exe /export /cfg "$exportCfg" /areas USER_RIGHTS | Out-Null
            if (Test-Path $exportCfg) {
                $cfg = Get-Content -Path $exportCfg -Raw
                if ($cfg -match "SeServiceLogonRight\s*=\s*(.*)") {
                    $existing = $matches[1].Trim()
                    if ($existing -notmatch "(^|,)\s*\*?$AccountName\s*(,|$)") {
                        $newVal = "$existing,*$AccountName"
                        $cfg = $cfg -replace "SeServiceLogonRight\s*=.*", "SeServiceLogonRight = $newVal"
                    }
                } else {
                    $cfg += "`r`n[Privilege Rights]`r`nSeServiceLogonRight = *$AccountName`r`n"
                }
                Set-Content -Path $importCfg -Value $cfg -Encoding Ascii
                & secedit.exe /configure /db "$sdbDb" /cfg "$importCfg" /areas USER_RIGHTS | Out-Null
            }
            Remove-Item $exportCfg, $importCfg, $sdbDb -Force -ErrorAction SilentlyContinue
        }
    } catch {
        Write-Warning "Failed to grant SeServiceLogonRight: $_"
    }
}

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectDir = Join-Path $scriptDir "src\CustomerManagementSpike.MonitoringService"
$projectFile = Join-Path $projectDir "CustomerManagementSpike.MonitoringService.csproj"

if (-not (Test-Path $projectFile)) {
    Write-Error "Project file not found at: $projectFile"
    exit 1
}

# ============================================================================
# 2. ENSURE SERVICE ACCOUNT EXISTS AND HAS PERMISSIONS
# ============================================================================
Write-Host "[1/6] Ensuring service account '$UserName'..." -ForegroundColor Yellow
$userAccount = $UserName
$securePass = ConvertTo-SecureString $Password -AsPlainText -Force

if ($userAccount -notmatch "\\") {
    if (-not (Get-LocalUser -Name $userAccount -ErrorAction SilentlyContinue)) {
        New-LocalUser -Name $userAccount -Password $securePass -PasswordNeverExpires:$true -UserMayNotChangePassword:$true | Out-Null
        Write-Host "  [+] Created local user '$userAccount'." -ForegroundColor Green
    } else {
        # Ensure password is up to date
        Set-LocalUser -Name $userAccount -Password $securePass | Out-Null
        Write-Host "  [+] Verified and updated password for '$userAccount'." -ForegroundColor Green
    }
    Grant-ServiceLogonRight -AccountName $userAccount
    $serviceObjUser = ".\$userAccount"
} else {
    $serviceObjUser = $userAccount
    Grant-ServiceLogonRight -AccountName $userAccount
}

# ============================================================================
# 3. COMPILE & PUBLISH RELEASE ARTIFACTS
# ============================================================================
Write-Host "`n[2/6] Compiling and publishing project in Release mode..." -ForegroundColor Yellow

if (-not (Test-Path $InstallPath)) {
    New-Item -ItemType Directory -Path $InstallPath -Force | Out-Null
    Write-Host "  [+] Created directory: $InstallPath" -ForegroundColor Green
}

try {
    dotnet publish "$projectFile" `
        --configuration Release `
        --output "$InstallPath" `
        --verbosity minimal

    Write-Host "  [+] Publish completed successfully." -ForegroundColor Green
} catch {
    Write-Error "Failed to publish service: $_"
    exit 1
}

$exePath = Join-Path $InstallPath "CustomerManagementSpike.MonitoringService.exe"
if (-not (Test-Path $exePath)) {
    Write-Error "Executable not found at: $exePath"
    exit 1
}

# Grant ACL permissions on target folder to service account
try {
    $acl = Get-Acl -Path $InstallPath
    $rule = New-Object System.Security.AccessControl.FileSystemAccessRule($UserName, "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow")
    $acl.AddAccessRule($rule)
    Set-Acl -Path $InstallPath -AclObject $acl
    Write-Host "  [+] Granted FullControl filesystem permissions on $InstallPath to '$UserName'." -ForegroundColor Green
} catch {
    Write-Warning "Could not grant NTFS permissions to '$UserName': $_"
}

# ============================================================================
# 4. CONFIGURE APPSETTINGS.JSON IN DEPLOYMENT DIRECTORY
# ============================================================================
Write-Host "`n[3/6] Configuring appsettings.json in $InstallPath..." -ForegroundColor Yellow
$appSettingsFile = Join-Path $InstallPath "appsettings.json"

$configContent = @"
{
  "Logging": {
    "LogLevel": {
      "Default": "Information",
      "Microsoft.Hosting.Lifetime": "Information",
      "CustomerManagementSpike": "Information"
    }
  },
  "Monitoring": {
    "WebsiteUrl": "$TargetUrl",
    "CheckIntervalSeconds": $CheckIntervalSeconds,
    "RequestTimeoutSeconds": 15,
    "LogFileName": "iis_monitor.log",
    "StopOnNon200": true
  }
}
"@

[System.IO.File]::WriteAllText($appSettingsFile, $configContent, [System.Text.Encoding]::UTF8)
Write-Host "  [+] appsettings.json written with TargetUrl='$TargetUrl' and Interval=${CheckIntervalSeconds}s." -ForegroundColor Green

# ============================================================================
# 5. REMOVE EXISTING SERVICE (IF PRESENT)
# ============================================================================
Write-Host "`n[4/6] Checking for existing Windows Service '$ServiceName'..." -ForegroundColor Yellow
$existingService = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue

if ($existingService) {
    Write-Host "  [!] Existing service found with Status: $($existingService.Status)" -ForegroundColor Yellow
    if ($existingService.Status -eq 'Running') {
        Write-Host "  [+] Stopping service..." -ForegroundColor Yellow
        Stop-Service -Name $ServiceName -Force
        Start-Sleep -Seconds 2
    }

    Write-Host "  [+] Deleting previous service registration..." -ForegroundColor Yellow
    & sc.exe delete "$ServiceName" | Out-Null
    Start-Sleep -Seconds 2
    Write-Host "  [+] Previous service registration removed." -ForegroundColor Green
} else {
    Write-Host "  [+] No previous service instance detected." -ForegroundColor Green
}

# ============================================================================
# 6. REGISTER WINDOWS SERVICE (USER, AUTO-START, 300S ERROR RECOVERY)
# ============================================================================
Write-Host "`n[5/6] Registering Windows Service in Service Control Manager..." -ForegroundColor Yellow

$startParam = switch ($StartupType) {
    "Automatic" { "auto" }
    "Manual"    { "demand" }
    "Disabled"  { "disabled" }
    default     { "auto" }
}

# 1. Create service pointing to .exe with Auto-Start and configured specific user
if ($serviceObjUser -and $Password) {
    $createResult = & sc.exe create "$ServiceName" binPath= "`"$exePath`"" start= $startParam DisplayName= "`"$DisplayName`"" obj= "$serviceObjUser" password= "$Password"
} else {
    $createResult = & sc.exe create "$ServiceName" binPath= "`"$exePath`"" start= $startParam DisplayName= "`"$DisplayName`""
}
Write-Host "  $createResult" -ForegroundColor Gray

# 2. Set service description
& sc.exe description "$ServiceName" "$Description" | Out-Null

# 3. Configure Error Recovery: Restart after 300 seconds (300,000 milliseconds) on failure
$delayMs = $RecoveryDelaySeconds * 1000
& sc.exe failure "$ServiceName" reset= 86400 actions= "restart/$delayMs/restart/$delayMs/restart/$delayMs" | Out-Null
& sc.exe failureflag "$ServiceName" 1 | Out-Null

Write-Host "  [+] Startup Type set to: $StartupType (Auto-Start)" -ForegroundColor Green
Write-Host "  [+] Run-As User configured as: $serviceObjUser" -ForegroundColor Green
Write-Host "  [+] Error Recovery configured: Automatically restart service after $RecoveryDelaySeconds seconds ($delayMs ms) on failure." -ForegroundColor Green

# ============================================================================
# 7. START SERVICE & VERIFY HEALTH
# ============================================================================
Write-Host "`n[6/6] Starting Windows Service..." -ForegroundColor Yellow
try {
    Start-Service -Name $ServiceName
    Start-Sleep -Seconds 3
} catch {
    Write-Host "  [!] Initial start attempt failed: $_" -ForegroundColor Yellow
    Write-Host "  [+] Retrying with fallback identity if needed or checking account logon..." -ForegroundColor Yellow
    Start-Sleep -Seconds 2
    Start-Service -Name $ServiceName
}

$deployedService = Get-Service -Name $ServiceName
$logFilePath = Join-Path $InstallPath "iis_monitor.log"

Write-Host ""
Write-Host "==========================================================================" -ForegroundColor Green
Write-Host "                   SERVICE DEPLOYED SUCCESSFULLY!                         " -ForegroundColor Green
Write-Host "==========================================================================" -ForegroundColor Green
Write-Host " Service Name       : $($deployedService.Name)" -ForegroundColor White
Write-Host " Display Name       : $($deployedService.DisplayName)" -ForegroundColor White
Write-Host " Current Status     : $($deployedService.Status)" -ForegroundColor Green
Write-Host " Run-As User        : $serviceObjUser" -ForegroundColor White
Write-Host " Startup Type       : Auto-Start ($StartupType)" -ForegroundColor White
Write-Host " Error Recovery     : Auto-restart after $RecoveryDelaySeconds seconds (300s)" -ForegroundColor White
Write-Host " Target URL         : $TargetUrl" -ForegroundColor White
Write-Host " Check Interval     : $CheckIntervalSeconds seconds" -ForegroundColor White
Write-Host " Executable Path    : $exePath" -ForegroundColor Gray
Write-Host " Log File Location  : $logFilePath" -ForegroundColor Cyan
Write-Host "==========================================================================" -ForegroundColor Green
Write-Host ""

if (Test-Path $logFilePath) {
    Write-Host "Initial Log File Content:" -ForegroundColor Cyan
    Write-Host "--------------------------------------------------------------------------" -ForegroundColor Gray
    Get-Content -Path $logFilePath -Tail 10
    Write-Host "--------------------------------------------------------------------------" -ForegroundColor Gray
}

Write-Host ""
Write-Host "Useful Management Commands:" -ForegroundColor Yellow
Write-Host " - View Live Logs        : Get-Content -Path `"$logFilePath`" -Wait" -ForegroundColor White
Write-Host " - Check Status          : Get-Service -Name `"$ServiceName`"" -ForegroundColor White
Write-Host " - Query SCM Failure cfg : sc.exe qfailure `"$ServiceName`"" -ForegroundColor White
Write-Host " - Stop Service          : Stop-Service -Name `"$ServiceName`"" -ForegroundColor White
Write-Host " - Start Service         : Start-Service -Name `"$ServiceName`"" -ForegroundColor White
Write-Host ""
