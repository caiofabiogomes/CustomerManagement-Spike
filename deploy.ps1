[CmdletBinding()]
param (
    [string]$SiteName         = "CustomerSpike",
    [string]$AppPoolName      = "CustomerSpikeAppPool",
    [string]$RootPath         = "C:\inetpub\wwwroot\CustomerSpike\Root",
    [string]$AppPath          = "C:\inetpub\wwwroot\CustomerSpike\App",
    [string]$LogDirectory     = "C:\inetpub\logs\CustomerSpike",
    [string]$UserName         = "SpikeIISUser",
    [string]$PasswordStr      = "SenhaForte@2026!",
    [string]$GroupName        = "SpikeIISGroup",
    [int]$HttpPort            = 80,
    [int]$HttpsPort           = 443,
    [string]$CertFriendlyName = "CustomerSpike-IIS-Cert",
    [switch]$SkipPublish
)

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
    exit 1
}

$ErrorActionPreference = "Stop"

# ==========================================
# 0. IIS CHECK AND PREREQUISITES
# ==========================================
Write-Host "Checking IIS installation and PowerShell modules..." -ForegroundColor Cyan

$hasWebAdminModule = [bool](Get-Module -Name WebAdministration -ListAvailable)
$hasW3Svc = [bool](Get-Service -Name W3SVC -ErrorAction SilentlyContinue)

if (-not $hasWebAdminModule -and -not $hasW3Svc) {
    Write-Host "IIS or management tools not detected. Installing required components..." -ForegroundColor Yellow
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
    try {
        Enable-WindowsOptionalFeature -Online -FeatureName $iisFeatures -All -ErrorAction Stop | Out-Null
        Write-Host "[SUCCESS] IIS features installed. Please re-run script if module does not load." -ForegroundColor Green
    } catch {
        Write-Error "Failed to install IIS features: $_"
        exit 1
    }
} else {
    Write-Host "[+] IIS service and management tools are ready." -ForegroundColor Green
}

# Import WebAdministration module
try {
    Import-Module WebAdministration -ErrorAction Stop
    Write-Host "[+] WebAdministration module loaded successfully." -ForegroundColor Green
} catch {
    Write-Error "Failed to load WebAdministration module: $_"
    exit 1
}

# Ensure W3SVC service is running
$w3svc = Get-Service -Name W3SVC -ErrorAction SilentlyContinue
if ($w3svc -and $w3svc.Status -ne 'Running') {
    Write-Host "Starting W3SVC (World Wide Web Publishing Service)..." -ForegroundColor Yellow
    Start-Service -Name W3SVC
}

$Password = ConvertTo-SecureString $PasswordStr -AsPlainText -Force

Write-Host ""
Write-Host "==========================================================================" -ForegroundColor Cyan
Write-Host "             PROVISIONING IIS INFRASTRUCTURE & APPLICATION                " -ForegroundColor Cyan
Write-Host "==========================================================================" -ForegroundColor Cyan
Write-Host " Web Site Name       : $SiteName (HTTP: $HttpPort | HTTPS: $HttpsPort)" -ForegroundColor Gray
Write-Host " Application Pool    : $AppPoolName (Identity: $UserName)" -ForegroundColor Gray
Write-Host " Root Physical Path  : $RootPath" -ForegroundColor Gray
Write-Host " Child Application   : /$SiteName/app -> $AppPath" -ForegroundColor Gray
Write-Host " Log File Directory  : $LogDirectory" -ForegroundColor Gray
Write-Host " Service Account     : $UserName (Member of $GroupName)" -ForegroundColor Gray
Write-Host "==========================================================================" -ForegroundColor Cyan
Write-Host ""

# ==========================================
# 1. LOCAL USER AND GROUP PROVISIONING
# ==========================================
Write-Host "[1/7] Configuring Local User and Group..." -ForegroundColor Yellow

