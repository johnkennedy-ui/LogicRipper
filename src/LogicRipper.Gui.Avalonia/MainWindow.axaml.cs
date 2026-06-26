using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Threading.Tasks;
using Avalonia.Controls;
using Avalonia.Interactivity;
using LogicRipper.Gui.Avalonia.Models;

namespace LogicRipper.Gui.Avalonia;

public sealed partial class MainWindow : Window
{
    private readonly LogicRipperBackend _backend = new();
    private readonly ObservableCollection<FindingRow> _findings = new();
    private readonly ObservableCollection<TemplateRow> _templates = new();
    private readonly ObservableCollection<WorkspaceRow> _workspaces = new();
    private readonly Dictionary<string, string> _workspaceValues = new(StringComparer.OrdinalIgnoreCase);
    private readonly Dictionary<string, string> _bindingValues = new(StringComparer.OrdinalIgnoreCase);
    private JsonNode? _analysis;
    private JsonNode? _selectedTemplate;
    private JsonNode? _selectedWorkspace;
    private string? _selectedBindingId;
    private string? _lastOutputPath;
    private string? _basePath;

    public MainWindow()
    {
        InitializeComponent();
        FindingsGrid.ItemsSource = _findings;
        TemplatesGrid.ItemsSource = _templates;
        WorkspacesGrid.ItemsSource = _workspaces;
        WireEvents();
        _ = RefreshAllAsync();
    }

    private void WireEvents()
    {
        LoadJsonButton.Click += LoadJsonAsync;
        AnalyseButton.Click += AnalyseAsync;
        ClearButton.Click += (_, _) => { CodeViewText.Text = ""; Say("Cleared pasted JSON."); };
        MarkReplaceButton.Click += (_, _) => MarkSelected("replace");
        MarkPreserveButton.Click += (_, _) => MarkSelected("preserve");
        MarkSecretButton.Click += (_, _) => MarkSelected("secret");
        MarkReviewButton.Click += (_, _) => MarkSelected("reviewrequired");
        SaveTemplateButton.Click += SaveTemplateAsync;
        RefreshTemplatesButton.Click += async (_, _) => await RefreshTemplatesAsync();
        SelectTemplateButton.Click += SelectTemplateAsync;
        RenameTemplateButton.Click += RenameTemplateAsync;
        DeleteTemplateButton.Click += DeleteTemplateAsync;
        ViewTemplateValuesButton.Click += ViewTemplateValuesAsync;
        RefreshWorkspacesButton.Click += async (_, _) => await RefreshWorkspacesAsync();
        SelectWorkspaceButton.Click += SelectWorkspaceAsync;
        NewWorkspaceButton.Click += (_, _) => ClearWorkspaceForm();
        EditWorkspaceButton.Click += EditWorkspaceAsync;
        CloneWorkspaceButton.Click += CloneWorkspaceAsync;
        DeleteWorkspaceButton.Click += DeleteWorkspaceAsync;
        AddWorkspaceValueButton.Click += (_, _) => AddWorkspaceExtraValue();
        SaveWorkspaceButton.Click += SaveWorkspaceAsync;
        AddBindingValueButton.Click += (_, _) => AddBindingValue();
        SaveBindingButton.Click += SaveBindingAsync;
        GenerateButton.Click += GenerateAsync;
        CopyGeneratedButton.Click += CopyGeneratedAsync;
        SaveGeneratedButton.Click += SaveGeneratedAsync;
        OpenOutputButton.Click += OpenOutputFolder;
    }

    private async Task RefreshAllAsync()
    {
        await RefreshTemplatesAsync();
        await RefreshWorkspacesAsync();
    }

    private async void LoadJsonAsync(object? sender, RoutedEventArgs e)
    {
        var files = await StorageProvider.OpenFilePickerAsync(new global::Avalonia.Platform.Storage.FilePickerOpenOptions
        {
            Title = "Load Logic App code-view JSON",
            AllowMultiple = false
        });
        if (files.Count == 0) return;
        await using var stream = await files[0].OpenReadAsync();
        using var reader = new StreamReader(stream);
        CodeViewText.Text = await reader.ReadToEndAsync();
        Say("Loaded JSON file.");
    }

    private async void AnalyseAsync(object? sender, RoutedEventArgs e)
    {
        try
        {
            if (string.IsNullOrWhiteSpace(CodeViewText.Text)) throw new InvalidOperationException("Paste or load JSON first.");
            _analysis = await _backend.AnalyseAsync(CodeViewText.Text, _basePath);
            LoadFindings(_analysis);
            Tabs.SelectedIndex = 1;
            Say($"Analysed local JSON: {_findings.Count} detected values.");
        }
        catch (Exception ex) { Say("Analyse failed: " + ex.Message); }
    }

