#Requires -Version 7.4
[CmdletBinding()]
param([string]$BasePath)

Import-Module (Join-Path $PSScriptRoot '..' 'LogicRipper' 'LogicRipper.psd1') -Force

if (-not $IsWindows) {
    throw 'Logic Ripper GUI uses WPF and must be launched on Windows.'
}

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
$reader = [System.Xml.XmlReader]::Create((Join-Path $PSScriptRoot 'MainWindow.xaml'))
$window = [Windows.Markup.XamlReader]::Load($reader)
$reader.Close()

function C([string]$Name) { $window.FindName($Name) }

$status = C StatusText
$activity = C ActivityLog
$tabs = C Tabs
$codeViewText = C CodeViewText
$findingsGrid = C FindingsGrid
$templateGrid = C TemplateGrid
$workspaceGrid = C WorkspaceGrid
$templateNameText = C TemplateNameText
$generatedText = C GeneratedCodeViewText
$script:WorkspaceValues = @{}
$script:BindingValues = @{}
$script:Analysis = $null
$script:TemplateId = $null
$script:ProfileId = $null
$script:BindingId = $null
$script:LastOutputPath = $null

function Say([string]$Message) {
    $status.Text = $Message
    $activity.AppendText("$(Get-Date -Format s) $Message`r`n")
    $activity.ScrollToEnd()
}

function Refresh-Lists {
    $templateGrid.ItemsSource = @(Get-LogicRipperTemplate -BasePath $BasePath)
    $workspaceGrid.ItemsSource = @(Get-LogicRipperTargetWorkspace -BasePath $BasePath)
}

function Show-Hashtable {
    param([hashtable]$Values, [object]$TextBox)
    $TextBox.Text = (($Values.GetEnumerator() | Sort-Object Name | ForEach-Object { "$($_.Key) = $($_.Value)" }) -join "`r`n")
}

function Move-Step([int]$Delta) {
    $tabs.SelectedIndex = [Math]::Max(0, [Math]::Min($tabs.Items.Count - 2, $tabs.SelectedIndex + $Delta))
}

function Mark-Selected([string]$Decision) {
    $finding = $findingsGrid.SelectedItem
    if (-not $finding) { Say 'Select one detected value first'; return }
    Set-LogicRipperFindingDecision -Analysis $script:Analysis -FindingId $finding.id -Decision $Decision | Out-Null
    $findingsGrid.ItemsSource = @($script:Analysis.findings)
    Say "Marked $($finding.path) as $Decision"
}

(C AnalyseButton).Add_Click({
    try {
        $script:Analysis = Invoke-LogicRipperAnalysis -CodeViewJson $codeViewText.Text
        $findingsGrid.ItemsSource = @($script:Analysis.findings)
        $tabs.SelectedIndex = 2
        Say "Analysis complete: $(@($script:Analysis.findings).Count) values need review"
    } catch { Say "Analyse local JSON failed: $($_.Exception.Message)" }
})

(C StartImportButton).Add_Click({
    $tabs.SelectedIndex = 1
    Say 'Import mode: paste code view and click Analyse local JSON'
})

(C StartExportButton).Add_Click({
    Refresh-Lists
    $tabs.SelectedIndex = 3
    Say 'Export mode: select a saved template, then select or add a workspace'
})

(C MarkReplaceButton).Add_Click({ Mark-Selected replace })
(C MarkPreserveButton).Add_Click({ Mark-Selected preserve })
(C MarkSecretButton).Add_Click({ Mark-Selected secret })

(C SaveTemplateButton).Add_Click({
    try {
        if (-not $script:Analysis) { throw 'Analyse local JSON first.' }
        if ([string]::IsNullOrWhiteSpace($templateNameText.Text)) { throw 'Template name is required.' }
        $saved = Save-LogicRipperTemplate -Name $templateNameText.Text -Analysis $script:Analysis -BasePath $BasePath
        $script:TemplateId = $saved.templateId
        Refresh-Lists
        foreach ($item in $templateGrid.ItemsSource) { if ($item.templateId -eq $script:TemplateId) { $templateGrid.SelectedItem = $item; break } }
        $tabs.SelectedIndex = 3
        Say "Template saved: $($saved.name)"
    } catch { Say "Save failed: $($_.Exception.Message)" }
})

(C AddWorkspaceButton).Add_Click({
    try {
        $name = (C WorkspaceNameText).Text
        if ([string]::IsNullOrWhiteSpace($name)) { throw 'Workspace name is required.' }
        $saved = New-LogicRipperTargetWorkspace -DisplayName $name -Values $script:WorkspaceValues -BasePath $BasePath
        $script:ProfileId = $saved.profileId
        Refresh-Lists
        foreach ($item in $workspaceGrid.ItemsSource) { if ($item.profileId -eq $script:ProfileId) { $workspaceGrid.SelectedItem = $item; break } }
        Say "Workspace added: $($saved.displayName)"
    } catch { Say "Add workspace failed: $($_.Exception.Message)" }
})

