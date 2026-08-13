# Output Encoding Configuration for Accented Characters
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

# ==========================================
# ADMINISTRATIVE PRIVILEGE CHECK
# ==========================================
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host ""
    Write-Host "==========================================================================" -ForegroundColor Red
    Write-Host "[ERROR] Insufficient privileges. This script must be run as Administrator!" -ForegroundColor Red
    Write-Host "Please open PowerShell as Administrator ('Run as Administrator') and run the script again." -ForegroundColor Yellow
    Write-Host "==========================================================================" -ForegroundColor Red
    Write-Host ""
    return 1
}

$ErrorActionPreference = "Stop"

# ==========================================
# 0. IIS CHECK AND INSTALLATION
# ==========================================
Write-Host "Checking IIS dependencies..." -ForegroundColor Cyan

$iisFeatures = @(
    "IIS-WebServerRole",
    "IIS-WebServer",
    "IIS-CommonHttpFeatures",
    "IIS-DefaultDocument",
    "IIS-DirectoryBrowsing",
    "IIS-HttpErrors",
    "IIS-StaticContent",
    "IIS-HttpLogging",
    "IIS-RequestFiltering",
    "IIS-ManagementConsole",
    "IIS-ManagementScriptingTools"
)

$iisNeedsInstall = $false
try {
    $scriptingTools = Get-WindowsOptionalFeature -Online -FeatureName "IIS-ManagementScriptingTools" -ErrorAction Stop
    if ($null -eq $scriptingTools -or $scriptingTools.State -ne 'Enabled') {
        $iisNeedsInstall = $true
    }
} catch {
    $iisNeedsInstall = $true
}

if ($iisNeedsInstall) {
    Write-Host "IIS or management tools not detected. Installing required components..." -ForegroundColor Yellow
    try {
        Enable-WindowsOptionalFeature -Online -FeatureName $iisFeatures -All -ErrorAction Stop | Out-Null
        Write-Host ""
        Write-Host "===============================================================" -ForegroundColor Green
        Write-Host "[SUCCESS] IIS features installation completed!" -ForegroundColor Green
        Write-Host "To load the IIS modules in the environment:" -ForegroundColor Yellow
        Write-Host "1. Close this PowerShell window." -ForegroundColor Yellow
        Write-Host "2. Open a new PowerShell as Administrator." -ForegroundColor Yellow
        Write-Host "3. Run this script again to proceed." -ForegroundColor Yellow
        Write-Host "===============================================================" -ForegroundColor Green
        Write-Host ""
        return
    } catch {
        Write-Error "Failed to install IIS features: $_"
        return 1
    }
} else {
    Write-Host "IIS and management tools are ready. Proceeding..." -ForegroundColor Green
}

# Import WebAdministration module
if (-not (Get-Module -Name WebAdministration -ListAvailable)) {
    Write-Error "The PowerShell 'WebAdministration' module was not found. Check the IIS installation."
    return 1
}
Import-Module WebAdministration -ErrorAction Stop

# ==========================================
# CONFIGURATION VARIABLES
# ==========================================
$SiteName    = "CustomerSpike"
$AppPoolName = "CustomerSpikeAppPool"
$SitePath    = "C:\inetpub\wwwroot\CustomerSpike\Api"

$UserName    = "SpikeIISUser"
$PasswordStr = "SenhaForte@2026!"
$Password    = ConvertTo-SecureString $PasswordStr -AsPlainText -Force
$GroupName   = "SpikeIISGroup"

Write-Host "Starting complete provisioning..." -ForegroundColor Cyan

# ==========================================
# 1. LOCAL USER AND GROUP
# ==========================================
# Create the user if it does not exist
if (-not (Get-LocalUser -Name $UserName -ErrorAction SilentlyContinue)) {
    New-LocalUser -Name $UserName -Password $Password -PasswordNeverExpires:$true -UserMayNotChangePassword:$true | Out-Null
    Write-Host "[+] User '$UserName' created." -ForegroundColor Green
}

