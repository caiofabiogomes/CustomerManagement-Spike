# Customer Management Spike (.NET Core Web Application & CI/CD Pipeline)

![CI Pipeline Status](https://github.com/caiofabiogomes/CustomerManagement-Spike/actions/workflows/ci.yml/badge.svg)

A modern .NET Core MVC Web Application complete with unit testing and an automated Continuous Integration (CI) pipeline using **GitHub Actions**.

---

## 🚀 Stages of Completion

### 1. Web Application in Version Control
- Built with **.NET 10 / .NET Core MVC architecture**.
- Managed with **Git** version control hosted on GitHub.
- Clean repository structure distinguishing application source code (`src/`) and automated test suites (`tests/`).
- Industry-standard `.gitignore` preventing build artifacts, binary outputs, user settings, and zip packages from polluting version history.

### 2. Automated CI Pipeline
- Fully automated workflow defined in [`.github/workflows/ci.yml`](.github/workflows/ci.yml).
- **Triggers**:
  - Automatically triggers on every `push` to `main` or `master` branches.
  - Automatically triggers on `pull_request` targetting `main` or `master`.
  - Manual trigger via `workflow_dispatch`.

### 3. Application Zip Packaging
- Compiles the application binaries using `dotnet publish` with `--configuration Release`.
- Compresses the compiled web app bundle into a clean `.zip` archive (`CustomerManagementSpike-Web-app.zip`).
- Uploads the `.zip` archive as a GitHub artifact (`actions/upload-artifact@v4`) for continuous delivery (CD) or deployment pipelines.

### 4. Implementation of Best Practices

#### Repository Best Practices
- **Solution Organization**: Clear separation of concerns with `CustomerManagementSpike.Web` in `src/` and `CustomerManagementSpike.Tests` in `tests/`.
- **Git Hygiene**: Strict `.gitignore` rules suppressing temporary files, intermediate build binaries, and generated zip archives.

#### Pipeline Efficiency & Security
- **NuGet Caching**: Utilizes `actions/setup-dotnet` built-in dependency caching to accelerate restore phases.
- **Concurrency Management**: automatically cancels redundant in-flight workflow runs when new commits are pushed (`cancel-in-progress: true`).
- **Least-Privilege Security**: Workflow runs with restricted scope (`permissions: contents: read`).
- **Quality Gates**: Enforces compilation, code format checks, and runs unit tests (`dotnet test`) prior to packaging.
- **Artifact Retention**: Configured explicit retention windows for published build packages (14 days) and test result logs (7 days).

---

## 🛠️ Repository Structure

```
CustomerManagement-Spike/
├── .github/
│   └── workflows/
│       └── ci.yml                 # GitHub Actions CI workflow definition
├── src/
│   └── CustomerManagementSpike.Web/ # .NET Web Application (MVC)
│       ├── Controllers/
│       ├── Models/
│       ├── Services/
│       ├── Views/
│       └── Program.cs
├── tests/
│   └── CustomerManagementSpike.Tests/ # Automated xUnit Test Suite
│       └── CustomerServiceTests.cs
├── CustomerManagement-Spike.slnx  # Solution file
├── .gitignore                      # Git ignore rules
└── README.md                       # Project documentation
```

---

## 💻 Local Development & Execution

### Prerequisites
- [.NET SDK 10.0](https://dotnet.microsoft.com/download) (or .NET Core 8.0+)

### Building the Project
```bash
dotnet build
```

### Running Unit Tests
```bash
dotnet test
```

### Running the Web Application
```bash
dotnet run --project src/CustomerManagementSpike.Web/CustomerManagementSpike.Web.csproj
```

### Publishing & Creating Zip Package Locally
```bash
dotnet publish src/CustomerManagementSpike.Web/CustomerManagementSpike.Web.csproj -c Release -o ./publish
```