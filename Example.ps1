# A very basic webhook handler.

Import-Module (Join-Path $PSScriptRoot 'PowerShellWebhook')

Start-PowerShellWebhookServer -ConfigFileDir $PSScriptRoot -OnWebhook {
    param($ActionName, $WebEvent)

    switch ($ActionName) {
        # To be called like this: http://desktop-computer:1234/powershell-webhook/beep-for-me
        # You can use the host name configured in your router, or an IP like "192.168.1.1". Use the external port from the config file.
        'beep-for-me' {
            Write-Host 'Beep!'
            [Console]::Beep()
        }
        'hows-this-and-that' {
            Import-Module Pode -Scope Local

            # See: https://badgerati.github.io/Pode/Functions/Responses/Write-PodeJsonResponse/
            Write-PodeJsonResponse -Value @{
                foo = 123
                bar = 'baz'
                # See: https://badgerati.github.io/Pode/Tutorials/WebEvent/
                actionName = $WebEvent.Parameters.action
            }
        }
        default {
            Import-Module Pode -Scope Local
            Set-PodeResponseStatus -Code 404
        }
    }
}
