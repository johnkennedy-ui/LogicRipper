#Requires -Version 7.4
[CmdletBinding()]
param([string]$BasePath)

Import-Module (Join-Path $PSScriptRoot '..' 'LogicRipper' 'LogicRipper.psd1') -Force

if (-not $IsWindows) {
    throw 'Logic Ripper GUI uses WPF and must be launched on Windows. Use the LogicRipper module CLI commands on other platforms.'
}

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

$xamlPath = Join-Path $PSScriptRoot 'MainWindow.xaml'
$reader = [System.Xml.XmlReader]::Create($xamlPath)
$window = [Windows.Markup.XamlReader]::Load($reader)
$reader.Close()

function Find-Control([string]$Name) { $window.FindName($Name) }

$status = Find-Control 'StatusText'
$activity = Find-Control 'ActivityLog'
$templateGrid = Find-Control 'TemplateGrid'
$workspaceGrid = Find-Control 'WorkspaceGrid'
$outputFolder = Find-Control 'OutputFolderText'
$tabs = Find-Control 'Tabs'
$missingValues = Find-Control 'MissingValuesText'
$validationSummary = Find-Control 'ValidationSummaryText'
$templateNameText = Find-Control 'TemplateNameText'
$script:CurrentTemplateId = $null

function Add-Activity([string]$Message) {
    $activity.AppendText("$(Get-Date -Format s) $Message`r`n")
    $activity.ScrollToEnd()
    $status.Text = $Message
}

function Refresh-LogicRipperData {
    $templates = @(Get-LogicRipperTemplate -BasePath $BasePath)
    $workspaces = @(Get-LogicRipperTargetWorkspace -BasePath $BasePath)
    $templateGrid.ItemsSource = $templates
    $workspaceGrid.ItemsSource = $workspaces
    if (-not $outputFolder.Text) { $outputFolder.Text = Get-LogicRipperPath -Kind Generated -BasePath $BasePath }
}

function Move-Step([int]$Delta) {
    $next = [Math]::Max(0, [Math]::Min($tabs.Items.Count - 2, $tabs.SelectedIndex + $Delta))
    $tabs.SelectedIndex = $next
}

function Show-ValueGuide {
    $template = $templateGrid.SelectedItem
    if (-not $template) { return }
    $templateNameText.Text = $template.displayName
    $guide = @(Get-LogicRipperRequiredValueGuide -TemplateId $template.templateId -BasePath $BasePath)
    $missingValues.Text = (($guide | ForEach-Object { "$($_.name)`r`n$($_.guide)" }) -join "`r`n`r`n")
}

(Find-Control 'ImportTemplateButton').Add_Click({
    $dialog = [Microsoft.Win32.OpenFileDialog]::new()
    $dialog.Filter = 'Logic App JSON (*.json)|*.json'
    if ($dialog.ShowDialog()) {
        try {
            Add-Activity "Importing $($dialog.FileName)"
            $result = Import-LogicRipperWorkflow -WorkflowPath $dialog.FileName -BasePath $BasePath
            $script:CurrentTemplateId = $result.templateId
            Refresh-LogicRipperData
            foreach ($item in $templateGrid.ItemsSource) {
                if ($item.templateId -eq $script:CurrentTemplateId) { $templateGrid.SelectedItem = $item; break }
            }
            (Find-Control 'Tabs').SelectedIndex = 1
            Add-Activity 'Template imported'
        } catch { Add-Activity "Import failed: $($_.Exception.Message)" }
    }
})

(Find-Control 'RenameTemplateButton').Add_Click({
    $template = $templateGrid.SelectedItem
    if (-not $template) { Add-Activity 'Import or select a template first'; return }
    if ([string]::IsNullOrWhiteSpace($templateNameText.Text)) { Add-Activity 'Template name is required'; return }
    Rename-LogicRipperTemplate -TemplateId $template.templateId -DisplayName $templateNameText.Text -BasePath $BasePath | Out-Null
    Refresh-LogicRipperData
    Add-Activity 'Template name saved'
})

(Find-Control 'GeneratePackageButton').Add_Click({
    $template = $templateGrid.SelectedItem
    $workspace = $workspaceGrid.SelectedItem
    if (-not $template -or -not $workspace) { Add-Activity 'Select a template and target workspace first'; return }
    $scriptBlock = {
        param($modulePath,$base,$templateId,$profileId,$out)
        Import-Module $modulePath -Force
        Export-LogicRipperCodeView -TemplateId $templateId -TargetWorkspaceProfileId $profileId -BasePath $base -OutputPath $out
    }
    Add-Activity "Exporting code view $($template.displayName) for $($workspace.displayName)"
    $ps = [PowerShell]::Create()
    $null = $ps.AddScript($scriptBlock).AddArgument((Join-Path $PSScriptRoot '..' 'LogicRipper' 'LogicRipper.psd1')).AddArgument($BasePath).AddArgument($template.templateId).AddArgument($workspace.profileId).AddArgument($outputFolder.Text)
    $handle = $ps.BeginInvoke()
    Register-ObjectEvent -InputObject $handle -EventName AsyncWaitHandle -Action {} | Out-Null
    while (-not $handle.IsCompleted) {
        [Windows.Threading.Dispatcher]::CurrentDispatcher.Invoke([action]{}, [Windows.Threading.DispatcherPriority]::Background)
        Start-Sleep -Milliseconds 100
    }
    try { $result = $ps.EndInvoke($handle); Add-Activity "Exported: $($result.Path)" } catch { Add-Activity "Export failed: $($_.Exception.Message)" }
    $ps.Dispose()
})

(Find-Control 'NextButton').Add_Click({ Move-Step 1 })
(Find-Control 'BackButton').Add_Click({ Move-Step -1 })

$templateGrid.Add_SelectionChanged({ Show-ValueGuide })
$workspaceGrid.Add_SelectionChanged({
    $template = $templateGrid.SelectedItem
    $workspace = $workspaceGrid.SelectedItem
    if ($template -and $workspace) {
        $validationSummary.Text = "Template: $($template.displayName)`r`nWorkspace: $($workspace.displayName)`r`nOutput: codeview.json"
    }
})

Refresh-LogicRipperData
Add-Activity 'Ready'
$window.ShowDialog() | Out-Null
