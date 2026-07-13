[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$Command = "help",

    [Parameter(Position = 1, ValueFromRemainingArguments = $true)]
    [string[]]$CommandArguments
)

$ErrorActionPreference = "Stop"
$RootDirectory = $PSScriptRoot
$ProjectName = "lsr"
$ContainerName = "lsr-relay"
$RequiredCompose = [version]"2.20.0"
$SelectedDistroFile = Join-Path $RootDirectory ".local\active-distro"
$script:LabDistro = "ubuntu"

function Resolve-LabDistro {
    param([string]$Name)

    switch ($Name.ToLowerInvariant()) {
        "ubuntu" { return "ubuntu" }
        "debian" { return "debian" }
        "rocky" { return "rocky" }
        default { throw "Unknown distribution '$Name'. Run .\lab.ps1 distros to see supported targets." }
    }
}

function Get-DistroDisplay {
    param([string]$Name)

    switch ($Name) {
        "ubuntu" { return "Ubuntu 26.04 LTS" }
        "debian" { return "Debian 13" }
        "rocky" { return "Rocky Linux 10" }
        default { return $Name }
    }
}

function Get-SelectedDistro {
    if (Test-Path -LiteralPath $SelectedDistroFile) {
        return Resolve-LabDistro ((Get-Content -Raw -LiteralPath $SelectedDistroFile).Trim())
    }
    return "ubuntu"
}

function Set-DistroContext {
    param([string]$Name)

    $script:LabDistro = Resolve-LabDistro $Name
    $env:LAB_DISTRO = $script:LabDistro
}

function Save-SelectedDistro {
    $directory = Split-Path -Parent $SelectedDistroFile
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
    Set-Content -LiteralPath $SelectedDistroFile -Value $script:LabDistro -NoNewline
}

function Test-ContainerExists {
    & docker container inspect $ContainerName *> $null
    return $LASTEXITCODE -eq 0
}

function Test-ContainerRunning {
    $value = & docker container inspect --format "{{.State.Running}}" $ContainerName 2>$null
    return $LASTEXITCODE -eq 0 -and $value -eq "true"
}

function Get-ContainerDistro {
    $value = & docker container inspect --format '{{index .Config.Labels "cloudsprocket.distro"}}' $ContainerName 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $value -or $value -eq "<no value>") { return "" }
    return $value
}

function Use-ContainerDistro {
    if (Test-ContainerExists) {
        $actual = Get-ContainerDistro
        if ($actual) { Set-DistroContext $actual }
    }
}

function Assert-Running {
    if (-not (Test-ContainerRunning)) {
        throw "The lab is not running. Start it with .\lab.ps1 up."
    }
}

function Resolve-Drill {
    param([string]$Name)

    switch ($Name) {
        { $_ -in @("01", "service-failure", "01-service-failure") } { return "01-service-failure" }
        { $_ -in @("02", "full-filesystem", "02-full-filesystem") } { return "02-full-filesystem" }
        default { throw "Unknown drill '$Name'. Run .\lab.ps1 drills to see the available incidents." }
    }
}

