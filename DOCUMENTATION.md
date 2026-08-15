# Customer Management Spike — Technical Project Documentation

> **Document Version:** 1.0.0  
> **Target Framework:** .NET 10.0 (C# 13, ASP.NET Core MVC, Worker Service SDK)  
> **Deployment Targets:** Windows Server IIS 10.0+ (HTTPS / Custom User) & Docker Containers  
> **SRE & Reliability:** Windows Service with SCM 300-Second Auto-Recovery & HTTP Probing  
> **Continuous Integration:** GitHub Actions (.NET 10 Build, xUnit Test Suite, Packaging & Docker Hub)  
> **Automation Engine:** PowerShell 7+ / Windows PowerShell (ACLs, IIS, SCM, LSA Win32 Interop)  
> **Word Document Deliverable:** [`CustomerManagement_Spike_Documentation.docx`](./CustomerManagement_Spike_Documentation.docx)

---

## 📑 Table of Contents

1. [Executive Summary & System Architecture](#1-executive-summary--system-architecture)
2. [Required Tools & Environmental Prerequisites](#2-required-tools--environmental-prerequisites)
3. [Application Architecture & Component Details](#3-application-architecture--component-details)
4. [Local Development, Build & Run Guide](#4-local-development-build--run-guide)
5. [Automated IIS Web Hosting Deployment Guide (`deploy.ps1`)](#5-automated-iis-web-hosting-deployment-guide-deployps1)
6. [Automated Windows Monitoring Service Deployment Guide (`deploy-service.ps1`)](#6-automated-windows-monitoring-service-deployment-guide-deploy-serviceps1)
7. [Containerized Deployment Guide (Docker & Compose)](#7-containerized-deployment-guide-docker--compose)
8. [Continuous Integration & Delivery Pipeline (CI/CD)](#8-continuous-integration--delivery-pipeline-cicd)
9. [Configuration Management & Parameters Reference](#9-configuration-management--parameters-reference)
10. [Troubleshooting & Operations Runbook](#10-troubleshooting--operations-runbook)

---

## 1. Executive Summary & System Architecture

The **Customer Management Spike** is a production-ready enterprise reference application showcasing the end-to-end integration of modern **.NET 10** web architecture, Site Reliability Engineering (SRE) automated health monitoring, Windows infrastructure provisioning, multi-stage containerization, and automated CI/CD pipelines.

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

### 1.1 Repository Structure

| Path | Type | Responsibility |
| :--- | :--- | :--- |
| `src/CustomerManagementSpike.Web/` | ASP.NET Core 10 MVC | Customer CRUD Web UI, validation, controllers, models, and Data Protection key management. |
| `src/CustomerManagementSpike.MonitoringService/` | Worker Windows Service | SRE monitor: periodic HTTP probing, file logging, fail-stop on non-200, and SCM recovery integration. |
| `src/CustomerManagementSpike.Tests/` | xUnit Test Suite | 16 automated tests covering customer operations, mock HTTP handlers, failure simulations, and worker lifecycle. |
| `deploy.ps1` | PowerShell Automation | End-to-end IIS provisioning: local user/group, ACLs, Release publish, AppPool identity, HTTPS binding, and child app. |
| `deploy-service.ps1` | PowerShell Automation | Windows Service deployment: grants `SeServiceLogonRight` via Win32 LSA API, publishes .exe, registers SCM service (`start= auto`), and sets 300s auto-recovery. |
| `deploy-docker.ps1` | PowerShell Automation | Docker Compose deployment script with port mapping and environment variable overrides. |
| `install-service.ps1` | PowerShell Automation | Convenience wrapper script for `deploy-service.ps1`. |
| `Dockerfile` & `docker-compose.yml` | Container Configuration | Hardened multi-stage container build and compose orchestration. |
| `.github/workflows/ci.yml` | GitHub Actions CI | Automated build, test, packaging into `CustomerManagementSpike-Web-app.zip`, and Docker Hub push. |

---

## 2. Required Tools & Environmental Prerequisites

To develop, build, run, test, and deploy this solution across all supported platforms, ensure the following tools are available on the host machine.

### 2.1 Master Tools & Prerequisites Matrix

| Category | Tool / Dependency | Minimum Version | Operational Purpose | Verification Command |
| :--- | :--- | :--- | :--- | :--- |
| **Development** | **.NET SDK** | `10.0.x` *(or 8.0+ LTS)* | Compiling code, running unit tests, publishing binaries, and executing applications. | `dotnet --version` |
| **Development** | **Visual Studio 2022** / **VS Code** | VS 2022 v17.10+ / VS Code v1.90+ | Solution navigation (`.slnx` / `.sln`), interactive debugging, and C# 13 language tooling. | `code --version` / VS Installer |
| **Development** | **Git** | `2.40+` | Version control, branch management, and repository synchronization. | `git --version` |
| **Automation** | **PowerShell** | `7.0+` or `Windows PS 5.1` | Executing infrastructure provisioning scripts (`deploy.ps1`, `deploy-service.ps1`). Requires Administrator elevation. | `$PSVersionTable.PSVersion` |
| **IIS Web Server** | **Internet Information Services (IIS)** | `10.0+` *(Win 10/11/Server)* | Hosting web applications on Port 80 (HTTP) and Port 443 (HTTPS) with dedicated Application Pools. | `Get-Service W3SVC` |
| **IIS Web Server** | **ASP.NET Core Hosting Bundle** | `10.0.x` | Installs the **ASP.NET Core Module v2 (ANCM)** inside IIS for reverse proxying to Kestrel. | `dotnet --info` |
| **IIS Web Server** | **WebAdministration Module** | Windows Built-in | PowerShell cmdlets for managing IIS sites, AppPools, and bindings. | `Get-Module -ListAvailable WebAdministration` |
| **Windows Service** | **Service Control Manager CLI (`sc.exe`)** | Windows Built-in | Registers Windows Services, sets startup type, configures user credentials, and establishes 300s failure recovery. | `sc.exe /?` |
| **Windows Service** | **Network Shell (`netsh.exe`)** | Windows Built-in | Binds SSL certificates to TCP endpoints in the `HTTP.SYS` kernel driver. | `netsh http show sslcert` |
| **Windows Service** | **Local Security Authority (LSA) / Secedit** | Windows Built-in | Grants the `SeServiceLogonRight` ("Log on as a service") user right assignment to `SpikeIISUser`. | Handled automatically in script |
| **Containerization**| **Docker Desktop / Docker Engine** | Engine `24.0+` | Building multi-stage container images and running isolated Linux containers. | `docker --version` |
| **Containerization**| **Docker Compose** | Compose `v2.20+` | Multi-container orchestration, port forwarding, and environment variable configuration. | `docker compose version` |
| **CI/CD** | **GitHub Actions Runner** | Ubuntu 22.04+ | Automated cloud runner executing checkout, build, test, packaging, and container publishing. | Cloud Managed |

---

## 3. Application Architecture & Component Details

### 3.1 Web Application (`CustomerManagementSpike.Web`)
- **MVC Architecture:** Separation into Controllers (`CustomersController`, `HomeController`), Models (`Customer`), and Views.
- **Domain Entity (`Customer.cs`):** Strongly typed validation with `[Required]`, `[EmailAddress]`, `[Phone]`, and document/CPF format support.
- **In-Memory Storage (`CustomerService.cs`):** Thread-safe concurrent collection (`ConcurrentDictionary` / locking) allowing multi-user concurrent operations without data races.
- **Data Protection API:** Configured in `Program.cs` to persist cryptographic keys in `App_Data/DataProtection-Keys`, guaranteeing anti-forgery token consistency across IIS worker process recycles.
- **CSRF / Anti-Forgery:** Secure cookie policy enforced on all state-mutating requests (`.CustomerManagementSpike.Antiforgery`).

### 3.2 Health Monitoring Windows Service (`CustomerManagementSpike.MonitoringService`)
- **Worker Service Framework:** Built on `Microsoft.Extensions.Hosting.WindowsServices` and `BackgroundService`.
- **Health Check Engine:** Utilizes modern `PeriodicTimer` (configurable interval, default: 60s) to perform non-blocking HTTP probes using `HttpClient`.
- **Autonomous File Logging (`IisStatusFileLogger`):** Records probe timestamps (ISO 8601), HTTP response codes, reason phrases, and execution durations directly to `iis_monitor.log` in the executable folder.
- **Fail-Stop on Non-200 OK:** When any status other than `200 OK` (or connection refusal/timeout) is encountered, the service writes a critical failure entry and invokes `Environment.Exit(1)` to intentionally terminate.
- **SCM 300-Second Auto-Recovery:** The Windows Service Control Manager recognizes the exit code 1 crash and triggers the auto-recovery policy to restart the service after **300 seconds** (5 minutes).
- **Dual Execution Modes:** Runs as a native console application for local interactive debugging or as a background Windows Service.

### 3.3 Automated xUnit Test Suite (`CustomerManagementSpike.Tests`)
- **16 Automated Tests** across three test classes:
  1. `CustomerServiceTests` (4 tests): CRUD operations, incremental ID generation, and thread safety.
  2. `MonitoringServiceTests - Health` (6 tests): Mock HTTP handler responses for 200 OK, 404 Not Found, 500 Internal Error, 503 Unavailable, 401 Unauthorized, and network socket exceptions.
  3. `MonitoringServiceTests - Logging` (3 tests): Thread-safe file writing, format accuracy, and append reliability.
  4. `MonitoringServiceTests - Lifecycle` (3 tests): Service startup, check cancellation handling, and fail-stop exit invocation.

---

## 4. Local Development, Build & Run Guide

### 4.1 Build Solution
```powershell
# Navigate to repository root
cd CustomerManagement-Spike

# Restore NuGet dependencies
dotnet restore

# Build all projects in Release mode
dotnet build --configuration Release --no-restore
```

### 4.2 Run Automated Tests
```powershell
# Execute the complete 16-test suite with verbose output
dotnet test --configuration Release --verbosity normal --logger "trx;LogFileName=test_results.trx"
```

### 4.3 Run Web Application Locally
```powershell
# Start Web application on local Kestrel server
dotnet run --project src/CustomerManagementSpike.Web/CustomerManagementSpike.Web.csproj

# Access in browser: http://localhost:5000 (or configured launch URL)
```

### 4.4 Run Monitoring Service Locally
```powershell
# Run Monitoring Service in console/debug mode
dotnet run --project src/CustomerManagementSpike.MonitoringService/CustomerManagementSpike.MonitoringService.csproj
```

---

## 5. Automated IIS Web Hosting Deployment Guide (`deploy.ps1`)

The `deploy.ps1` script provides automated provisioning for IIS web hosting.

### 5.1 Provisioning Workflow
1. **Administrative Check:** Verifies elevated permissions.
2. **IIS Feature Check:** Installs missing IIS features and imports `WebAdministration`.
3. **User & Group Provisioning:** Creates local user `SpikeIISUser`, group `SpikeIISGroup`, and assigns `IIS_IUSRS` membership.
4. **Compilation & Decoupled Directory Staging:** Publishes binaries to `C:\inetpub\wwwroot\CustomerSpike\App` and prepares `...\Root` landing page.
5. **NTFS ACL Configuration:** Grants Full Control permissions to `SpikeIISUser`.
6. **Application Pool Setup:** Configures `CustomerSpikeAppPool` with `managedRuntimeVersion=""` (No Managed Code) and identity `.\SpikeIISUser`.
7. **Website & Log Path:** Provisions `CustomerSpike` on Port 80, points logging to `C:\inetpub\logs\CustomerSpike`.
8. **SSL / HTTPS Binding:** Generates self-signed localhost SSL certificate and binds Port 443 via `netsh http`.
9. **Child Application:** Maps `/app` to the published web application binaries.

### 5.2 Deployment Command
```powershell
# Open PowerShell as Administrator
.\deploy.ps1
```

### 5.3 Active Endpoints

| URL | Protocol & Port | Target / Behavior |
| :--- | :--- | :--- |
| `http://localhost/` | HTTP (Port 80) | Root landing page (auto-redirects to `/app`) |
| `http://localhost/app` | HTTP (Port 80) | Customer Management Web Application |
| `https://localhost/` | HTTPS (Port 443) | Encrypted root landing page |
| `https://localhost/app` | HTTPS (Port 443) | Encrypted Customer Management Web Application |

---

## 6. Automated Windows Monitoring Service Deployment Guide (`deploy-service.ps1`)

### 6.1 Deployment Command
```powershell
# Open PowerShell as Administrator
.\deploy-service.ps1
```

### 6.2 Service Management Commands
```powershell
# Check service status
Get-Service -Name "CustomerSpikeIisMonitor"

# View live log output
Get-Content -Path "C:\Services\CustomerSpikeIisMonitor\iis_monitor.log" -Wait -Tail 20

# Query SCM 300s failure / auto-recovery configuration
sc.exe qfailure "CustomerSpikeIisMonitor"

# Expected output:
# RESTART -- Delay = 300000 milliseconds.
# RESTART -- Delay = 300000 milliseconds.
# RESTART -- Delay = 300000 milliseconds.

# Stop service
Stop-Service -Name "CustomerSpikeIisMonitor"

# Start service
Start-Service -Name "CustomerSpikeIisMonitor"
```

### 6.3 300-Second Auto-Recovery Verification
1. Stop the target website: `Stop-WebSite -Name "CustomerSpike"`
2. Within 60 seconds, the monitoring worker detects failure, writes `SERVICE_FAILURE` to `iis_monitor.log`, and exits with code 1.
3. Restart the website: `Start-WebSite -Name "CustomerSpike"`
4. Exactly **300 seconds (5 minutes)** after termination, Windows SCM automatically restarts `CustomerSpikeIisMonitor` and normal logging resumes.

---

## 7. Containerized Deployment Guide (Docker & Compose)

### 7.1 Multi-Stage Container Architecture
- **Base:** `mcr.microsoft.com/dotnet/aspnet:10.0` running as non-root `$APP_UID` on Port 8080.
- **Build & Publish:** `mcr.microsoft.com/dotnet/sdk:10.0` compiles Release binaries.
- **Final:** Minimal production container runtime.

### 7.2 Deploying via PowerShell
```powershell
# Build and launch containerized application
.\deploy-docker.ps1 -Build

# Deploy on custom port (e.g. 9000)
.\deploy-docker.ps1 -HostPort 9000 -Environment "Production" -Build

# Access in browser: http://localhost:8080 (or custom port)
```

---

## 8. Continuous Integration & Delivery Pipeline (CI/CD)

Defined in `.github/workflows/ci.yml`:

```yaml
name: CI to integrate, build, test and package the application
on:
  push:
    branches: [ main, master ]
  pull_request:
    branches: [ main, master ]
  workflow_dispatch:

concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true

permissions:
  contents: read
```

### Pipeline Key Steps:
1. **Setup .NET SDK 10.0** with dependency caching (`cache: true`).
2. **Compile (`dotnet build --configuration Release`)**.
3. **Execute Unit Tests (`dotnet test`)** with TRX report generation.
4. **Publish Web App (`dotnet publish`)**.
5. **Compress into Zip Bundle (`CustomerManagementSpike-Web-app.zip`)** and upload artifact (14-day retention).
6. **Build & Push Docker Image** to Docker Hub (`latest` and commit SHA tags).
7. **Upload Test Results Artifact** (7-day retention).

---

## 9. Configuration Management & Parameters Reference

### 9.1 `appsettings.json` (Monitoring Service)
```json
{
  "Logging": {
    "LogLevel": {
      "Default": "Information",
      "Microsoft.Hosting.Lifetime": "Information",
      "CustomerManagementSpike": "Information"
    }
  },
  "Monitoring": {
    "WebsiteUrl": "http://localhost/",
    "CheckIntervalSeconds": 60,
    "RequestTimeoutSeconds": 15,
    "LogFileName": "iis_monitor.log",
    "StopOnNon200": true
  }
}
```

### 9.2 Script Parameters Summary

| Script | Parameter | Type | Default | Description |
| :--- | :--- | :--- | :--- | :--- |
| `deploy.ps1` | `-SiteName` | String | `CustomerSpike` | IIS Web Site name |
| `deploy.ps1` | `-AppPoolName` | String | `CustomerSpikeAppPool` | IIS Application Pool name |
| `deploy.ps1` | `-HttpPort` | Int | `80` | HTTP port |
| `deploy.ps1` | `-HttpsPort` | Int | `443` | HTTPS port |
| `deploy.ps1` | `-UserName` | String | `SpikeIISUser` | Dedicated local Windows user account |
| `deploy-service.ps1` | `-InstallPath`| String | `C:\Services\CustomerSpikeIisMonitor` | Service installation folder |
| `deploy-service.ps1` | `-TargetUrl` | String | `http://localhost/` | Target HTTP probe endpoint |
| `deploy-service.ps1` | `-CheckIntervalSeconds` | Int | `60` | Health check interval in seconds |
| `deploy-service.ps1` | `-RecoveryDelaySeconds` | Int | `300` | SCM auto-recovery restart delay (300s = 5m) |
| `deploy-docker.ps1` | `-HostPort` | Int | `8080` | Host port mapped to container port 8080 |
| `deploy-docker.ps1` | `-Build` | Switch | `False` | Forces container rebuild |

---

## 10. Troubleshooting & Operations Runbook

### 10.1 Diagnostic Checklist

| Issue | Probable Cause | Resolution |
| :--- | :--- | :--- |
| **HTTP 500.19 on IIS** | ASP.NET Core Hosting Bundle is missing. | Install ASP.NET Core 10 Hosting Bundle and restart WAS (`net stop was /y` then `net start w3svc`). |
| **HTTP 502.5 Process Failure** | Web application binaries missing or wrong .NET runtime. | Inspect stdout logs in `C:\inetpub\wwwroot\CustomerSpike\App\logs` and ensure .NET 10 is installed. |
| **Service Error 1069 (Logon Failure)** | Missing `SeServiceLogonRight` or password mismatch. | Re-run `deploy-service.ps1` as Administrator to grant user rights automatically via LSA API. |
| **HTTPS Certificate Warning** | Self-signed certificate is not in Trusted Root store. | Import localhost certificate from `Cert:\LocalMachine\My` into `Cert:\LocalMachine\Root`. |
| **Docker Port Conflict (8080)** | Host port 8080 is in use by another process. | Deploy on an alternate port: `.\deploy-docker.ps1 -HostPort 8090 -Build`. |

---

*Documentation generated for Customer Management Spike Project Deliverables.*