    private void MarkSelected(string decision)
    {
        if (FindingsGrid.SelectedItem is not FindingRow row || _analysis is null)
        {
            Say("Select one detected value first.");
            return;
        }

        foreach (var finding in _analysis["findings"]!.AsArray())
        {
            if (finding?["id"]?.GetValue<string>() != row.Id) continue;
            finding["decision"] = decision;
            row.SelectedAction = DisplayDecision(decision);
            row.RequiredStatus = RequiredStatusFor(finding);
            FindingsGrid.ItemsSource = null;
            FindingsGrid.ItemsSource = _findings;
            Say($"Marked {row.Path} as {row.SelectedAction}.");
            return;
        }
    }

    private async void SaveTemplateAsync(object? sender, RoutedEventArgs e)
    {
        try
        {
            if (_analysis is null) throw new InvalidOperationException("Analyse local JSON first.");
            if (string.IsNullOrWhiteSpace(TemplateNameText.Text)) throw new InvalidOperationException("Template name is required.");
            var result = await _backend.SaveTemplateAsync(TemplateNameText.Text, _analysis, _basePath);
            await RefreshTemplatesAsync();
            var id = result["templateId"]!.GetValue<string>();
            SelectTemplateRow(id);
            await LoadSelectedTemplateAsync(id);
            Tabs.SelectedIndex = 2;
            Say("Saved template.");
        }
        catch (Exception ex) { Say("Save template failed: " + ex.Message); }
    }

    private async Task RefreshTemplatesAsync()
    {
        _templates.Clear();
        var nodes = await _backend.ListTemplatesAsync(_basePath);
        foreach (var item in nodes.AsArray())
        {
            if (item is null) continue;
            _templates.Add(new TemplateRow
            {
                TemplateId = item["templateId"]?.GetValue<string>() ?? "",
                Name = item["name"]?.GetValue<string>() ?? "",
                SavedAt = item["savedAt"]?.GetValue<string>() ?? ""
            });
        }
    }

    private async void SelectTemplateAsync(object? sender, RoutedEventArgs e)
    {
        if (TemplatesGrid.SelectedItem is not TemplateRow row) { Say("Select one template first."); return; }
        await LoadSelectedTemplateAsync(row.TemplateId);
        Say("Selected template: " + row.Name);
    }

    private async Task LoadSelectedTemplateAsync(string templateId)
    {
        _selectedTemplate = await _backend.GetTemplateAsync(templateId, _basePath);
        LoadFindings(_selectedTemplate);
        UpdateSelectionSummary();
        UpdateMissingValues();
    }

    private async void RenameTemplateAsync(object? sender, RoutedEventArgs e)
    {
        try
        {
            if (TemplatesGrid.SelectedItem is not TemplateRow row) throw new InvalidOperationException("Select one template first.");
            if (string.IsNullOrWhiteSpace(TemplateNameText.Text)) throw new InvalidOperationException("Enter the new name in Template name.");
            await _backend.RenameTemplateAsync(row.TemplateId, TemplateNameText.Text, _basePath);
            await RefreshTemplatesAsync();
            SelectTemplateRow(row.TemplateId);
            Say("Renamed template.");
        }
        catch (Exception ex) { Say("Rename failed: " + ex.Message); }
    }

    private async void DeleteTemplateAsync(object? sender, RoutedEventArgs e)
    {
        try
        {
            if (TemplatesGrid.SelectedItem is not TemplateRow row) throw new InvalidOperationException("Select one template first.");
            await _backend.DeleteTemplateAsync(row.TemplateId, _basePath);
            _selectedTemplate = null;
            await RefreshTemplatesAsync();
            UpdateSelectionSummary();
            Say("Deleted template.");
        }
        catch (Exception ex) { Say("Delete failed: " + ex.Message); }
    }

    private async void ViewTemplateValuesAsync(object? sender, RoutedEventArgs e)
    {
        if (TemplatesGrid.SelectedItem is not TemplateRow row) { Say("Select one template first."); return; }
        var template = await _backend.GetTemplateAsync(row.TemplateId, _basePath);
        var lines = template["findings"]!.AsArray().Select(f => $"{f?["path"]} | {f?["kind"]} | {f?["decision"]} | {f?["replacementName"]}");
        TemplateValuesText.Text = string.Join(Environment.NewLine, lines);
    }