function Invoke-Doctor {
    $failures = 0
    Write-Host "Linux Server Rescue doctor`n"
    Write-Host "Target distribution: $(Get-DistroDisplay $script:LabDistro) ($script:LabDistro)"

    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        Write-Host "FAIL  Docker was not found. Install Docker Engine or Docker Desktop."
        return 1
    }
    Write-Host "PASS  Docker CLI is installed."

    & docker info *> $null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "FAIL  The Docker daemon is not reachable. Start Docker and try again."
        return 1
    }
    Write-Host "PASS  Docker daemon is reachable."

    $composeText = & docker compose version --short 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "FAIL  Docker Compose v2 is unavailable. Update Docker or install the Compose plugin."
        $failures++
    }
    else {
        $normalised = ($composeText -replace '^v', '') -replace '-.*$', ''
        $composeVersion = [version]$normalised
        if ($composeVersion -lt $RequiredCompose) {
            Write-Host "FAIL  Docker Compose $composeVersion is too old; version $RequiredCompose or later is required."
            $failures++
        }
        else {
            Write-Host "PASS  Docker Compose $composeVersion meets the $RequiredCompose minimum."
        }
    }

    $holders = @(& docker ps --filter "publish=8100" --format "{{.Names}}" 2>$null)
    $otherHolders = @($holders | Where-Object { $_ -and $_ -ne $ContainerName })
    foreach ($holder in $otherHolders) {
        $label = & docker inspect --format '{{index .Config.Labels "cloudsprocket.lab"}}' $holder 2>$null
        if (-not $label -or $label -eq "<no value>") { $label = "unlabelled container" }
        Write-Host "FAIL  Port 8100 is held by $holder ($label). Stop it before starting this lab."
        $failures++
    }
    if ($otherHolders.Count -eq 0) {
        Write-Host "PASS  Port 8100 is available to this lab."
    }

    if ((Test-ContainerExists) -and -not (Test-ContainerRunning)) {
        Write-Host "WARN  A stopped $ContainerName container exists. lab up will recover it; lab reset will recreate it."
    }

    $root = [System.IO.Path]::GetPathRoot($RootDirectory)
    $drive = [System.IO.DriveInfo]::new($root)
    if ($drive.AvailableFreeSpace -lt 3GB) {
        Write-Host "WARN  Less than 3 GB is free on the project drive. An image build may fail."
    }
    else {
        Write-Host "PASS  Project drive has at least 3 GB free."
    }

    Write-Host "WARN  This lab uses a privileged container for real systemd. It is not a security boundary."
    Write-Host "      It mounts no Docker socket, host filesystem, home directory or SSH keys."

    if ($failures -eq 0) {
        Write-Host "`nDoctor found no blocking problems."
    }
    return $failures
}

function Show-Status {
    if (-not (Test-ContainerExists)) {
        Write-Host "Linux Server Rescue is down. Selected distribution: $(Get-DistroDisplay $script:LabDistro)."
        Write-Host "Start it with .\lab.ps1 up, or choose another target with .\lab.ps1 up <distribution>."
        return
    }

    $actual = Get-ContainerDistro
    if ($actual) { Set-DistroContext $actual }
    & docker compose --project-name $ProjectName --file (Join-Path $RootDirectory "compose.yaml") ps
    Write-Host "`nDistribution: $(Get-DistroDisplay $script:LabDistro) ($script:LabDistro)"
    Write-Host "Service URL: http://127.0.0.1:8100"
    if (Test-ContainerRunning) {
        $active = & docker exec $ContainerName sh -c 'cat /var/lib/cloudsprocket-lab/active-drill 2>/dev/null || true'
        if ($active) { Write-Host "Active drill: $active" } else { Write-Host "Active drill: none" }
    }
    else {
        Write-Host "Container is stopped. lab up will recover it; lab reset will recreate it."
    }
}

function Wait-LabReady {
    for ($attempt = 0; $attempt -lt 90; $attempt++) {
        if (Test-ContainerRunning) {
            $active = & docker exec $ContainerName sh -c 'cat /var/lib/cloudsprocket-lab/active-drill 2>/dev/null || true' 2>$null
            $health = & docker container inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{end}}' $ContainerName 2>$null

            if (-not $active -and $health -eq "healthy") {
                return
            }

            if ($active) {
                $systemState = & docker exec $ContainerName systemctl is-system-running 2>$null
                if ($systemState -in @("running", "degraded")) {
                    return
                }
            }
        }
        Start-Sleep -Seconds 1
    }

    & docker compose --project-name $ProjectName --file (Join-Path $RootDirectory "compose.yaml") ps
    throw "The lab did not reach a ready or diagnosable incident state."
}

function Start-Lab {
    param([string]$RequestedDistro)

    $requested = Resolve-LabDistro $(if ($RequestedDistro) { $RequestedDistro } else { $script:LabDistro })
    if (Test-ContainerExists) {
        $actual = Get-ContainerDistro
        if ($actual -and $actual -ne $requested) {
            throw "$(Get-DistroDisplay $actual) is already present. Run .\lab.ps1 down before switching to $(Get-DistroDisplay $requested)."
        }
    }

    Set-DistroContext $requested
    if ((Invoke-Doctor) -ne 0) { throw "Doctor found blocking problems." }
    Write-Host "`nBuilding and starting $(Get-DistroDisplay $script:LabDistro)..."
    & docker compose --project-name $ProjectName --file (Join-Path $RootDirectory "compose.yaml") up --build --detach
    if ($LASTEXITCODE -ne 0) { throw "Docker Compose could not start the lab." }
    Wait-LabReady
    Save-SelectedDistro
    Show-Status
}

