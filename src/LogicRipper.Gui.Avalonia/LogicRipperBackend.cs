using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Threading.Tasks;

namespace LogicRipper.Gui.Avalonia;

public sealed class LogicRipperBackend
{
    private readonly string _cliPath;

    public LogicRipperBackend(string? cliPath = null)
    {
        _cliPath = cliPath
            ?? Environment.GetEnvironmentVariable("LOGIC_RIPPER_CLI")
            ?? "logic-ripper";
    }

    public Task<JsonNode> AnalyseAsync(string codeViewJson, string? basePath)
    {
        return InvokeApiAsync(new JsonObject
        {
            ["action"] = "analyse",
            ["basePath"] = basePath,
            ["codeViewJson"] = codeViewJson
        });
    }

    public Task<JsonNode> SaveTemplateAsync(string name, JsonNode analysis, string? basePath)
    {
        return InvokeApiAsync(new JsonObject
        {
            ["action"] = "saveTemplate",
            ["basePath"] = basePath,
            ["name"] = name,
            ["analysis"] = analysis.DeepClone()
        });
    }

    public Task<JsonNode> ListTemplatesAsync(string? basePath)
    {
        return InvokeApiAsync(new JsonObject { ["action"] = "listTemplates", ["basePath"] = basePath });
    }

    public Task<JsonNode> GetTemplateAsync(string templateId, string? basePath)
    {
        return InvokeApiAsync(new JsonObject { ["action"] = "getTemplate", ["basePath"] = basePath, ["templateId"] = templateId });
    }

    public Task<JsonNode> RenameTemplateAsync(string templateId, string name, string? basePath)
    {
        return InvokeApiAsync(new JsonObject
        {
            ["action"] = "renameTemplate",
            ["basePath"] = basePath,
            ["templateId"] = templateId,
            ["name"] = name
        });
    }

    public Task<JsonNode> DeleteTemplateAsync(string templateId, string? basePath)
    {
        return InvokeApiAsync(new JsonObject { ["action"] = "deleteTemplate", ["basePath"] = basePath, ["templateId"] = templateId });
    }

    public Task<JsonNode> SaveWorkspaceAsync(string? profileId, string displayName, IDictionary<string, string> values, string? basePath)
    {
        return InvokeApiAsync(new JsonObject
        {
            ["action"] = "saveWorkspace",
            ["basePath"] = basePath,
            ["profileId"] = profileId,
            ["displayName"] = displayName,
            ["values"] = ToJsonObject(values)
        });
    }

    public Task<JsonNode> ListWorkspacesAsync(string? basePath)
    {
        return InvokeApiAsync(new JsonObject { ["action"] = "listWorkspaces", ["basePath"] = basePath });
    }

    public Task<JsonNode> GetWorkspaceAsync(string profileId, string? basePath)
    {
        return InvokeApiAsync(new JsonObject { ["action"] = "getWorkspace", ["basePath"] = basePath, ["profileId"] = profileId });
    }

    public Task<JsonNode> CloneWorkspaceAsync(string profileId, string displayName, string? basePath)
    {
        return InvokeApiAsync(new JsonObject
        {
            ["action"] = "cloneWorkspace",
            ["basePath"] = basePath,
            ["profileId"] = profileId,
            ["displayName"] = displayName
        });
    }

    public Task<JsonNode> DeleteWorkspaceAsync(string profileId, string? basePath)
    {
        return InvokeApiAsync(new JsonObject { ["action"] = "deleteWorkspace", ["basePath"] = basePath, ["profileId"] = profileId });
    }

    public Task<JsonNode> SaveBindingAsync(string? bindingId, string templateId, string profileId, IDictionary<string, string> values, string? basePath)
    {
        return InvokeApiAsync(new JsonObject
        {
            ["action"] = "saveBinding",
            ["basePath"] = basePath,
            ["bindingId"] = bindingId,
            ["templateId"] = templateId,
            ["profileId"] = profileId,
            ["values"] = ToJsonObject(values)
        });
    }

    public Task<JsonNode> ListBindingsAsync(string templateId, string profileId, string? basePath)
    {
        return InvokeApiAsync(new JsonObject
        {
            ["action"] = "listBindings",
            ["basePath"] = basePath,
            ["templateId"] = templateId,
            ["profileId"] = profileId
        });
    }

    public Task<JsonNode> GenerateAsync(string templateId, string profileId, string bindingId, string? outputPath, string? basePath)
    {
        return InvokeApiAsync(new JsonObject
        {
            ["action"] = "generate",
            ["basePath"] = basePath,
            ["templateId"] = templateId,
            ["profileId"] = profileId,
            ["bindingId"] = bindingId,
            ["outputPath"] = outputPath
        });
    }

