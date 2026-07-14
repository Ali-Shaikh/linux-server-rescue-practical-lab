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
$ActiveScenarioFile = Join-Path $RootDirectory ".local\active-scenario"
$DrillCatalogPath = Join-Path $RootDirectory "drills\catalog.tsv"
$script:LabDistro = "ubuntu"
$script:LabOverlay = ""
$script:DrillCatalog = @(Import-Csv -LiteralPath $DrillCatalogPath -Delimiter "`t")

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

function Invoke-LabCompose {
    param(
        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$ComposeArguments
    )

    $dockerArguments = @(
        "compose",
        "--project-name", $ProjectName,
        "--file", (Join-Path $RootDirectory "compose.yaml")
    )
    if ($script:LabOverlay) {
        $dockerArguments += @("--file", (Join-Path $RootDirectory $script:LabOverlay))
    }
    $dockerArguments += $ComposeArguments
    & docker @dockerArguments
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

    $query = $Name.ToLowerInvariant()
    $record = $script:DrillCatalog | Where-Object {
        $fullId = "$($_.id)-$($_.slug)"
        $query -in @($_.id, $_.slug, $fullId)
    } | Select-Object -First 1

    if (-not $record) {
        throw "Unknown drill '$Name'. Run .\lab.ps1 drills to see the available incidents."
    }
    return "$($record.id)-$($record.slug)"
}

function Get-DrillOverlay {
    param([string]$ResolvedName)

    $record = $script:DrillCatalog | Where-Object {
        "$($_.id)-$($_.slug)" -eq $ResolvedName
    } | Select-Object -First 1
    if (-not $record) { throw "Drill '$ResolvedName' is missing from the catalogue." }
    if ($record.overlay -eq "none") { return "" }
    return $record.overlay
}

function Get-DrillServices {
    param([string]$ResolvedName)

    $record = $script:DrillCatalog | Where-Object {
        "$($_.id)-$($_.slug)" -eq $ResolvedName
    } | Select-Object -First 1
    if (-not $record) { throw "Drill '$ResolvedName' is missing from the catalogue." }
    if ($record.services -eq "none") { return @() }

    $services = @($record.services -split ',')
    foreach ($service in $services) {
        if ($service -notmatch '^[a-z0-9][a-z0-9-]*$') {
            throw "Scenario service '$service' is not a safe Compose service name."
        }
    }
    return $services
}

function Get-DrillForOverlay {
    param([string]$Overlay)

    $record = $script:DrillCatalog | Where-Object { $_.overlay -eq $Overlay } |
        Select-Object -First 1
    if (-not $record) { throw "Scenario overlay $Overlay is not assigned to a drill." }
    return "$($record.id)-$($record.slug)"
}

function Assert-SafeScenarioOverlay {
    param([string]$Overlay)

    if ($Overlay -notmatch '^scenarios/[a-z0-9][a-z0-9-]*/compose\.yaml$' -or $Overlay.Contains("..")) {
        throw "Scenario overlay '$Overlay' is not a safe repository path."
    }
    if (-not ($script:DrillCatalog | Where-Object { $_.overlay -eq $Overlay })) {
        throw "Scenario overlay '$Overlay' is not listed in the drill catalogue."
    }
    if (-not (Test-Path -LiteralPath (Join-Path $RootDirectory $Overlay) -PathType Leaf)) {
        throw "Scenario overlay '$Overlay' does not exist."
    }
}

function Set-ScenarioContext {
    param([string]$Overlay)

    if ($Overlay) { Assert-SafeScenarioOverlay $Overlay }
    $script:LabOverlay = $Overlay
}

function Get-SavedScenarioOverlay {
    if (-not (Test-Path -LiteralPath $ActiveScenarioFile -PathType Leaf)) { return "" }
    $stored = (Get-Content -Raw -LiteralPath $ActiveScenarioFile).Trim()
    if (-not $stored) { return "" }
    Assert-SafeScenarioOverlay $stored
    return $stored
}

function Save-ScenarioOverlay {
    $directory = Split-Path -Parent $ActiveScenarioFile
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
    Set-Content -LiteralPath $ActiveScenarioFile -Value $script:LabOverlay -NoNewline
}

