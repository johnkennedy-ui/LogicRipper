namespace LogicRipper.Gui.Avalonia.Models;

public sealed class FindingRow
{
    public string Id { get; set; } = "";
    public string Path { get; set; } = "";
    public string ValuePreview { get; set; } = "";
    public string DetectedType { get; set; } = "";
    public string RecommendedAction { get; set; } = "";
    public string SelectedAction { get; set; } = "";
    public string ReplacementKey { get; set; } = "";
    public string RequiredStatus { get; set; } = "";
}

public sealed class TemplateRow
{
    public string TemplateId { get; set; } = "";
    public string Name { get; set; } = "";
    public string SavedAt { get; set; } = "";
}

public sealed class WorkspaceRow
{
    public string ProfileId { get; set; } = "";
    public string DisplayName { get; set; } = "";
    public string CustomerName { get; set; } = "";
    public string EnvironmentName { get; set; } = "";
    public string SavedAt { get; set; } = "";
}