    private async Task RefreshWorkspacesAsync()
    {
        _workspaces.Clear();
        var nodes = await _backend.ListWorkspacesAsync(_basePath);
        foreach (var item in nodes.AsArray())
        {
            if (item is null) continue;
            var values = item["values"];
            _workspaces.Add(new WorkspaceRow
            {
                ProfileId = item["profileId"]?.GetValue<string>() ?? "",
                DisplayName = item["displayName"]?.GetValue<string>() ?? "",
                CustomerName = values?["customerName"]?.GetValue<string>() ?? "",
                EnvironmentName = values?["environmentName"]?.GetValue<string>() ?? "",
                SavedAt = item["savedAt"]?.GetValue<string>() ?? ""
            });
        }
    }

    private async void SelectWorkspaceAsync(object? sender, RoutedEventArgs e)
    {
        if (WorkspacesGrid.SelectedItem is not WorkspaceRow row) { Say("Select one workspace first."); return; }
        await LoadSelectedWorkspaceAsync(row.ProfileId);
        Say("Selected workspace: " + row.DisplayName);
    }

    private async Task LoadSelectedWorkspaceAsync(string profileId)
    {
        _selectedWorkspace = await _backend.GetWorkspaceAsync(profileId, _basePath);
        LoadWorkspaceForm(_selectedWorkspace);
        UpdateSelectionSummary();
        UpdateMissingValues();
    }

    private async void EditWorkspaceAsync(object? sender, RoutedEventArgs e)
    {
        if (WorkspacesGrid.SelectedItem is not WorkspaceRow row) { Say("Select one workspace first."); return; }
        await LoadSelectedWorkspaceAsync(row.ProfileId);
        Say("Loaded workspace for editing.");
    }

    private async void CloneWorkspaceAsync(object? sender, RoutedEventArgs e)
    {
        try
        {
            if (WorkspacesGrid.SelectedItem is not WorkspaceRow row) throw new InvalidOperationException("Select one workspace first.");
            var name = string.IsNullOrWhiteSpace(WorkspaceDisplayNameText.Text) ? row.DisplayName + " Copy" : WorkspaceDisplayNameText.Text;
            var clone = await _backend.CloneWorkspaceAsync(row.ProfileId, name, _basePath);
            await RefreshWorkspacesAsync();
            SelectWorkspaceRow(clone["profileId"]!.GetValue<string>());
            Say("Cloned workspace.");
        }
        catch (Exception ex) { Say("Clone failed: " + ex.Message); }
    }

    private async void DeleteWorkspaceAsync(object? sender, RoutedEventArgs e)
    {
        try
        {
            if (WorkspacesGrid.SelectedItem is not WorkspaceRow row) throw new InvalidOperationException("Select one workspace first.");
            await _backend.DeleteWorkspaceAsync(row.ProfileId, _basePath);
            _selectedWorkspace = null;
            ClearWorkspaceForm();
            await RefreshWorkspacesAsync();
            UpdateSelectionSummary();
            Say("Deleted workspace.");
        }
        catch (Exception ex) { Say("Delete failed: " + ex.Message); }
    }

    private void AddWorkspaceExtraValue()
    {
        if (string.IsNullOrWhiteSpace(WorkspaceExtraKeyText.Text) || string.IsNullOrWhiteSpace(WorkspaceExtraValueText.Text))
        {
            Say("Enter one workspace key and value.");
            return;
        }

        _workspaceValues[WorkspaceExtraKeyText.Text] = WorkspaceExtraValueText.Text;
        WorkspaceExtraKeyText.Text = "";
        WorkspaceExtraValueText.Text = "";
        ShowValues(WorkspaceValuesPreviewText, _workspaceValues);
        UpdateMissingValues();
    }

    private async void SaveWorkspaceAsync(object? sender, RoutedEventArgs e)
    {
        try
        {
            var values = CollectWorkspaceValues();
            if (string.IsNullOrWhiteSpace(WorkspaceDisplayNameText.Text)) throw new InvalidOperationException("displayName is required.");
            var id = _selectedWorkspace?["profileId"]?.GetValue<string>();
            var result = await _backend.SaveWorkspaceAsync(id, WorkspaceDisplayNameText.Text, values, _basePath);
            await RefreshWorkspacesAsync();
            SelectWorkspaceRow(result["profileId"]!.GetValue<string>());
            await LoadSelectedWorkspaceAsync(result["profileId"]!.GetValue<string>());
            Say("Saved target workspace.");
        }
        catch (Exception ex) { Say("Save workspace failed: " + ex.Message); }
    }