# Create the group if it does not exist
if (-not (Get-LocalGroup -Name $GroupName -ErrorAction SilentlyContinue)) {
    New-LocalGroup -Name $GroupName | Out-Null
    Write-Host "[+] Group '$GroupName' created." -ForegroundColor Green
}

# Add the user to the group
$groupMembers = (Get-LocalGroupMember -Group $GroupName -ErrorAction SilentlyContinue).Name
if ($groupMembers -notcontains $UserName -and $groupMembers -notmatch "\\$UserName$") {
    Add-LocalGroupMember -Group $GroupName -Member $UserName -ErrorAction SilentlyContinue
    Write-Host "[+] User added to group '$GroupName'." -ForegroundColor Green
}

# Add the user to the native IIS_IUSRS group (Required for IIS identities)
$iisMembers = (Get-LocalGroupMember -Group "IIS_IUSRS" -ErrorAction SilentlyContinue).Name
if ($iisMembers -notcontains $UserName -and $iisMembers -notmatch "\\$UserName$") {
    Add-LocalGroupMember -Group "IIS_IUSRS" -Member $UserName -ErrorAction SilentlyContinue
    Write-Host "[+] User added to native group 'IIS_IUSRS'." -ForegroundColor Green
}

# ==========================================
# 2. ENSURE PHYSICAL DIRECTORY AND PERMISSIONS (ACL)
# ==========================================
if (-not (Test-Path $SitePath)) {
    New-Item -ItemType Directory -Path $SitePath -Force | Out-Null
}

# Grant read/execute permission to the newly created user on the site folder
try {
    $acl = Get-Acl -Path $SitePath
    $accessRule = New-Object System.Security.AccessControl.FileSystemAccessRule($UserName, "ReadAndExecute", "ContainerInherit,ObjectInherit", "None", "Allow")
    $acl.AddAccessRule($accessRule)
    Set-Acl -Path $SitePath -AclObject $acl
    Write-Host "[+] Read permissions granted to user '$UserName'." -ForegroundColor Green
} catch {
    Write-Host "[!] Warning: Could not apply permissions automatically." -ForegroundColor Yellow
}

# ==========================================
# 3. APPLICATION POOL WITH SPECIFIC USER
# ==========================================
if (-not (Test-Path "IIS:\AppPools\$AppPoolName")) {
    New-WebAppPool -Name $AppPoolName | Out-Null
    Write-Host "[+] Application Pool '$AppPoolName' created." -ForegroundColor Green
}

# Configure as "No Managed Code" (.NET Core) and set the custom identity
Set-ItemProperty -Path "IIS:\AppPools\$AppPoolName" -Name "managedRuntimeVersion" -Value ""
Set-ItemProperty -Path "IIS:\AppPools\$AppPoolName" -Name "processModel.identityType" -Value 3 # 3 = SpecificUser
Set-ItemProperty -Path "IIS:\AppPools\$AppPoolName" -Name "processModel.userName" -Value $UserName
Set-ItemProperty -Path "IIS:\AppPools\$AppPoolName" -Name "processModel.password" -Value $PasswordStr

Write-Host "[+] AppPool configured as 'No Managed Code' running with user '$UserName'." -ForegroundColor Green

# ==========================================
# 4. CREATE SITE AND LINK TO APP POOL
# ==========================================
if ((Get-WebSite -Name "Default Web Site" -ErrorAction SilentlyContinue).State -eq "Started") {
    Stop-WebSite -Name "Default Web Site" -ErrorAction SilentlyContinue
}

if (Test-Path "IIS:\Sites\$SiteName") {
    Remove-WebSite -Name $SiteName
}

New-Website -Name $SiteName -PhysicalPath $SitePath -ApplicationPool $AppPoolName -Port 80 -Force | Out-Null
Write-Host "[+] Site '$SiteName' created on port 80." -ForegroundColor Green

# ==========================================
# 5. RESTART SERVICES
# ==========================================
Restart-WebAppPool -Name $AppPoolName -ErrorAction SilentlyContinue
Stop-WebSite -Name $SiteName -ErrorAction SilentlyContinue
Start-WebSite -Name $SiteName -ErrorAction SilentlyContinue

Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "Process completed successfully! Access http://localhost" -ForegroundColor Cyan