(C EditWorkspaceButton).Add_Click({
    try {
        $workspace = $workspaceGrid.SelectedItem
        if (-not $workspace) { throw 'Select one workspace first.' }
        $script:ProfileId = $workspace.profileId
        (C WorkspaceNameText).Text = $workspace.displayName
        $script:WorkspaceValues = @{}
        foreach ($p in $workspace.values.PSObject.Properties) { $script:WorkspaceValues[$p.Name] = [string]$p.Value }
        Show-Hashtable -Values $script:WorkspaceValues -TextBox (C WorkspaceValuesPreviewText)
        Say "Loaded workspace for editing: $($workspace.displayName)"
    } catch { Say "Edit workspace failed: $($_.Exception.Message)" }
})

(C AddWorkspaceValueButton).Add_Click({
    $name = (C WorkspaceValueNameText).Text
    $value = (C WorkspaceValueText).Text
    if ([string]::IsNullOrWhiteSpace($name) -or [string]::IsNullOrWhiteSpace($value)) { Say 'Enter one value name and value'; return }
    $script:WorkspaceValues[$name] = $value
    Show-Hashtable -Values $script:WorkspaceValues -TextBox (C WorkspaceValuesPreviewText)
    (C WorkspaceValueNameText).Text = ''
    (C WorkspaceValueText).Text = ''
    Say "Added workspace value $name"
})

(C SaveWorkspaceButton).Add_Click({
    try {
        $name = (C WorkspaceNameText).Text
        if ([string]::IsNullOrWhiteSpace($name)) { throw 'Workspace name is required.' }
        $saved = New-LogicRipperTargetWorkspace -DisplayName $name -Values $script:WorkspaceValues -BasePath $BasePath
        $script:ProfileId = $saved.profileId
        Refresh-Lists
        foreach ($item in $workspaceGrid.ItemsSource) { if ($item.profileId -eq $saved.profileId) { $workspaceGrid.SelectedItem = $item; break } }
        $tabs.SelectedIndex = 5
        Say "Workspace saved: $($saved.displayName)"
    } catch { Say "Workspace save failed: $($_.Exception.Message)" }
})

(C AddBindingValueButton).Add_Click({
    $name = (C BindingValueNameText).Text
    $value = (C BindingValueText).Text
    if ([string]::IsNullOrWhiteSpace($name) -or [string]::IsNullOrWhiteSpace($value)) { Say 'Enter one binding value name and value'; return }
    $script:BindingValues[$name] = $value
    Show-Hashtable -Values $script:BindingValues -TextBox (C BindingValuesPreviewText)
    (C BindingValueNameText).Text = ''
    (C BindingValueText).Text = ''
    Say "Added binding value $name"
})

(C SaveBindingButton).Add_Click({
    try {
        $template = $templateGrid.SelectedItem
        $workspace = $workspaceGrid.SelectedItem
        if (-not $template) { throw 'Select one template first.' }
        if (-not $workspace) { throw 'Select one workspace first.' }
        $binding = New-LogicRipperBinding -TemplateId $template.templateId -ProfileId $workspace.profileId -Values $script:BindingValues -BasePath $BasePath
        $script:TemplateId = $template.templateId
        $script:ProfileId = $workspace.profileId
        $script:BindingId = $binding.bindingId
        Say 'Binding saved for this template and workspace'
    } catch { Say "Save binding failed: $($_.Exception.Message)" }
})

(C GenerateButton).Add_Click({
    try {
        $template = $templateGrid.SelectedItem
        $workspace = $workspaceGrid.SelectedItem
        if (-not $template) { throw 'Save or select one template first.' }
        if (-not $workspace) { throw 'Select one workspace first.' }
        $binding = New-LogicRipperBinding -TemplateId $template.templateId -ProfileId $workspace.profileId -Values $script:BindingValues -BasePath $BasePath
        $script:BindingId = $binding.bindingId
        $generated = New-LogicRipperCodeView -TemplateId $template.templateId -ProfileId $workspace.profileId -BindingId $binding.bindingId -BasePath $BasePath
        $script:LastOutputPath = $generated.path
        $generatedText.Text = Get-Content -Raw -LiteralPath $generated.path
        Say "Generated code view"
    } catch { Say "Generate failed: $($_.Exception.Message)" }
})

(C CopyButton).Add_Click({ [Windows.Clipboard]::SetText($generatedText.Text); Say 'Copied generated JSON' })
(C OpenOutputButton).Add_Click({
    try {
        if (-not $script:LastOutputPath) { throw 'Generate code view first.' }
        Start-Process -FilePath (Split-Path -Parent $script:LastOutputPath)
        Say 'Opened output folder'
    } catch { Say "Open folder failed: $($_.Exception.Message)" }
})
(C NextButton).Add_Click({ Move-Step 1 })
(C BackButton).Add_Click({ Move-Step -1 })

Refresh-Lists
Say 'Ready'
$window.ShowDialog() | Out-Null
