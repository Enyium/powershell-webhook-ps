# This webhook handler is for use with the home automation system Homee. When someone suffering from non-24-hour sleep-wake disorder has homeegrams for their subjective-day phases, Homee can send webhook requests to this script, which, in turn, will control the screens' color temperature and brightness. The script will initially ask Homee for the currently applying s.-day phase and act accordingly. It should be started with Windows. In `enum SDayPhase`, one must enter their homeegram IDs. Transitions can be fine-tuned in `UpdateTransitionState()`.

Import-Module (Join-Path $PSScriptRoot 'PowerShellWebhook')

$homeeU = 'usr'
$homeeP = 'top-secret'

$n24HomeeHelper = 'n24-homee-helper'  # https://github.com/Enyium/n24-homee-helper-js
$nightLight = 'night-light.exe'  # https://github.com/Enyium/sem-reg-rs
$controlMyMonitor = 'C:\Portable_Programs\ControlMyMonitor\ControlMyMonitor.exe'  # https://www.nirsoft.net/utils/control_my_monitor.html

$transition = @{
    timer = $null
    sDayPhase = $null
    startTime = $null
    suspended = $false
}

function Main {
    # Ensure availability of some commands.
    foreach ($command in @($n24HomeeHelper, $nightLight, $controlMyMonitor)) {
        Get-Command $command -ErrorAction SilentlyContinue | Out-Null
        if (-not $?) {
            throw "Required command ""$command"" is missing."
        }
    }

    #
    Start-Process -FilePath $nightLight -ArgumentList 'keep-initing'
    Start-Sleep -Milliseconds 500

    # Prepare transition timer.
    $transition.timer = [System.Timers.Timer]::new(30 <#s#> * 1000)
    Register-ObjectEvent -InputObject $transition.timer -EventName Elapsed -Action { UpdateTransitionState } | Out-Null

    # Transition to currently applying s.-day phase. (Especially important for s. mornings when starting.)
    $sDayPhase, $phaseStartTime = Get-SDayPhase
    if ($null -ne $sDayPhase) {
        TransitionToSDayPhase $sDayPhase $phaseStartTime
    } else {
        Write-Host 'Warning: Couldn''t determine current s.-day phase.'
    }

    # Listen for webhook requests (blocks until Ctrl+C).
    Write-Host 'Starting webhook listener.'
    Start-PowerShellWebhookServer -ConfigFileDir $PSScriptRoot -OnWebhook { Invoke-WebhookAction @args }
}

function Get-SDayPhase {
    try {
        $runningHomeegrams = & $n24HomeeHelper -u $homeeU -p $homeeP dump-running-homeegrams | ConvertFrom-Json

        if ($runningHomeegrams -isnot [array]) {
            # Not an array.
            return @($null, $null)
        }
    } catch {
        # Invalid JSON.
        return @($null, $null)
    }

    $outSDayPhase = $null
    $outStartTime = $null

    foreach ($homeegram in $runningHomeegrams) {
        if (
            $homeegram -isnot [PSCustomObject] -or
            $homeegram.id -isnot [int32] -or
            $homeegram.start_epoch_secs -isnot [int32]
        ) {
            return @($null, $null)
        }

        $sDayPhase = $homeegram.id -as [SDayPhase]
        if ($null -ne $sDayPhase) {  # Valid phase?
            if ($null -eq $outSDayPhase) {
                $outSDayPhase = $sDayPhase
                $outStartTime = [DateTimeOffset]::FromUnixTimeSeconds($homeegram.start_epoch_secs).LocalDateTime
            } else {
                # Two s.-day phases active at the same time doesn't make sense.
                return @($null, $null)
            }
        }
    }

    return @($outSDayPhase, $outStartTime)
}

# Called by PowerShell Webhook.
function Invoke-WebhookAction {
    param($ActionName, $WebEvent)

    Log "Received request for webhook ""$ActionName""."

    switch ($ActionName) {
        'transition-to-s-morning-to-noon' {
            TransitionToSDayPhase ([SDayPhase]::MorningToNoon)
        }
        'transition-to-s-afternoon' {
            TransitionToSDayPhase ([SDayPhase]::Afternoon)
        }
        'transition-to-s-evening' {
            TransitionToSDayPhase ([SDayPhase]::Evening)
        }
        'transition-to-s-late-evening' {
            TransitionToSDayPhase ([SDayPhase]::LateEvening)
        }
        'transition-to-s-night' {
            TransitionToSDayPhase ([SDayPhase]::Night)
        }
        'suspend-transition' {
            $transition.suspended = $true
        }
        'resume-transition' {
            $transition.suspended = $false
        }
        'toggle-transition-suspended' {
            $transition.suspended = -not $transition.suspended
        }
        'test-beep' {
            [Console]::Beep()
        }
        default {
            Log "Webhook ""$ActionName"" isn't defined."

            Import-Module Pode -Scope Local
            Set-PodeResponseStatus -Code 404
        }
    }
}

function TransitionToSDayPhase {
    param(
        [Parameter(Mandatory)] [SDayPhase] $SDayPhase,
        [DateTime] $PhaseStartTime
    )

    $transition.timer.Stop()

    $transition.sDayPhase = $SDayPhase
    $transition.startTime = if ($null -ne $PhaseStartTime) { $PhaseStartTime } else { Get-Date }

    UpdateTransitionState
    $transition.timer.Start()
}

function UpdateTransitionState {
    if ($transition.suspended) {
        return
    }

    $phaseAgeMins = ((Get-Date) - $transition.startTime).TotalMinutes
    $hMin = { param($H, $Min) $H * 60 + $Min }

    Log "Updating s.-day phase ""$($transition.sDayPhase)"" transition (minute $([math]::Floor($phaseAgeMins)))."

    $sMorningToNoonLight = @{
        warmth = 0.0
        primaryMonitorBrightnessPct = 100
    }
    $sAfternoonLight = @{
        warmth = 0.17
        primaryMonitorBrightnessPct = 100
    }
    $sEveningLight = @{
        warmth = 0.57
        primaryMonitorBrightnessPct = 100
    }
    $sLateEveningLight = @{
        warmth = 0.63
        primaryMonitorBrightnessPct = 38
    }
    $sNightLight = @{
        warmth = 0.7
        primaryMonitorBrightnessPct = 0
    }

    switch ($transition.sDayPhase) {
        ([SDayPhase]::MorningToNoon) {
            & $nightLight switch --off --warmth 0  # Warmth 0 prevents strange transition when turning on again with less warmth.
            Set-MonitorBrightness -PrimaryPct 100
            $transition.timer.Stop()
        }
        ([SDayPhase]::Afternoon) {
            Set-LightOrEndTransition -Mins $phaseAgeMins -MaxMins (& $hMin 1 30) -From $sMorningToNoonLight -To $sAfternoonLight
        }
        ([SDayPhase]::Evening) {
            Set-LightOrEndTransition -Mins $phaseAgeMins -MaxMins (& $hMin 0 20) -From $sAfternoonLight -To $sEveningLight
        }
        ([SDayPhase]::LateEvening) {
            Set-LightOrEndTransition -Mins $phaseAgeMins -MaxMins (& $hMin 0 10) -From $sEveningLight -To $sLateEveningLight
        }
        ([SDayPhase]::Night) {
            Set-LightOrEndTransition -Mins $phaseAgeMins -MaxMins (& $hMin 0 0) -From $sLateEveningLight -To $sNightLight
        }
    }
}

function Set-LightOrEndTransition {
    param(
        [Parameter(Mandatory)] [double] $Mins,
        [Parameter(Mandatory)] [double] $MaxMins,
        [Parameter(Mandatory)] [HashTable] $From,
        [Parameter(Mandatory)] [HashTable] $To
    )

    if ($null -eq $From.warmth -or $null -eq $To.warmth) {
        throw '`HashTable` missing `warmth`.'
    }
    if ($null -eq $From.primaryMonitorBrightnessPct -or $null -eq $To.primaryMonitorBrightnessPct) {
        throw '`HashTable` missing `primaryMonitorBrightnessPct`.'
    }

    $progressFactor = if ($MaxMins -eq 0) { 1.0 } else { [math]::Max(0.0, [math]::Min($Mins / $MaxMins, 1.0)) }

    # Calculate values.
    $warmth = ($To.warmth - $From.warmth) * $progressFactor + $From.warmth

    $fromSecondaryMonitorBrightnessPct = $From.secondaryMonitorBrightnessPct
    $toSecondaryMonitorBrightnessPct = $To.secondaryMonitorBrightnessPct
    if ($null -eq $fromSecondaryMonitorBrightnessPct) {
        $fromSecondaryMonitorBrightnessPct = $From.primaryMonitorBrightnessPct
    }
    if ($null -eq $toSecondaryMonitorBrightnessPct) {
        $toSecondaryMonitorBrightnessPct = $To.primaryMonitorBrightnessPct
    }

    $primaryMonitorBrightnessPct = [math]::Round(($To.primaryMonitorBrightnessPct - $From.primaryMonitorBrightnessPct) * $progressFactor + $From.primaryMonitorBrightnessPct)
    $secondaryMonitorBrightnessPct = [math]::Round(($toSecondaryMonitorBrightnessPct - $fromSecondaryMonitorBrightnessPct) * $progressFactor + $fromSecondaryMonitorBrightnessPct)

    # Apply.
    & $nightLight switch --on --warmth $warmth --gamma

    $brightnessVcpCode = '10'  # VCP = virtual control panel
    & $controlMyMonitor /SetValue Primary $brightnessVcpCode $primaryMonitorBrightnessPct /SetValue Secondary $brightnessVcpCode $secondaryMonitorBrightnessPct

    # Finish.
    if ($progressFactor -ge 1.0) {
        $transition.timer.Stop()
    }
}

function Set-MonitorBrightness {
    param(
        [Parameter(Mandatory)] [byte] $PrimaryPct,
        [byte] $SecondaryPct
    )

    if ($null -eq $SecondaryPct) {
        $SecondaryPct = $PrimaryPct
    }

    $brightnessVcpCode = '10'  # VCP = virtual control panel
    & $controlMyMonitor /SetValue Primary $brightnessVcpCode $PrimaryPct /SetValue Secondary $brightnessVcpCode $SecondaryPct
}

enum SDayPhase {
    # The numbers are the homeegram IDs for the s.-day phases (in URLs of Homee web app).
    MorningToNoon = 3
    Afternoon = 13
    Evening = 2
    LateEvening = 12
    Night = 4
}

function Log {
    param([string] $Text)

    Write-Host "[$(Get-Date -Format 'HH:mm:ss.fff')] $Text"
}

Main
