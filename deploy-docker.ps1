param(
    [Parameter(Mandatory = $false)]
    [int]$HostPort = 8080,

    [Parameter(Mandatory = $false)]
    [string]$Environment = "Production",

    [Parameter(Mandatory = $false)]
    [switch]$Build
)

$env:HOST_PORT = $HostPort
$env:ENVIRONMENT = $Environment

Write-Host "Initializing deploy by Docker Compose ($Environment | Port: $HostPort )..." -ForegroundColor Cyan

if ($Build) {
    docker compose up -d --build --remove-orphans
} else {
    docker compose pull
    docker compose up -d --remove-orphans
}

if ($LASTEXITCODE -eq 0) {
    Write-Host "[OK] deploy was created! : http://localhost:$HostPort" -ForegroundColor Green
} else {
    Write-Host "[ERRO] failed to deploy by docker-compose." -ForegroundColor Red
    exit 1
}