function Clear-ScenarioOverlay {
    Remove-Item -LiteralPath $ActiveScenarioFile -Force -ErrorAction SilentlyContinue
    $script:LabOverlay = ""
}

function Get-ActiveDrill {
    $active = [string](& docker exec $ContainerName sh -c 'cat /var/lib/cloudsprocket-lab/active-drill 2>/dev/null || true' 2>$null)
    return $active.Trim()
}

function Remove-ScenarioServices {
    param([string]$Drill)

    $services = @(Get-DrillServices $Drill)
    if ($services.Count -eq 0) { return }
    Invoke-LabCompose rm --stop --force @services
    if ($LASTEXITCODE -ne 0) {
        throw "The scenario services for $Drill could not be removed."
    }
}

function Restore-ScenarioContext {
    param([string]$PreviousOverlay)

    if ($PreviousOverlay) {
        Set-ScenarioContext $PreviousOverlay
        Save-ScenarioOverlay
    }
    else {
        Clear-ScenarioOverlay
    }
}

function Undo-ScenarioActivation {
    param(
        [string]$Drill,
        [string]$PreviousOverlay
    )

    try {
        Remove-ScenarioServices $Drill
        Restore-ScenarioContext $PreviousOverlay
        return $true
    }
    catch {
        try { Save-ScenarioOverlay } catch { }
        Write-Warning "Scenario cleanup failed; overlay state was retained for .\lab.ps1 reset."
        return $false
    }
}

function Sync-ScenarioState {
    $active = Get-ActiveDrill
    if (-not $script:LabOverlay) {
        if ($active) {
            $expectedOverlay = Get-DrillOverlay $active
            if ($expectedOverlay) {
                throw "Saved drill $active requires a missing scenario overlay. Run .\lab.ps1 reset."
            }
        }
        return
    }

    $overlayDrill = Get-DrillForOverlay $script:LabOverlay
    if (-not $active) {
        Write-Host "Cleaning up an uncommitted scenario for $overlayDrill..."
        Remove-ScenarioServices $overlayDrill
        Clear-ScenarioOverlay
        return
    }

    $expectedOverlay = Get-DrillOverlay $active
    if ($expectedOverlay -ne $script:LabOverlay) {
        throw "Saved drill $active and scenario overlay $script:LabOverlay are inconsistent. Run .\lab.ps1 reset."
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
    Write-Host "      It mounts only public lab content read-only; no Docker socket, home directory or SSH keys."

    if ($failures -eq 0) {
        Write-Host "`nDoctor found no blocking problems."
    }
    return $failures
}

function Show-Status {
    if (-not (Test-ContainerExists)) {
        Write-Host "Linux Server Rescue is down. Selected distribution: $(Get-DistroDisplay $script:LabDistro)."
        Write-Host "Start it with .\lab.ps1 up, or choose another target with .\lab.ps1 up <distribution>."
        Write-Host "Scenario overlay: $(if ($script:LabOverlay) { $script:LabOverlay } else { 'none' })"
        return
    }

    $actual = Get-ContainerDistro
    if ($actual) { Set-DistroContext $actual }
    Invoke-LabCompose ps
    Write-Host "`nDistribution: $(Get-DistroDisplay $script:LabDistro) ($script:LabDistro)"
    Write-Host "Service URL: http://127.0.0.1:8100"
    if (Test-ContainerRunning) {
        $active = & docker exec $ContainerName sh -c 'cat /var/lib/cloudsprocket-lab/active-drill 2>/dev/null || true'
        if ($active) { Write-Host "Active drill: $active" } else { Write-Host "Active drill: none" }
    }
    else {
        Write-Host "Container is stopped. lab up will recover it; lab reset will recreate it."
    }
    Write-Host "Scenario overlay: $(if ($script:LabOverlay) { $script:LabOverlay } else { 'none' })"
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

    Invoke-LabCompose ps
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
    Invoke-LabCompose up --build --detach
    if ($LASTEXITCODE -ne 0) { throw "Docker Compose could not start the lab." }
    Wait-LabReady
    Sync-ScenarioState
    Save-SelectedDistro
    Show-Status
}

function Stop-Lab {
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) { throw "Docker was not found." }
    Use-ContainerDistro
    Invoke-LabCompose down --remove-orphans
    if ($LASTEXITCODE -ne 0) { throw "Docker Compose could not stop the lab." }
    Write-Host "Linux Server Rescue is down. $(Get-DistroDisplay $script:LabDistro) drill state is preserved; lab reset clears it."
}