function Stop-Lab {
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) { throw "Docker was not found." }
    Use-ContainerDistro
    & docker compose --project-name $ProjectName --file (Join-Path $RootDirectory "compose.yaml") down --remove-orphans
    if ($LASTEXITCODE -ne 0) { throw "Docker Compose could not stop the lab." }
    Write-Host "Linux Server Rescue is down. $(Get-DistroDisplay $script:LabDistro) drill state is preserved; lab reset clears it."
}

function Reset-Lab {
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) { throw "Docker was not found." }
    Use-ContainerDistro
    Write-Host "Removing only $(Get-DistroDisplay $script:LabDistro) resources in the $ProjectName Compose project, including its state volume..."
    & docker compose --project-name $ProjectName --file (Join-Path $RootDirectory "compose.yaml") down --volumes --remove-orphans
    if ($LASTEXITCODE -ne 0) { throw "Docker Compose could not clear the lab." }
    Start-Lab $script:LabDistro
}

function Invoke-Break {
    param([string]$Name)
    Assert-Running
    $drill = Resolve-Drill $Name
    & docker exec --user root $ContainerName "/opt/lab/drills/break/$drill.sh"
    if ($LASTEXITCODE -ne 0) { throw "The incident could not be applied." }
}

function Invoke-Verify {
    param([string]$Name)
    Assert-Running
    $drill = Resolve-Drill $Name
    & docker exec --user root $ContainerName "/opt/lab/drills/checks/$drill.sh"
    exit $LASTEXITCODE
}

function Invoke-Check {
    param([string]$Exercise)
    Assert-Running
    if (-not $Exercise) { throw "Provide an exercise number." }
    & docker exec $ContainerName test -x "/opt/lab/checks/$Exercise.sh"
    if ($LASTEXITCODE -ne 0) { throw "Exercise '$Exercise' is not available in this early build." }
    & docker exec --user root $ContainerName "/opt/lab/checks/$Exercise.sh"
    exit $LASTEXITCODE
}

function Show-Distributions {
    Write-Host "ubuntu  Ubuntu 26.04 LTS  apt  Debian family (default)"
    Write-Host "debian  Debian 13         apt  Upstream Debian stable"
    Write-Host "rocky   Rocky Linux 10    dnf  RHEL-compatible enterprise Linux"
}

function Show-Usage {
    @"
Usage: .\lab.ps1 <command> [argument]

Commands:
  up [distribution]   Build and start the selected distribution
  down               Stop and remove lab containers
  reset              Recreate the selected distribution and clear its drill state
  status             Show distribution, health, URL and active drill
  doctor [distro]    Check local requirements and conflicts
  check <exercise>   Run an exercise check
  break <drill>      Apply an incident
  verify <drill>     Verify a repair without changing state
  drills             List incidents
  distros            List supported Linux distributions
  shell              Open a shell on relay as the rescue user
  logs               Follow container logs
  version            Print the lab version
"@
}

try {
    Set-DistroContext (Get-SelectedDistro)
    $argument = if ($CommandArguments.Count -gt 0) { $CommandArguments[0] } else { "" }
    switch ($Command.ToLowerInvariant()) {
        "up" { Start-Lab $argument }
        "down" { Stop-Lab }
        "reset" { Reset-Lab }
        "status" { Show-Status }
        "doctor" {
            if ($argument) { Set-DistroContext $argument }
            exit (Invoke-Doctor)
        }
        "check" { Invoke-Check $argument }
        "break" { Invoke-Break $argument }
        "verify" { Invoke-Verify $argument }
        "drills" {
            Write-Host "01  service-failure  Beginner  Diagnose a service trapped in a restart loop."
            Write-Host "02  full-filesystem  Beginner  Recover an application filesystem with no free space."
        }
        "distros" { Show-Distributions }
        { $_ -in @("shell", "ssh") } {
            Assert-Running
            & docker exec --interactive --tty --user rescue --workdir /home/rescue $ContainerName bash
            exit $LASTEXITCODE
        }
        "logs" {
            Use-ContainerDistro
            & docker compose --project-name $ProjectName --file (Join-Path $RootDirectory "compose.yaml") logs --follow relay
            exit $LASTEXITCODE
        }
        "version" { (Get-Content -Raw (Join-Path $RootDirectory "VERSION")).Trim() }
        { $_ -in @("help", "-h", "--help") } { Show-Usage }
        default { throw "Unknown command '$Command'. Run .\lab.ps1 help." }
    }
}
catch {
    Write-Error $_.Exception.Message
    exit 1
}
