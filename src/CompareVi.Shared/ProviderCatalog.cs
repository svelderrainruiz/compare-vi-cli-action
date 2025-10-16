using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.Json.Nodes;

namespace CompareVi.Shared
{
    public sealed record ProviderBinarySpec(
        IReadOnlyList<string> Env)
    {
        public bool HasEnvOverrides => Env.Count > 0;
    }

    public sealed record ProviderSpec(
        string Id,
        string? DisplayName,
        string? Description,
        ProviderBinarySpec? Binary,
        IReadOnlyList<string> Operations)
    {
        public string PrimaryName => DisplayName ?? Id;

        public bool SupportsOperation(string operation) =>
            Operations.Contains(operation, StringComparer.OrdinalIgnoreCase);
    }

    public sealed record ProviderCatalogDocument(IReadOnlyList<ProviderSpec> Providers)
    {
        public int ProviderCount => Providers.Count;

        public ProviderSpec? Find(string nameOrId)
        {
            return Providers.FirstOrDefault(provider =>
                string.Equals(provider.Id, nameOrId, StringComparison.OrdinalIgnoreCase) ||
                (!string.IsNullOrWhiteSpace(provider.DisplayName) &&
                 string.Equals(provider.DisplayName, nameOrId, StringComparison.OrdinalIgnoreCase)));
        }

        internal static ProviderCatalogDocument FromJson(JsonObject root)
        {
            if (!root.TryGetPropertyValue("providers", out var providersNode) || providersNode is not JsonArray providersArray)
            {
                throw new InvalidDataException("Provider spec is missing a 'providers' array.");
            }

            var providers = new List<ProviderSpec>(providersArray.Count);

            foreach (var item in providersArray)
            {
                if (item is not JsonObject providerObj)
                {
                    continue;
                }

                if (!providerObj.TryGetPropertyValue("id", out var idNode) || idNode is not JsonValue idValue ||
                    !idValue.TryGetValue(out string? id) || string.IsNullOrWhiteSpace(id))
                {
                    continue;
                }

                string? displayName = null;
                if (providerObj.TryGetPropertyValue("displayName", out var displayNameNode) && displayNameNode is JsonValue displayNameValue)
                {
                    displayNameValue.TryGetValue(out displayName);
                }

                string? description = null;
                if (providerObj.TryGetPropertyValue("description", out var descriptionNode) && descriptionNode is JsonValue descriptionValue)
                {
                    descriptionValue.TryGetValue(out description);
                }

                ProviderBinarySpec? binarySpec = null;
                if (providerObj.TryGetPropertyValue("binary", out var binaryNode) && binaryNode is JsonObject binaryObj)
                {
                    var envOverrides = new List<string>();
                    if (binaryObj.TryGetPropertyValue("env", out var envNode) && envNode is JsonArray envArray)
                    {
                        foreach (var envItem in envArray)
                        {
                            if (envItem is JsonValue envValue && envValue.TryGetValue(out string? envName) &&
                                !string.IsNullOrWhiteSpace(envName))
                            {
                                envOverrides.Add(envName);
                            }
                        }
                    }

                    binarySpec = new ProviderBinarySpec(envOverrides);
                }

                var operations = new List<string>();
                if (providerObj.TryGetPropertyValue("operations", out var operationsNode) && operationsNode is JsonArray operationsArray)
                {
                    foreach (var opNode in operationsArray)
                    {
                        if (opNode is JsonValue opValue && opValue.TryGetValue(out string? operationName) &&
                            !string.IsNullOrWhiteSpace(operationName))
                        {
                            operations.Add(operationName);
                        }
                    }
                }

                providers.Add(new ProviderSpec(id!, displayName, description, binarySpec, operations));
            }

            return new ProviderCatalogDocument(providers);
        }
    }

    public static class ProviderCatalog
    {
        private const string ResourceName = "CompareVi.Shared.Providers.providers.json";

        public static JsonObject LoadRaw()
        {
            using var stream = typeof(ProviderCatalog).Assembly.GetManifestResourceStream(ResourceName)
                ?? throw new InvalidOperationException($"Embedded providers spec '{ResourceName}' not found.");

            if (JsonNode.Parse(stream) is not JsonObject root)
            {
                throw new InvalidDataException("Embedded providers spec is not a JSON object.");
            }

            return (JsonObject)root.DeepClone();
        }

        public static ProviderCatalogDocument Load()
        {
            var raw = LoadRaw();
            return ProviderCatalogDocument.FromJson(raw);
        }
    }
}