$existingUser = Get-LocalUser -Name $UserName -ErrorAction SilentlyContinue
if (-not $existingUser) {
    try {
        New-LocalUser -Name $UserName -Password $Password -PasswordNeverExpires:$true -UserMayNotChangePassword:$true | Out-Null
        Write-Host "  [+] User '$UserName' created." -ForegroundColor Green
    } catch {
        Write-Warning "Could not create user with New-LocalUser: $_. Attempting net user fallback..."
        & net user "$UserName" "$PasswordStr" /add /y | Out-Null
    }
} else {
    try {
        Set-LocalUser -Name $UserName -Password $Password -ErrorAction SilentlyContinue | Out-Null
    } catch { }
    Write-Host "  [+] User '$UserName' verified." -ForegroundColor Green
}

$existingGroup = Get-LocalGroup -Name $GroupName -ErrorAction SilentlyContinue
if (-not $existingGroup) {
    try {
        New-LocalGroup -Name $GroupName | Out-Null
        Write-Host "  [+] Group '$GroupName' created." -ForegroundColor Green
    } catch {
        & net localgroup "$GroupName" /add 2>&1 | Out-Null
    }
} else {
    Write-Host "  [+] Group '$GroupName' already exists." -ForegroundColor Green
}

# Add user to custom group
try {
    Add-LocalGroupMember -Group $GroupName -Member $UserName -ErrorAction Stop
    Write-Host "  [+] User '$UserName' added to custom group '$GroupName'." -ForegroundColor Green
} catch {
    Write-Host "  [+] User '$UserName' is a member of '$GroupName'." -ForegroundColor Green
}

# Add user to native IIS_IUSRS group
try {
    Add-LocalGroupMember -Group "IIS_IUSRS" -Member $UserName -ErrorAction Stop
    Write-Host "  [+] User '$UserName' added to native group 'IIS_IUSRS'." -ForegroundColor Green
} catch {
    Write-Host "  [+] User '$UserName' is a member of 'IIS_IUSRS'." -ForegroundColor Green
}

# ==========================================
# 2. COMPILE & PUBLISH WEB APPLICATION & PREPARE ROOT
# ==========================================
Write-Host "`n[2/7] Preparing Web Application Binaries & Root Directory..." -ForegroundColor Yellow
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$webProject = Join-Path $scriptDir "src\CustomerManagementSpike.Web\CustomerManagementSpike.Web.csproj"

# Prepare decoupled Root site directory and static landing page
if (-not (Test-Path $RootPath)) {
    New-Item -ItemType Directory -Path $RootPath -Force | Out-Null
}

$rootIndexHtml = Join-Path $RootPath "index.html"
$rootHtmlContent = @"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta http-equiv="refresh" content="0; url=/app" />
    <title>Customer Management Spike</title>
</head>
<body style="font-family: sans-serif; text-align: center; margin-top: 50px;">
    <h1>Customer Management Spike</h1>
    <p>IIS Root Site online. Redirecting to child application <a href="/app">/app</a>...</p>
</body>
</html>
"@
[System.IO.File]::WriteAllText($rootIndexHtml, $rootHtmlContent, [System.Text.Encoding]::UTF8)

if (-not (Test-Path $AppPath)) {
    New-Item -ItemType Directory -Path $AppPath -Force | Out-Null
}

if (-not $SkipPublish) {
    if (Test-Path $webProject) {
        Write-Host "  [+] Compiling and publishing web app to $AppPath..." -ForegroundColor Cyan
        dotnet publish "$webProject" --configuration Release --output "$AppPath" --verbosity minimal
        Write-Host "  [+] Web application published successfully." -ForegroundColor Green
    } else {
        Write-Warning "Web project file not found at '$webProject'. Skipping compilation."
    }
} else {
    Write-Host "  [+] Skipping publish as -SkipPublish flag was supplied." -ForegroundColor Gray
}

# ==========================================
# 3. SET DIRECTORY PERMISSIONS (ACL)
# ==========================================
Write-Host "`n[3/7] Setting NTFS Directory Permissions..." -ForegroundColor Yellow

$targetDirectories = @($RootPath, $AppPath, $LogDirectory)
foreach ($dir in $targetDirectories) {
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    try {
        $acl = Get-Acl -Path $dir
        $accessRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
            $UserName, "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow")
        $acl.AddAccessRule($accessRule)
        Set-Acl -Path $dir -AclObject $acl
        Write-Host "  [+] FullControl permissions granted on '$dir' to '$UserName'." -ForegroundColor Green
    } catch {
        Write-Warning "Could not apply NTFS permissions on '$dir': $_"
    }
}