    private void AddBindingValue()
    {
        if (string.IsNullOrWhiteSpace(BindingKeyText.Text) || string.IsNullOrWhiteSpace(BindingValueText.Text))
        {
            Say("Enter one binding key and value.");
            return;
        }

        _bindingValues[BindingKeyText.Text] = BindingValueText.Text;
        BindingKeyText.Text = "";
        BindingValueText.Text = "";
        ShowValues(BindingPreviewText, _bindingValues);
        UpdateMissingValues();
    }

    private async void SaveBindingAsync(object? sender, RoutedEventArgs e)
    {
        try
        {
            var templateId = RequireTemplateId();
            var profileId = RequireProfileId();
            var result = await _backend.SaveBindingAsync(_selectedBindingId, templateId, profileId, _bindingValues, _basePath);
            _selectedBindingId = result["bindingId"]!.GetValue<string>();
            Say("Saved binding.");
        }
        catch (Exception ex) { Say("Save binding failed: " + ex.Message); }
    }

    private async void GenerateAsync(object? sender, RoutedEventArgs e)
    {
        try
        {
            var templateId = RequireTemplateId();
            var profileId = RequireProfileId();
            var binding = await _backend.SaveBindingAsync(_selectedBindingId, templateId, profileId, _bindingValues, _basePath);
            _selectedBindingId = binding["bindingId"]!.GetValue<string>();
            var generated = await _backend.GenerateAsync(templateId, profileId, _selectedBindingId, null, _basePath);
            _lastOutputPath = generated["path"]!.GetValue<string>();
            GeneratedJsonText.Text = await File.ReadAllTextAsync(_lastOutputPath);
            ValidationStatusText.Text = "Validation status: " + (generated["validation"]?["status"]?.GetValue<string>() ?? "generated");
            Say("Generated target code-view JSON.");
        }
        catch (Exception ex)
        {
            ValidationStatusText.Text = "Validation status: failed";
            Say("Generate failed: " + ex.Message);
        }
    }

    private async void CopyGeneratedAsync(object? sender, RoutedEventArgs e)
    {
        if (string.IsNullOrWhiteSpace(GeneratedJsonText.Text)) { Say("Generate JSON first."); return; }
        await Clipboard!.SetTextAsync(GeneratedJsonText.Text);
        Say("Copied generated JSON to clipboard.");
    }

    private async void SaveGeneratedAsync(object? sender, RoutedEventArgs e)
    {
        if (string.IsNullOrWhiteSpace(GeneratedJsonText.Text)) { Say("Generate JSON first."); return; }
        var file = await StorageProvider.SaveFilePickerAsync(new global::Avalonia.Platform.Storage.FilePickerSaveOptions
        {
            Title = "Save generated code-view JSON",
            SuggestedFileName = "codeview.json"
        });
        if (file is null) return;
        await using var stream = await file.OpenWriteAsync();
        await using var writer = new StreamWriter(stream);
        await writer.WriteAsync(GeneratedJsonText.Text);
        Say("Saved generated JSON to file.");
    }

    private void OpenOutputFolder(object? sender, RoutedEventArgs e)
    {
        try
        {
            if (string.IsNullOrWhiteSpace(_lastOutputPath)) throw new InvalidOperationException("Generate JSON first.");
            var dir = Path.GetDirectoryName(_lastOutputPath)!;
            if (OperatingSystem.IsLinux())
            {
                Process.Start(new ProcessStartInfo { FileName = "xdg-open", ArgumentList = { dir }, UseShellExecute = false });
            }
            else
            {
                Process.Start(new ProcessStartInfo { FileName = dir, UseShellExecute = true });
            }
            Say("Opened output folder.");
        }
        catch (Exception ex) { Say("Open output folder failed: " + ex.Message); }
    }

    private void LoadFindings(JsonNode node)
    {
        _findings.Clear();
        var findings = node["findings"]?.AsArray() ?? new JsonArray();
        foreach (var finding in findings)
        {
            if (finding is null) continue;
            _findings.Add(new FindingRow
            {
                Id = finding["id"]?.GetValue<string>() ?? "",
                Path = finding["path"]?.GetValue<string>() ?? "",
                ValuePreview = Preview(finding["value"]?.GetValue<string>() ?? ""),
                DetectedType = finding["kind"]?.GetValue<string>() ?? "",
                RecommendedAction = RecommendedAction(finding),
                SelectedAction = DisplayDecision(finding["decision"]?.GetValue<string>() ?? ""),
                ReplacementKey = finding["replacementName"]?.GetValue<string>() ?? "",
                RequiredStatus = RequiredStatusFor(finding)
            });
        }
    }

