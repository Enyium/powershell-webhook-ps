function Get-FreePortPair {
    param (
        [Parameter(Mandatory)] [int[]] $UsedPorts
    )

    $socket = [System.Net.Sockets.Socket]::new(
        [System.Net.Sockets.AddressFamily]::InterNetworkV6,
        [System.Net.Sockets.SocketType]::Stream,
        [System.Net.Sockets.ProtocolType]::Tcp
    )
    $socket.DualMode = $true

    $firstPort = 1024
    try {
        $socket.Bind([System.Net.IPEndPoint]::new([System.Net.IPAddress]::Any, 0))
        $firstPort = $socket.LocalEndPoint.Port
    } catch {
        $firstPort = [int]::MaxValue
    } finally {
        $socket.Close()
    }

    $ports = $null
    for (; $firstPort -le 60999; $firstPort++) {
        $ports = @()

        for ($offset = 0; $offset -lt 2; $offset++) {
            $isFree = $UsedPorts -notcontains $port

            if ($isFree) {
                $socket = [System.Net.Sockets.Socket]::new(
                    [System.Net.Sockets.AddressFamily]::InterNetworkV6,
                    [System.Net.Sockets.SocketType]::Stream,
                    [System.Net.Sockets.ProtocolType]::Tcp
                )
                $socket.DualMode = $true

                try {
                    $socket.Bind([System.Net.IPEndPoint]::new([System.Net.IPAddress]::Any, $firstPort + $offset))
                    $ports += $firstPort + $offset
                } catch {
                    $isFree = $false
                }

                $socket.Close()
            }

            if (-not $isFree) {
                break
            }
        }

        if ($ports.Count -eq 2) {
            break
        }
    }

    if ($null -ne $ports -and $ports.Count -eq 2) {
        return $ports
    } else {
        throw "No free port pair found."
    }
}

<##############################################################################>

# Ensure elevated privileges. (Alternative: `#Requires -RunAsAdministrator`.)
$currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($currentIdentity)
$isElevated = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isElevated) {
    throw "This script requires elevated privileges. Please restart the script in a command prompt with administrator rights."
}

#
Write-Host 'Welcome to the setup script.'
Write-Host 'You can rerun this script any time to update or reapply the settings to the system.'
Write-Host

# Ask whether to install/uninstall.
Write-Host 'Options:'
Write-Host '1. Install'
Write-Host '2. Uninstall'
$userInput = Read-Host 'Enter number'
Write-Host

$isInstalling = $false
switch ($userInput.Trim()) {
    '1' {
        $isInstalling = $true
    }
    '2' {
        $isInstalling = $false
    }
    default {
        throw "Invalid input."
    }
}

# Ask for ports.
$externalPort = $null
$internalPort = $null

if ($isInstalling) {
    Write-Host 'Port forwarding will be set up to avoid needing elevated privileges for the server on every run.'
    Write-Host 'Choose your external and internal server ports by entering two comma-separated numbers in that order (may be taken from old config file), or press Enter for auto-selection:'
    $userInput = Read-Host 'Ports'
    Write-Host

    if ($userInput -ne '') {
        $parts = $userInput.Split(',') | ForEach-Object { $_.Trim() -as [int] }

        if ($parts.Count -ne 2 -or $parts -contains $null) {
            throw "Invalid input."
        }

        $externalPort, $internalPort = $parts
    } else {
        # Find free port pair.
        $usedPorts = @(1433, 1434, 1521, 3306, 3389, 5432, 5900, 5985, 5986, 8080, 8443)
        $usedPorts += (
            netsh interface portproxy show all |
            Select-String -Pattern '(?:^| )(\d+)(?: |$)' -AllMatches |
            ForEach-Object { $_.Matches | ForEach-Object { $_.Groups[1].Value } }
            # (`Select-String` has idiotic behavior when first using `Out-String`, making `(?m)` and `\r?$` necessary.)
        )

        $externalPort, $internalPort = Get-FreePortPair $usedPorts
    }

    Write-Host "Server configured with external port $externalPort and internal port $internalPort."
    Write-Host 'Build your webhook URLs using the external port. This port is also recorded in the config file.'
    Write-Host
}

# Ask for firewall rule details.
$needsFirewallRule = $false
$firewallRuleName = 'AllowPowerShellWebhook_h8w4e7'
$firewallRuleRemoteAddress = $null

if ($isInstalling) {
    Write-Host 'To unblock network requests, specify a remote IP address (e.g., from your home automation system) to create a rule for the Windows firewall. Rerunning this setup will reset manual changes to this rule (manually add separate rule[s]).'
    Write-Host 'Press Enter to skip creating a firewall rule (still removing a previous one).'
    $userInput = Read-Host 'Remote IP'
    Write-Host

    $firewallRuleRemoteAddress = $userInput.Trim()
    $needsFirewallRule = $firewallRuleRemoteAddress -ne ''

    if ($needsFirewallRule -and -not [System.Net.IPAddress]::TryParse($firewallRuleRemoteAddress, [ref]$null)) {
        throw "Invalid input."
    }
}

<##############################################################################>

# Read config file.
$configFilePath = "$PSScriptRoot\config.json"
$hasConfigFile = Test-Path $configFilePath

$config = $null
if ($hasConfigFile) {
    $config = Get-Content $configFilePath | ConvertFrom-Json

    if ($null -eq $config.ExternalPort -or $null -eq $config.InternalPort) {
        throw "Invalid config file. Ports missing."
    }
}

<##############################################################################>

# Always uninstall first.
if (-not $isInstalling -and -not $hasConfigFile) {
    throw "No config file."
}

if ($hasConfigFile) {
    # Remove port forwarding.
    foreach ($command in @('v4tov4', 'v6tov4')) {
        $null = netsh interface portproxy delete $command listenport=$($config.ExternalPort)
    }
    Write-Host 'Removed port forwarding.'

    # # Delete config file.
    # if (-not $isInstalling) {
    #     Remove-Item $configFilePath
    # }
}

Remove-NetFirewallRule -Name $firewallRuleName -ErrorAction SilentlyContinue
if (-not $isInstalling) {
    Write-Host 'Removed firewall rule.'
}

if (-not $isInstalling) {
    Write-Host 'Uninstallation finished. You may delete the config file or keep it for future reference.'
    Write-Host
}

<##############################################################################>

# Install.
if ($isInstalling) {
    # Set up port forwarding.
    foreach ($command in @('v4tov4', 'v6tov4')) {
        $null = netsh interface portproxy add $command listenport=$externalPort connectaddress=127.0.0.1 connectport=$internalPort
    }

    # Create config file.
    $config = @{
        ExternalPort = $externalPort
        InternalPort = $internalPort
    }

    $config | ConvertTo-Json | Set-Content -Path $configFilePath

    # Create firewall rule.
    if ($needsFirewallRule) {
        $displayName = "PowerShell Webhook (From $firewallRuleRemoteAddress)"

        $null = New-NetFirewallRule `
            -Name $firewallRuleName `
            -DisplayName $displayName `
            -Direction Inbound `
            -Protocol TCP `
            -LocalPort $externalPort `
            -RemoteAddress $firewallRuleRemoteAddress `
            -Action Allow

        Write-Host "Created firewall rule ""$displayName""."
        Write-Host
    }

    #
    Write-Host 'Installation finished. Do not edit the config file manually.'
    Write-Host
}