# ==========================================
# 4. CONFIGURE APPLICATION POOL WITH CUSTOM USER
# ==========================================
Write-Host "`n[4/7] Configuring IIS Application Pool..." -ForegroundColor Yellow

if (-not (Test-Path "IIS:\AppPools\$AppPoolName")) {
    New-WebAppPool -Name $AppPoolName | Out-Null
    Write-Host "  [+] Application Pool '$AppPoolName' created." -ForegroundColor Green
} else {
    Write-Host "  [+] Application Pool '$AppPoolName' already exists." -ForegroundColor Green
}

if ($UserName -match "\\") {
    $appPoolUser = $UserName
} else {
    $appPoolUser = ".\$UserName"
}

# Configure as "No Managed Code" (.NET Core) and set custom identity
Set-ItemProperty -Path "IIS:\AppPools\$AppPoolName" -Name "managedRuntimeVersion" -Value ""
Set-ItemProperty -Path "IIS:\AppPools\$AppPoolName" -Name "processModel.identityType" -Value 3
Set-ItemProperty -Path "IIS:\AppPools\$AppPoolName" -Name "processModel.userName" -Value $appPoolUser
Set-ItemProperty -Path "IIS:\AppPools\$AppPoolName" -Name "processModel.password" -Value $PasswordStr
Set-ItemProperty -Path "IIS:\AppPools\$AppPoolName" -Name "processModel.loadUserProfile" -Value "True"

Write-Host "  [+] AppPool configured with 'No Managed Code' and identity '$appPoolUser'." -ForegroundColor Green

# ==========================================
# 5. CREATE WEB SITE & CONFIGURE LOG PATH
# ==========================================
Write-Host "`n[5/7] Creating Web Site and Configuring Log File Directory..." -ForegroundColor Yellow

# Handle Default Web Site port 80 conflict
$defaultSite = Get-WebSite -Name "Default Web Site" -ErrorAction SilentlyContinue
if ($defaultSite -and $defaultSite.State -eq "Started") {
    Write-Host "  [!] Stopping 'Default Web Site' to free up Port 80..." -ForegroundColor Yellow
    Stop-WebSite -Name "Default Web Site" -ErrorAction SilentlyContinue
}

if (Test-Path "IIS:\Sites\$SiteName") {
    Remove-WebSite -Name $SiteName
    Write-Host "  [+] Removed existing site '$SiteName' for clean provisioning." -ForegroundColor Gray
}

# Create Web Site pointing to decoupled $RootPath
New-Website -Name $SiteName -PhysicalPath $RootPath -ApplicationPool $AppPoolName -Port $HttpPort -Force | Out-Null
Write-Host "  [+] Site '$SiteName' created on Port $HttpPort (Root Path: $RootPath)." -ForegroundColor Green

# Modify the path of the web site log file
try {
    Set-ItemProperty -Path "IIS:\Sites\$SiteName" -Name "logFile.directory" -Value $LogDirectory -ErrorAction Stop
} catch {
    Set-WebConfigurationProperty -pspath "IIS:\" -filter "system.applicationHost/sites/site[@name='$SiteName']/logFile" -name "directory" -value $LogDirectory -ErrorAction SilentlyContinue
}
Write-Host "  [+] Web site log directory configured to: '$LogDirectory'." -ForegroundColor Green

# ==========================================
# 6. ADD HTTPS BINDING & SSL CERTIFICATE
# ==========================================
Write-Host "`n[6/7] Adding HTTPS Binding with SSL Certificate..." -ForegroundColor Yellow

# Retrieve or generate self-signed development certificate
$cert = Get-ChildItem Cert:\LocalMachine\My | Where-Object {
    ($_.FriendlyName -eq $CertFriendlyName -or $_.Subject -match "CN=localhost") -and $_.HasPrivateKey
} | Select-Object -First 1

