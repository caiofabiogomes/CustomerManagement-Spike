# 

[![CI Pipeline](https://github.com/caiofabiogomes/CustomerManagement-Spike/actions/workflows/ci.yml/badge.svg)](https://github.com/caiofabiogomes/CustomerManagement-Spike/actions/workflows/ci.yml)
![.NET 10](https://img.shields.io/badge/.NET-10.0-512BD4?logo=dotnet&logoColor=white)
![C# 13](https://img.shields.io/badge/C%23-13.0-239120?logo=csharp&logoColor=white)
![IIS](https://img.shields.io/badge/IIS-10.0%2B-0078D7?logo=windows&logoColor=white)
![Docker](https://img.shields.io/badge/Docker-Ready-2496ED?logo=docker&logoColor=white)
![Tests](https://img.shields.io/badge/Tests-16%20Passed-brightgreen?logo=xunit)

---

## 📑 Table of Contents

- [Overview & System Architecture](#-overview--system-architecture)
- [Key Features](#-key-features)
- [Repository Structure](#-repository-structure)
- [Prerequisites & System Requirements](#-prerequisites--system-requirements)
- [🚀 Quick Start (5-Minute Run)](#-quick-start-5-minute-run)
- [Detailed Deployment Guides](#-detailed-deployment-guides)
  - [1. Local Development & Testing](#1-local-development--testing)
  - [2. Automated IIS Web Hosting (`deploy.ps1`)](#2-automated-iis-web-hosting-deployps1)
  - [3. Windows Monitoring Service (`deploy-service.ps1` / `install-service.ps1`)](#3-windows-monitoring-service-deploy-serviceps1--install-serviceps1)
  - [4. Docker & Containerized Hosting (`deploy-docker.ps1`)](#4-docker--containerized-hosting-deploy-dockerps1)
- [CI/CD Pipeline (GitHub Actions)](#-cicd-pipeline-github-actions)
- [Script Parameters Reference](#-script-parameters-reference)
- [Verification & Reliability Testing (300s Auto-Recovery)](#-verification--reliability-testing-300s-auto-recovery)
- [Troubleshooting Runbook](#-troubleshooting-runbook)
- [Further Documentation](#-further-documentation)

---

## 🏗️ Overview & System Architecture

```
+-----------------------------------------------------------------------------------+
|                                GitHub Actions CI/CD                               |
| (Checkout -> .NET 10 SDK -> Restore -> Build -> xUnit Tests -> Zip & Docker Push)  |
+----------------------------------------+------------------------------------------+
                                         |
            +----------------------------+----------------------------+
            |                                                         |
            v                                                         v
+---------------------------------------+         +----------------------------------+
|      IIS Web Server (Port 80/443)     |         |     Docker Container Engine      |
|  - Root Site: http://localhost/       |         |  - Container: customer-mgmt-web  |
|  - Child App: http://localhost/app    |         |  - Image: multi-stage .NET 10    |
|  - Identity: SpikeIISUser             |         |  - User: Non-root ($APP_UID)     |
|  - SSL: Self-signed cert via netsh    |         |  - Port: 8080:8080               |
+-------------------+-------------------+         +----------------------------------+
                    ^
                    | HTTP Probe (every 60s)
                    |
+-------------------+-------------------+
|      Windows Monitoring Service       |
|  - Service: CustomerSpikeIisMonitor   |
|  - Identity: SpikeIISUser             |
|  - Log File: iis_monitor.log          |
|  - Fail-Stop: Exit(1) on non-200 OK   |
|  - SCM Auto-Recovery: 300s (5 minutes)|
+---------------------------------------+
```

---

## ✨ Key Features

- **Web Application (`CustomerManagementSpike.Web`)**:
  - ASP.NET Core 10 MVC with clean Controller-View-Model separation.
  - Full CRUD operations with client and server-side data validation.
  - Thread-safe in-memory data store (`ConcurrentDictionary`).
  - Persistent Data Protection keys in `App_Data` to preserve session and anti-forgery tokens across IIS worker process recycles.
- **SRE Health Monitoring Worker (`CustomerManagementSpike.MonitoringService`)**:
  - Built with .NET Worker Service and `Microsoft.Extensions.Hosting.WindowsServices`.
  - Non-blocking HTTP health probing using `PeriodicTimer` (every 60 seconds).
  - Autonomous file logging to `iis_monitor.log`.
  - **Fail-Stop pattern**: Intentional termination (`Environment.Exit(1)`) on non-200 OK responses or network unreachable errors.
  - Configured with Windows SCM **300-second (5-minute) auto-recovery**.
- **Automated Infrastructure as Code (PowerShell)**:
  - `deploy.ps1`: Zero-touch IIS setup including local dedicated user/group, NTFS ACLs, AppPool identity, port 80/443 SSL certificate binding, and `/app` child application routing.
  - `deploy-service.ps1` & `install-service.ps1`: Windows Service installation granting `SeServiceLogonRight` ("Log on as a service") via Win32 LSA API, service binary compilation, and SCM failure recovery setup.
  - `deploy-docker.ps1`: Automated Docker Compose orchestration.
- **Test Suite (`CustomerManagementSpike.Tests`)**:
  - 16 automated xUnit tests covering customer domain logic, mock HTTP handlers (200, 404, 500, 503, timeouts), file logger concurrency, and service lifecycle.
- **CI/CD Pipeline**:
  - Automated build, test with TRX reporting, zip packaging (`CustomerManagementSpike-Web-app.zip`), and Docker Hub publishing.

---

## 📂 Repository Structure

```
CustomerManagement-Spike/
├── .github/
│   └── workflows/
│       └── ci.yml                             # GitHub Actions CI/CD workflow
├── src/
│   ├── CustomerManagementSpike.Web/           # ASP.NET Core 10 MVC Application
│   │   ├── Controllers/                       # CustomersController, HomeController
│   │   ├── Models/                            # Customer model & validation rules
│   │   ├── Services/                          # Thread-safe CustomerService
│   │   ├── Views/                             # Razor Views (CRUD & layout)
│   │   └── Program.cs                         # Application entrypoint & DataProtection
│   ├── CustomerManagementSpike.MonitoringService/ # Windows Health Monitoring Service
│   │   ├── Logging/                           # Autonomous file logger (iis_monitor.log)
│   │   ├── Worker.cs                          # PeriodicTimer HTTP probe & fail-stop logic
│   │   ├── appsettings.json                   # Probe intervals & URL configuration
│   │   └── Program.cs                         # Windows Service host builder
│   └── CustomerManagementSpike.Tests/         # Automated xUnit Test Suite (16 tests)
│       ├── CustomerServiceTests.cs            # Customer CRUD & thread-safety tests
│       └── MonitoringServiceTests.cs          # HTTP probing, logging & lifecycle tests
├── deploy.ps1                                 # Automated IIS deployment script
├── deploy-service.ps1                         # Automated Windows Service deployment script
├── install-service.ps1                        # Quick wrapper for Windows Service deployment
├── deploy-docker.ps1                          # Automated Docker Compose deployment script
├── Dockerfile                                 # Multi-stage container build
├── docker-compose.yml                         # Container orchestration configuration
├── DOCUMENTATION.md                           # Detailed technical documentation
├── guide.html                                 # Visual quick-start HTML guide
└── README.md                                  # User and developer manual
```

---

## 🔧 Prerequisites & System Requirements

| Tool | Minimum Version | Required For | Verification Command |
| :--- | :--- | :--- | :--- |
| **.NET SDK** | `10.0.x` *(or 8.0+)* | Building, testing, local execution | `dotnet --version` |
| **ASP.NET Core Hosting Bundle** | `10.0.x` | IIS hosting (installs ANCM v2) | [Download Hosting Bundle](https://dotnet.microsoft.com/permalink/dotnetcore-current-windows-runtime-bundle-installer) |
| **PowerShell** | `5.1` or `7.0+` | Running automated deployment scripts | `$PSVersionTable.PSVersion` |
| **IIS (Internet Information Services)** | `10.0+` | IIS hosting on Windows | Handled by `deploy.ps1` (or `Get-Service W3SVC`) |
| **Docker Desktop / Docker Engine** | `24.0+` | Container execution | `docker --version` |
| **Docker Compose** | `v2.20+` | Container orchestration | `docker compose version` |

> [!IMPORTANT]
> To execute `deploy.ps1`, `deploy-service.ps1`, or `install-service.ps1`, you must open PowerShell with **Run as Administrator**.

---

## 🚀 Quick Start (5-Minute Run)

### Option 1: Run Locally (Fastest)

```powershell
# 1. Clone repository & navigate to folder
git clone https://github.com/caiofabiogomes/CustomerManagement-Spike.git
cd CustomerManagement-Spike

# 2. Run unit tests
dotnet test

# 3. Launch Web Application
dotnet run --project src/CustomerManagementSpike.Web/CustomerManagementSpike.Web.csproj
```
👉 Open your browser at **`http://localhost:5000`** (or the URL displayed in the console).

---

### Option 2: Run with Docker

```powershell
# Launch containerized application on Port 8080
.\deploy-docker.ps1 -Build
```
👉 Open your browser at **`http://localhost:8080`**.

---

### Option 3: Deploy to Full IIS & Windows Monitoring Service

```powershell
# Open PowerShell as Administrator

# 1. Deploy Web App to IIS (creates SpikeIISUser, sets ACLs, provisions AppPool & HTTPS)
.\deploy.ps1

# 2. Install & Start Windows Monitoring Service (grants logon rights, registers SCM with 300s recovery)
.\install-service.ps1
```
👉 Open your browser at:
- Root Redirect: **`http://localhost/`**
- Web Application: **`http://localhost/app`**
- HTTPS Encrypted: **`https://localhost/app`**

---

## 📖 Detailed Deployment Guides

### 1. Local Development & Testing

#### Building the Solution
```powershell
dotnet restore
dotnet build --configuration Release
```

#### Running the Test Suite
```powershell
dotnet test --configuration Release --verbosity normal
```

#### Running the Monitoring Service in Console Mode
```powershell
dotnet run --project src/CustomerManagementSpike.MonitoringService/CustomerManagementSpike.MonitoringService.csproj
```

---

### 2. Automated IIS Web Hosting (`deploy.ps1`)

The [`deploy.ps1`](file:///C:/Users/caiof/source/repos/CustomerManagement-Spike/deploy.ps1) script provides completely unattended provisioning of IIS:

```powershell
# Run with default settings (Administrator PowerShell required)
.\deploy.ps1
```

#### What `deploy.ps1` does automatically:
1. **Validates Admin Rights**: Ensures execution under Administrator privileges.
2. **Installs Required IIS Features**: Installs `IIS-WebServerRole`, `IIS-DefaultDocument`, `IIS-HttpLogging`, and PowerShell `WebAdministration` tools if missing.
3. **Creates Dedicated User & Group**: Provisions local user `SpikeIISUser` and local group `SpikeIISGroup`.
4. **Compiles & Stages Binaries**: Publishes the Release build to `C:\inetpub\wwwroot\CustomerSpike\App` and configures `...\Root` default page.
5. **Configures NTFS Permissions**: Grants explicit Full Control rights to `SpikeIISUser`.
6. **Creates & Configures AppPool**: Sets `CustomerSpikeAppPool` to `No Managed Code` (ANCM Out-of-Process / In-Process) running under `.\SpikeIISUser`.
7. **Sets up IIS Website & Bindings**: Configures Port 80 (HTTP) and generates a self-signed localhost SSL certificate bound to Port 443 (HTTPS).
8. **Maps Child Application**: Binds `/app` to the compiled web application.

---

### 3. Windows Monitoring Service (`deploy-service.ps1` / `install-service.ps1`)

The [`install-service.ps1`](file:///C:/Users/caiof/source/repos/CustomerManagement-Spike/install-service.ps1) / [`deploy-service.ps1`](file:///C:/Users/caiof/source/repos/CustomerManagement-Spike/deploy-service.ps1) script configures the SRE background health monitor:

```powershell
# Run with default settings (Administrator PowerShell required)
.\install-service.ps1
```

#### What it does automatically:
1. **Grants `SeServiceLogonRight`**: Uses Windows Win32 LSA API to grant "Log on as a service" privilege to `SpikeIISUser`.
2. **Publishes Service Binaries**: Compiles `CustomerManagementSpike.MonitoringService` to `C:\Services\CustomerSpikeIisMonitor`.
3. **Registers Windows Service**: Creates `CustomerSpikeIisMonitor` in Windows SCM set to Automatic startup (`start= auto`).
4. **Configures SCM Auto-Recovery**: Sets failure action to restart the service after **300,000 ms (300 seconds / 5 minutes)** for all failure attempts:
   ```powershell
   sc.exe failure "CustomerSpikeIisMonitor" reset= 86400 actions= restart/300000/restart/300000/restart/300000
   ```
5. **Starts the Service**: Verifies startup and checks initial log entry creation.

#### Useful Service Management Commands:
```powershell
# Check service status
Get-Service -Name "CustomerSpikeIisMonitor"

# Tail live monitor logs
Get-Content -Path "C:\Services\CustomerSpikeIisMonitor\iis_monitor.log" -Wait -Tail 20

# Inspect SCM auto-recovery configuration
sc.exe qfailure "CustomerSpikeIisMonitor"

# Stop / Start service manually
Stop-Service -Name "CustomerSpikeIisMonitor"
Start-Service -Name "CustomerSpikeIisMonitor"
```

---

### 4. Docker & Containerized Hosting (`deploy-docker.ps1`)

Run the application inside a hardened Linux container:

```powershell
# Build and run container
.\deploy-docker.ps1 -Build

# Run on a custom host port (e.g. 9000)
.\deploy-docker.ps1 -HostPort 9000 -Environment "Production" -Build
```

Or using native Docker commands:
```powershell
# Build image
docker build -t customer-management-web .

# Run container
docker run -d -p 8080:8080 --name customer-management-web customer-management-web
```

---

## 🔄 CI/CD Pipeline (GitHub Actions)

The workflow defined in [`.github/workflows/ci.yml`](file:///C:/Users/caiof/source/repos/CustomerManagement-Spike/.github/workflows/ci.yml) automates continuous quality gates and packaging:

1. **Trigger**: Executes on every `push` or `pull_request` against `main` or `master`, or via manual `workflow_dispatch`.
2. **Restore & Build**: Restores NuGet dependencies with caching and builds in Release configuration.
3. **Automated Testing**: Executes the 16 xUnit tests and generates TRX test logs.
4. **Zip Packaging**: Compiles web app and compresses it into `CustomerManagementSpike-Web-app.zip`.
5. **Artifact Upload**: Publishes zip package as a downloadable artifact (14-day retention).
6. **Docker Hub Publishing**: Builds and pushes Docker image tagged with `latest` and commit SHA.
7. **Test Results Upload**: Saves TRX test report artifact (7-day retention).

---

## ⚙️ Script Parameters Reference

### `deploy.ps1` (IIS Provisioning)

| Parameter | Type | Default Value | Description |
| :--- | :--- | :--- | :--- |
| `-SiteName` | String | `CustomerSpike` | Name of the IIS Web Site |
| `-AppPoolName` | String | `CustomerSpikeAppPool` | Name of the IIS Application Pool |
| `-RootPath` | String | `C:\inetpub\wwwroot\CustomerSpike\Root` | Directory for root landing page |
| `-AppPath` | String | `C:\inetpub\wwwroot\CustomerSpike\App` | Directory for compiled MVC Web application |
| `-LogDirectory` | String | `C:\inetpub\logs\CustomerSpike` | Directory for IIS web traffic logs |
| `-UserName` | String | `SpikeIISUser` | Local Windows user for AppPool and service identity |
| `-PasswordStr` | String | `SenhaForte@2026!` | Password for the dedicated Windows user |
| `-GroupName` | String | `SpikeIISGroup` | Local Windows group created for permissions |
| `-HttpPort` | Int | `80` | Port for HTTP binding |
| `-HttpsPort` | Int | `443` | Port for HTTPS SSL binding |
| `-CertFriendlyName` | String | `CustomerSpike-IIS-Cert` | Friendly name for generated self-signed SSL cert |
| `-SkipPublish` | Switch | `False` | Skips dotnet compilation if binaries already exist |

### `deploy-service.ps1` / `install-service.ps1` (Monitoring Service)

| Parameter | Type | Default Value | Description |
| :--- | :--- | :--- | :--- |
| `-InstallPath` | String | `C:\Services\CustomerSpikeIisMonitor` | Target directory for monitoring service binaries |
| `-ServiceName` | String | `CustomerSpikeIisMonitor` | Windows Service registered name |
| `-TargetUrl` | String | `http://localhost/` | HTTP endpoint probed by the worker |
| `-CheckIntervalSeconds`| Int | `60` | Frequency of health check probes in seconds |
| `-RecoveryDelaySeconds` | Int | `300` | SCM restart delay on failure (300s = 5 minutes) |
| `-UserName` | String | `SpikeIISUser` | Account identity for running the service |
| `-Password` | String | `SenhaForte@2026!` | Password for the service account |

### `deploy-docker.ps1` (Container Hosting)

| Parameter | Type | Default Value | Description |
| :--- | :--- | :--- | :--- |
| `-HostPort` | Int | `8080` | Host port mapped to container port 8080 |
| `-Environment` | String | `Production` | ASP.NET Core runtime environment |
| `-Build` | Switch | `False` | Forces docker compose to rebuild the image |

---

## 🔍 Verification & Reliability Testing (300s Auto-Recovery)

To verify the SRE fail-stop mechanism and the Windows SCM 300-second auto-recovery lifecycle:

```
+-----------------------------------------------------------------------------------+
| 1. Stop IIS Website        Stop-WebSite -Name "CustomerSpike"                     |
|                                     |                                             |
|                                     v                                             |
| 2. Monitor detects failure Worker records SERVICE_FAILURE in iis_monitor.log      |
|                                     |                                             |
|                                     v                                             |
| 3. Fail-Stop Triggered     Worker executes Environment.Exit(1)                    |
|                                     |                                             |
|                                     v                                             |
| 4. SCM Recovery Countdown  Windows SCM starts 300-second (5 min) restart timer    |
|                                     |                                             |
|                                     v                                             |
| 5. Restart IIS Website     Start-WebSite -Name "CustomerSpike"                    |
|                                     |                                             |
|                                     v                                             |
| 6. SCM Restores Service    Exactly at 300s, SCM relaunches monitor service        |
|                            and normal 200 OK logging resumes                      |
+-----------------------------------------------------------------------------------+
```

### Step-by-Step Test Procedure:

1. **Verify normal operation**:
   ```powershell
   Get-Content "C:\Services\CustomerSpikeIisMonitor\iis_monitor.log" -Tail 5
   # Output shows: [INFO] ... URL: http://localhost/ | Status: 200 OK
   ```

2. **Simulate outage by stopping the website**:
   ```powershell
   Stop-WebSite -Name "CustomerSpike"
   ```

3. **Observe Fail-Stop within 60 seconds**:
   ```powershell
   Get-Content "C:\Services\CustomerSpikeIisMonitor\iis_monitor.log" -Tail 3
   # Output shows: [ERROR] ... Critical failure: HTTP request failed ... Exiting process.
   Get-Service -Name "CustomerSpikeIisMonitor"
   # Status shows: Stopped
   ```

4. **Restore website**:
   ```powershell
   Start-WebSite -Name "CustomerSpike"
   ```

5. **Verify SCM Auto-Recovery after 5 minutes**:
   After 300 seconds (5 minutes), Windows SCM automatically restarts the service.
   ```powershell
   Get-Service -Name "CustomerSpikeIisMonitor"
   # Status shows: Running
   ```

---

## 🛠️ Troubleshooting Runbook

| Issue | Likely Cause | Solution |
| :--- | :--- | :--- |
| **HTTP 500.19 on IIS** | ASP.NET Core Hosting Bundle is missing on the machine. | Install the [ASP.NET Core 10.0 Hosting Bundle](https://dotnet.microsoft.com/permalink/dotnetcore-current-windows-runtime-bundle-installer), then run `net stop was /y` and `net start w3svc`. |
| **HTTP 502.5 Process Failure** | Application crashed during startup or missing .NET 10 runtime. | Check the stdout logs at `C:\inetpub\wwwroot\CustomerSpike\App\logs\` and ensure .NET 10 runtime is installed. |
| **Service Error 1069 (Logon Failure)** | `SpikeIISUser` is missing the "Log on as a service" right (`SeServiceLogonRight`). | Run `.\deploy-service.ps1` as Administrator; it uses Win32 LSA API to grant the logon right automatically. |
| **Browser Certificate Warning on HTTPS** | Self-signed certificate is not trusted by your local trust store. | For local testing, click "Advanced -> Proceed to localhost", or import the certificate from `Cert:\LocalMachine\My` into `Cert:\LocalMachine\Root`. |
| **Docker Port Conflict (8080)** | Port 8080 is already bound by another process. | Launch on another port: `.\deploy-docker.ps1 -HostPort 8090 -Build`. |
| **Access Denied in PowerShell** | PowerShell was opened without elevated privileges. | Right-click PowerShell and select **Run as Administrator**. |

---