function Reset-Lab {
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) { throw "Docker was not found." }
    Use-ContainerDistro
    Write-Host "Removing only $(Get-DistroDisplay $script:LabDistro) resources in the $ProjectName Compose project, including its state volume..."
    Invoke-LabCompose down --volumes --remove-orphans
    if ($LASTEXITCODE -ne 0) { throw "Docker Compose could not clear the lab." }
    Clear-ScenarioOverlay
    Start-Lab $script:LabDistro
}

function Invoke-Break {
    param([string]$Name)
    Assert-Running
    Sync-ScenarioState
    $drill = Resolve-Drill $Name
    $overlay = Get-DrillOverlay $drill
    $active = Get-ActiveDrill
    $previousOverlay = ""

    if ($active -and $active -ne $drill) {
        throw "Cannot start $drill while $active is active. Run .\lab.ps1 reset first."
    }

    if ($overlay) {
        if ($script:LabOverlay -and $script:LabOverlay -ne $overlay) {
            throw "Scenario overlay $script:LabOverlay is active. Run .\lab.ps1 reset first."
        }
        $previousOverlay = $script:LabOverlay
        Set-ScenarioContext $overlay
        try {
            Save-ScenarioOverlay
        }
        catch {
            Restore-ScenarioContext $previousOverlay
            throw "Scenario state for $drill could not be saved."
        }
        Invoke-LabCompose up --build --detach
        if ($LASTEXITCODE -ne 0) {
            if (-not $active) {
                $null = Undo-ScenarioActivation $drill $previousOverlay
            }
            throw "The scenario services for $drill could not be started."
        }
        try {
            Wait-LabReady
        }
        catch {
            if (-not $active) {
                $null = Undo-ScenarioActivation $drill $previousOverlay
            }
            throw "The lab did not reach a ready state while starting $drill."
        }
    }
    elseif ($script:LabOverlay) {
        throw "Scenario overlay $script:LabOverlay is active. Run .\lab.ps1 reset first."
    }

    & docker exec --user root $ContainerName bash "/opt/lab/drills/break/$drill.sh"
    if ($LASTEXITCODE -ne 0) {
        $currentActive = Get-ActiveDrill
        if ($overlay -and -not $active -and -not $currentActive) {
            $null = Undo-ScenarioActivation $drill $previousOverlay
        }
        throw "The incident could not be applied."
    }
}

function Invoke-Verify {
    param([string]$Name)
    Assert-Running
    $drill = Resolve-Drill $Name
    & docker exec --user root $ContainerName bash "/opt/lab/drills/checks/$drill.sh"
    exit $LASTEXITCODE
}

function Invoke-Check {
    param([string]$Exercise)
    Assert-Running
    if (-not $Exercise) { throw "Provide an exercise number." }
    & docker exec $ContainerName test -f "/opt/lab/checks/$Exercise.sh"
    if ($LASTEXITCODE -ne 0) { throw "Exercise '$Exercise' is not available in this early build." }
    & docker exec --user root $ContainerName bash "/opt/lab/checks/$Exercise.sh"
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
    Set-ScenarioContext (Get-SavedScenarioOverlay)
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
            foreach ($record in $script:DrillCatalog) {
                Write-Host ("{0,-2}  {1,-22}  {2,-12}  {3}" -f `
                    $record.id, $record.slug, $record.difficulty, $record.description)
            }
        }
        "distros" { Show-Distributions }
        { $_ -in @("shell", "ssh") } {
            Assert-Running
            & docker exec --interactive --tty --user rescue --workdir /home/rescue $ContainerName bash
            exit $LASTEXITCODE
        }
        "logs" {
            Use-ContainerDistro
            Invoke-LabCompose logs --follow relay
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
