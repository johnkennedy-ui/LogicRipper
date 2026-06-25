@{
    RootModule = 'LogicRipper.psm1'
    ModuleVersion = '0.1.0'
    GUID = '3f66135f-3f2f-4ec5-bf06-11f5ad6994c1'
    Author = 'Logic Ripper contributors'
    CompanyName = 'Independent'
    Copyright = '(c) 2026 Logic Ripper contributors. MIT.'
    Description = 'Rip Microsoft Sentinel playbooks and Consumption Logic Apps into sanitised reusable ARM packages.'
    PowerShellVersion = '7.4'
    FunctionsToExport = @(
        'Get-LogicRipperPath',
        'Get-LogicRipperTemplate',
        'Rename-LogicRipperTemplate',
        'Import-LogicRipperWorkflow',
        'Invoke-LogicRipperBatchRip',
        'New-LogicRipperTargetWorkspace',
        'Get-LogicRipperTargetWorkspace',
        'Export-LogicRipperTargetWorkspace',
        'New-LogicRipperTemplateBinding',
        'Get-LogicRipperTemplateBinding',
        'Get-LogicRipperRequiredValueGuide',
        'Export-LogicRipperCodeView',
        'New-LogicRipperPackage',
        'Test-LogicRipperPackage',
        'Compare-LogicRipperWorkflowSemantic',
        'Get-LogicRipperWorkflowSupport',
        'Find-LogicRipperSecret',
        'Protect-LogicRipperDiagnosticObject'
    )
    CmdletsToExport = @()
    VariablesToExport = @()
    AliasesToExport = @()
}