    private Dictionary<string, string> CollectWorkspaceValues()
    {
        AddIfNotBlank(_workspaceValues, "displayName", WorkspaceDisplayNameText.Text);
        AddIfNotBlank(_workspaceValues, "customerName", CustomerNameText.Text);
        AddIfNotBlank(_workspaceValues, "environmentName", EnvironmentNameText.Text);
        AddIfNotBlank(_workspaceValues, "tenantId", TenantIdText.Text);
        AddIfNotBlank(_workspaceValues, "subscriptionId", SubscriptionIdText.Text);
        AddIfNotBlank(_workspaceValues, "resourceGroupName", ResourceGroupNameText.Text);
        AddIfNotBlank(_workspaceValues, "location", LocationText.Text);
        AddIfNotBlank(_workspaceValues, "workspaceName", WorkspaceNameText.Text);
        AddIfNotBlank(_workspaceValues, "workspaceResourceId", WorkspaceResourceIdText.Text);
        AddIfNotBlank(_workspaceValues, "workspaceCustomerId", WorkspaceCustomerIdText.Text);
        AddIfNotBlank(_workspaceValues, "defaultLogicAppResourceGroup", DefaultLogicAppResourceGroupText.Text);
        AddIfNotBlank(_workspaceValues, "defaultRuntimeIdentityType", DefaultRuntimeIdentityTypeText.Text);
        AddIfNotBlank(_workspaceValues, "defaultRuntimeIdentityResourceId", DefaultRuntimeIdentityResourceIdText.Text);
        AddIfNotBlank(_workspaceValues, "defaultRuntimeIdentityClientId", DefaultRuntimeIdentityClientIdText.Text);
        AddIfNotBlank(_workspaceValues, "defaultRuntimeIdentityPrincipalId", DefaultRuntimeIdentityPrincipalIdText.Text);
        AddIfNotBlank(_workspaceValues, "defaultConnections", DefaultConnectionsText.Text);
        AddIfNotBlank(_workspaceValues, "defaultTags", DefaultTagsText.Text);
        ShowValues(WorkspaceValuesPreviewText, _workspaceValues);
        return new Dictionary<string, string>(_workspaceValues, StringComparer.OrdinalIgnoreCase);
    }

    private void LoadWorkspaceForm(JsonNode workspace)
    {
        ClearWorkspaceForm();
        WorkspaceDisplayNameText.Text = workspace["displayName"]?.GetValue<string>() ?? "";
        var values = workspace["values"]?.AsObject();
        if (values is null) return;
        foreach (var (key, value) in values) _workspaceValues[key] = value?.GetValue<string>() ?? "";
        CustomerNameText.Text = GetValue("customerName");
        EnvironmentNameText.Text = GetValue("environmentName");
        TenantIdText.Text = GetValue("tenantId");
        SubscriptionIdText.Text = GetValue("subscriptionId");
        ResourceGroupNameText.Text = GetValue("resourceGroupName");
        LocationText.Text = GetValue("location");
        WorkspaceNameText.Text = GetValue("workspaceName");
        WorkspaceResourceIdText.Text = GetValue("workspaceResourceId");
        WorkspaceCustomerIdText.Text = GetValue("workspaceCustomerId");
        DefaultLogicAppResourceGroupText.Text = GetValue("defaultLogicAppResourceGroup");
        DefaultRuntimeIdentityTypeText.Text = GetValue("defaultRuntimeIdentityType");
        DefaultRuntimeIdentityResourceIdText.Text = GetValue("defaultRuntimeIdentityResourceId");
        DefaultRuntimeIdentityClientIdText.Text = GetValue("defaultRuntimeIdentityClientId");
        DefaultRuntimeIdentityPrincipalIdText.Text = GetValue("defaultRuntimeIdentityPrincipalId");
        DefaultConnectionsText.Text = GetValue("defaultConnections");
        DefaultTagsText.Text = GetValue("defaultTags");
        ShowValues(WorkspaceValuesPreviewText, _workspaceValues);

        string GetValue(string key) => _workspaceValues.TryGetValue(key, out var v) ? v : "";
    }