    public async Task RunSmokeAsync(string fixturePath, string basePath)
    {
        var codeViewJson = await File.ReadAllTextAsync(fixturePath);
        var analysis = await AnalyseAsync(codeViewJson, basePath);
        foreach (var finding in analysis["findings"]!.AsArray())
        {
            if (finding is null) continue;
            var kind = finding["kind"]?.GetValue<string>() ?? "";
            finding["decision"] = kind is "stableMicrosoftGuid" ? "preserve" : "replace";
        }

        var template = await SaveTemplateAsync("GUI Bridge Smoke", analysis, basePath);
        var templateId = template["templateId"]!.GetValue<string>();
        var workspace = await SaveWorkspaceAsync(null, "GUI Smoke Workspace", new Dictionary<string, string>
        {
            ["notificationEmail"] = "soc@contoso.example",
            ["tenantId"] = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
            ["subscriptionId"] = "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb",
            ["sentinelConnectionId"] = "/subscriptions/bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb/resourceGroups/rg-contoso/providers/Microsoft.Web/connections/azuresentinel-contoso",
            ["sentinelConnectionName"] = "azuresentinel-contoso",
            ["sentinelManagedApiId"] = "/subscriptions/bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb/providers/Microsoft.Web/locations/uksouth/managedApis/azuresentinel"
        }, basePath);
        var profileId = workspace["profileId"]!.GetValue<string>();

        var templateFull = await GetTemplateAsync(templateId, basePath);
        var values = new Dictionary<string, string>();
        foreach (var finding in templateFull["findings"]!.AsArray())
        {
            if (finding?["decision"]?.GetValue<string>() != "replace") continue;
            var key = finding["replacementName"]!.GetValue<string>();
            values.TryAdd(key, DefaultValueFor(finding));
        }

        var binding = await SaveBindingAsync(null, templateId, profileId, values, basePath);
        var bindingId = binding["bindingId"]!.GetValue<string>();
        var generated = await GenerateAsync(templateId, profileId, bindingId, null, basePath);
        var path = generated["path"]!.GetValue<string>();
        if (!File.Exists(path)) throw new InvalidOperationException("Generated code view was not written.");
        _ = await File.ReadAllTextAsync(path);
    }

    private static string DefaultValueFor(JsonNode finding)
    {
        return (finding["kind"]?.GetValue<string>()) switch
        {
            "email" => "soc@contoso.example",
            "guid" => "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
            "connectorReferenceId" => "/subscriptions/bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb/resourceGroups/rg-contoso/providers/Microsoft.Web/connections/azuresentinel-contoso",
            "connectorReferenceName" => "azuresentinel-contoso",
            "managedApiId" => "/subscriptions/bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb/providers/Microsoft.Web/locations/uksouth/managedApis/azuresentinel",
            _ => "contoso-value"
        };
    }

    private async Task<JsonNode> InvokeApiAsync(JsonObject payload)
    {
        var payloadPath = Path.Combine(Path.GetTempPath(), "logic-ripper-payload-" + Guid.NewGuid().ToString("n") + ".json");
        try
        {
            await File.WriteAllTextAsync(payloadPath, payload.ToJsonString(new JsonSerializerOptions { WriteIndented = true }));
            var output = await RunProcessAsync("api", "-PayloadPath", payloadPath);
            return JsonNode.Parse(output) ?? throw new InvalidOperationException("CLI returned empty JSON.");
        }
        finally
        {
            if (File.Exists(payloadPath)) File.Delete(payloadPath);
        }
    }

    private async Task<string> RunProcessAsync(params string[] args)
    {
        var start = new ProcessStartInfo
        {
            FileName = _cliPath,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false
        };
        foreach (var arg in args) start.ArgumentList.Add(arg);

        using var process = Process.Start(start) ?? throw new InvalidOperationException("Could not start logic-ripper CLI.");
        var stdout = await process.StandardOutput.ReadToEndAsync();
        var stderr = await process.StandardError.ReadToEndAsync();
        await process.WaitForExitAsync();

        if (process.ExitCode != 0)
        {
            throw new InvalidOperationException(string.IsNullOrWhiteSpace(stderr) ? stdout.Trim() : stderr.Trim());
        }

        return stdout;
    }

    private static JsonObject ToJsonObject(IDictionary<string, string> values)
    {
        var result = new JsonObject();
        foreach (var (key, value) in values) result[key] = value;
        return result;
    }
}
