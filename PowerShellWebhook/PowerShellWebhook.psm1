function Start-PowerShellWebhookServer {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $ConfigFileDir,
        [Parameter(Mandatory)] [scriptblock] $OnWebhook
    )

    # Set window title.
    $origWindowTitle = $Host.UI.RawUI.WindowTitle
    $Host.UI.RawUI.WindowTitle = 'PowerShell Webhook'

    # Read config.
    $config = Get-Content (Join-Path $ConfigFileDir 'config.json') | ConvertFrom-Json
    if ($config.InternalPort -isnot [int32]) {
        throw "No valid internal port specified in config file."
    }

    # Block, handling HTTP requests.
    Start-PodeServer {
        New-PodeLoggingMethod -Terminal | Enable-PodeErrorLogging

        Add-PodeEndpoint -Address '127.0.0.1' -Port $config.InternalPort -Protocol Http

        Add-PodeRoute -Method 'Get' -Path '/' -ScriptBlock {
            $text = "This is the PowerShell Webhook server.`n`n"
            $text += "Invoke webhooks with a GET request and a path like: /powershell-webhook/your-action"

            Write-PodeTextResponse -Value $text
        }

        Add-PodeRoute -Method @('Get', 'Post') -Path '/powershell-webhook/:action' -ScriptBlock {
            & $using:OnWebhook -ActionName $WebEvent.Parameters.action -WebEvent $WebEvent
        }
    }

    # Restore old window title.
    $Host.UI.RawUI.WindowTitle = $origWindowTitle
}