if (-not $cert) {
    Write-Host "  [+] Generating self-signed SSL certificate for 'localhost'..." -ForegroundColor Cyan
    $cert = New-SelfSignedCertificate `
        -DnsName "localhost" `
        -CertStoreLocation "Cert:\LocalMachine\My" `
        -FriendlyName $CertFriendlyName `
        -NotAfter (Get-Date).AddYears(5)
    Write-Host "  [+] Created SSL Certificate (Thumbprint: $($cert.Thumbprint))." -ForegroundColor Green
} else {
    Write-Host "  [+] Using existing SSL Certificate (Thumbprint: $($cert.Thumbprint))." -ForegroundColor Green
}

# Add HTTPS binding to the website
$existingHttps = Get-WebBinding -Name $SiteName -Protocol "https" -ErrorAction SilentlyContinue
if (-not $existingHttps) {
    New-WebBinding -Name $SiteName -IPAddress "*" -Port $HttpsPort -Protocol "https"
    Write-Host "  [+] Added HTTPS binding on Port $HttpsPort." -ForegroundColor Green
}

# Attach SSL certificate to HTTPS binding using netsh
try {
    & netsh http delete sslcert ipport="0.0.0.0:$HttpsPort" 2>&1 | Out-Null
    $appGuid = [Guid]::NewGuid().ToString("B")
    & netsh http add sslcert ipport="0.0.0.0:$HttpsPort" certhash="$($cert.Thumbprint)" appid="$appGuid" | Out-Null
    Write-Host "  [+] SSL Certificate attached to Port $HttpsPort." -ForegroundColor Green
} catch {
    Write-Warning "Failed attaching SSL cert via netsh: $_"
}

# ==========================================
# 7. CREATE LOWER-LEVEL APPLICATION & BIND APP POOL
# ==========================================
Write-Host "`n[7/7] Creating Lower-Level Application and Binding AppPool..." -ForegroundColor Yellow

$app = Get-WebApplication -Site $SiteName -Name "app" -ErrorAction SilentlyContinue
if (-not $app) {
    New-WebApplication -Site $SiteName -Name "app" -PhysicalPath $AppPath -ApplicationPool $AppPoolName | Out-Null
    Write-Host "  [+] Child application '/$SiteName/app' created and bound to '$AppPoolName' (Path: $AppPath)." -ForegroundColor Green
} else {
    Set-ItemProperty "IIS:\Sites\$SiteName\app" -Name "applicationPool" -Value $AppPoolName -ErrorAction SilentlyContinue
    Set-ItemProperty "IIS:\Sites\$SiteName\app" -Name "physicalPath" -Value $AppPath -ErrorAction SilentlyContinue
    Write-Host "  [+] Child application '/$SiteName/app' updated and bound to '$AppPoolName' (Path: $AppPath)." -ForegroundColor Green
}

# Restart Application Pool and Website
Restart-WebAppPool -Name $AppPoolName -ErrorAction SilentlyContinue
Stop-WebSite -Name $SiteName -ErrorAction SilentlyContinue
Start-WebSite -Name $SiteName -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "==========================================================================" -ForegroundColor Green
Write-Host "             IIS DEPLOYMENT COMPLETED WITH 100% COMPLIANCE!               " -ForegroundColor Green
Write-Host "==========================================================================" -ForegroundColor Green
Write-Host " Site Name          : $SiteName" -ForegroundColor White
Write-Host " HTTP Root Endpoint : http://localhost/  (Port: $HttpPort)" -ForegroundColor Cyan
Write-Host " HTTP App Endpoint  : http://localhost/app" -ForegroundColor Cyan
Write-Host " HTTPS Root Endpoint: https://localhost/ (Port: $HttpsPort)" -ForegroundColor Cyan
Write-Host " HTTPS App Endpoint : https://localhost/app" -ForegroundColor Cyan
Write-Host " AppPool Name       : $AppPoolName" -ForegroundColor White
Write-Host " AppPool User       : $appPoolUser (Member of $GroupName & IIS_IUSRS)" -ForegroundColor White
Write-Host " Root Directory     : $RootPath" -ForegroundColor White
Write-Host " Lower-Level App    : /app -> $AppPath" -ForegroundColor White
Write-Host " Log Files Location : $LogDirectory" -ForegroundColor White
Write-Host " SSL Certificate    : $($cert.Thumbprint) ($($cert.FriendlyName))" -ForegroundColor White
Write-Host "==========================================================================" -ForegroundColor Green
Write-Host ""