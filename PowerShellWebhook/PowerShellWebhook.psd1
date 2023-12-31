@{
    RootModule = 'PowerShellWebhook.psm1'
    ModuleVersion = '0.1.0'
    GUID = '2c88cb90-14dd-4616-b73e-0b6f4ab2858f'

    PowerShellVersion = '5.1'
    RequiredModules = @(
        @{ ModuleName = "Pode"; MaximumVersion = "2.99.99"; GUID = 'e3ea217c-fc3d-406b-95d5-4304ab06c6af' }
    )

    FunctionsToExport = @("Start-PowerShellWebhookServer")
    CmdletsToExport = @()
    VariablesToExport = '*'
    AliasesToExport = @()
}
