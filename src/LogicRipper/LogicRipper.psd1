@{
    RootModule = 'LogicRipper.psm1'
    ModuleVersion = '0.3.0'
    GUID = '3f66135f-3f2f-4ec5-bf06-11f5ad6994c1'
    Author = 'Logic Ripper contributors'
    CompanyName = 'Independent'
    Copyright = '(c) 2026 Logic Ripper contributors. MIT.'
    Description = 'Local Logic App code-view transformer for reusable customer-safe templates.'
    PowerShellVersion = '7.4'
    FunctionsToExport = @(
        'Get-LogicRipperPath',
        'Get-LogicRipperCanonicalCodeView',
        'Invoke-LogicRipperAnalysis',
        'Set-LogicRipperFindingDecision',
        'Save-LogicRipperTemplate',
        'Get-LogicRipperTemplate',
        'Rename-LogicRipperTemplate',
        'New-LogicRipperTargetWorkspace',
        'Get-LogicRipperTargetWorkspace',
        'New-LogicRipperBinding',
        'Get-LogicRipperBinding',
        'New-LogicRipperCodeView',
        'Test-LogicRipperCodeView',
        'Get-LogicRipperValueGuide'
    )
    CmdletsToExport = @()
    VariablesToExport = @()
    AliasesToExport = @()
}