    private void ClearWorkspaceForm()
    {
        _workspaceValues.Clear();
        _selectedWorkspace = null;
        foreach (var box in new[] { WorkspaceDisplayNameText, CustomerNameText, EnvironmentNameText, TenantIdText, SubscriptionIdText, ResourceGroupNameText, LocationText, WorkspaceNameText, WorkspaceResourceIdText, WorkspaceCustomerIdText, DefaultLogicAppResourceGroupText, DefaultRuntimeIdentityTypeText, DefaultRuntimeIdentityResourceIdText, DefaultRuntimeIdentityClientIdText, DefaultRuntimeIdentityPrincipalIdText, DefaultConnectionsText, DefaultTagsText })
        {
            box.Text = "";
        }
        WorkspaceValuesPreviewText.Text = "";
    }

    private void UpdateSelectionSummary()
    {
        var template = _selectedTemplate?["name"]?.GetValue<string>() ?? "(none)";
        var workspace = _selectedWorkspace?["displayName"]?.GetValue<string>() ?? "(none)";
        SelectionSummaryText.Text = $"Template: {template} | Target workspace: {workspace}";
    }

    private void UpdateMissingValues()
    {
        if (_selectedTemplate is null)
        {
            MissingValuesText.Text = "Missing required values: select a template first.";
            return;
        }

        var workspaceValues = _selectedWorkspace?["values"]?.AsObject();
        var missing = new List<string>();
        foreach (var finding in _selectedTemplate["findings"]!.AsArray())
        {
            if (finding?["decision"]?.GetValue<string>() != "replace") continue;
            var key = finding["replacementName"]?.GetValue<string>();
            if (string.IsNullOrWhiteSpace(key)) continue;
            var hasBinding = _bindingValues.TryGetValue(key, out var bindingValue) && !string.IsNullOrWhiteSpace(bindingValue);
            var hasWorkspace = workspaceValues is not null && workspaceValues.TryGetPropertyValue(key, out var node) && !string.IsNullOrWhiteSpace(node?.GetValue<string>());
            if (!hasBinding && !hasWorkspace) missing.Add(key);
        }

        MissingValuesText.Text = missing.Count == 0 ? "Missing required values: none" : "Missing required values: " + string.Join(", ", missing.Distinct());
    }

    private string RequireTemplateId()
    {
        return _selectedTemplate?["templateId"]?.GetValue<string>() ?? throw new InvalidOperationException("Select one template first.");
    }

    private string RequireProfileId()
    {
        return _selectedWorkspace?["profileId"]?.GetValue<string>() ?? throw new InvalidOperationException("Select one target workspace first.");
    }

    private void SelectTemplateRow(string id)
    {
        TemplatesGrid.SelectedItem = _templates.FirstOrDefault(t => t.TemplateId == id);
    }

    private void SelectWorkspaceRow(string id)
    {
        WorkspacesGrid.SelectedItem = _workspaces.FirstOrDefault(w => w.ProfileId == id);
    }

    private static void AddIfNotBlank(IDictionary<string, string> values, string key, string? value)
    {
        if (!string.IsNullOrWhiteSpace(value)) values[key] = value;
    }

    private static void ShowValues(TextBox textBox, IDictionary<string, string> values)
    {
        textBox.Text = string.Join(Environment.NewLine, values.OrderBy(v => v.Key).Select(v => $"{v.Key} = {v.Value}"));
    }

    private static string Preview(string value)
    {
        return value.Length <= 120 ? value : value[..117] + "...";
    }

    private static string RecommendedAction(JsonNode finding)
    {
        var kind = finding["kind"]?.GetValue<string>() ?? "";
        if (kind == "stableMicrosoftGuid") return "Preserve";
        if (kind == "secret") return "Secret";
        return "Replace";
    }

    private static string DisplayDecision(string decision)
    {
        return decision.ToLowerInvariant() switch
        {
            "replace" => "Replace",
            "preserve" => "Preserve",
            "secret" => "Secret",
            "reviewrequired" => "ReviewRequired",
            _ => "ReviewRequired"
        };
    }

    private static string RequiredStatusFor(JsonNode finding)
    {
        return (finding["decision"]?.GetValue<string>()) switch
        {
            "replace" => "Required",
            "secret" => "Blocks generation",
            "reviewrequired" => "Review required",
            _ => "Not required"
        };
    }

    private void Say(string message)
    {
        StatusText.Text = message;
        ActivityText.Text += $"{DateTimeOffset.Now:yyyy-MM-dd HH:mm:ss} {message}{Environment.NewLine}";
        ActivityText.CaretIndex = ActivityText.Text.Length;
    }
}
