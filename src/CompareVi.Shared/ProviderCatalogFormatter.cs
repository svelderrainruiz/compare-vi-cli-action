using System;
using System.Collections.Generic;
using System.Linq;
using System.Text.Json.Nodes;

namespace CompareVi.Shared
{
    public static class ProviderCatalogFormatter
    {
        private const string ProvidersSchema = "comparevi-cli/providers@v1";
        private const string ProviderSchema = "comparevi-cli/provider@v1";
        private const string ProviderNamesSchema = "comparevi-cli/provider-names@v1";

        public static JsonObject CreateProvidersListPayload()
        {
            var catalog = ProviderCatalog.Load();
            var providersArray = new JsonArray();

            foreach (var provider in catalog.Providers.OrderBy(p => p.PrimaryName, StringComparer.OrdinalIgnoreCase))
            {
                providersArray.Add(CreateProviderJson(provider));
            }

            return new JsonObject
            {
                ["schema"] = ProvidersSchema,
                ["providerCount"] = catalog.ProviderCount,
                ["providers"] = providersArray,
            };
        }

        public static bool TryCreateProviderPayload(string providerNameOrId, out JsonObject payload)
        {
            if (string.IsNullOrWhiteSpace(providerNameOrId))
            {
                throw new ArgumentException("Provider name or identifier must be provided.", nameof(providerNameOrId));
            }

            var catalog = ProviderCatalog.Load();
            var match = catalog.Find(providerNameOrId);
            if (match is null)
            {
                payload = null!;
                return false;
            }

            payload = new JsonObject
            {
                ["schema"] = ProviderSchema,
                ["providerId"] = match.Id,
                ["provider"] = CreateProviderJson(match),
            };
            return true;
        }

        public static JsonObject CreateProviderNamesPayload()
        {
            var catalog = ProviderCatalog.Load();
            var names = new List<string>();

            foreach (var provider in catalog.Providers)
            {
                names.Add(provider.Id);
            }

            names.Sort(StringComparer.OrdinalIgnoreCase);

            var namesArray = new JsonArray();
            foreach (var name in names)
            {
                namesArray.Add(name);
            }

            return new JsonObject
            {
                ["schema"] = ProviderNamesSchema,
                ["providerCount"] = names.Count,
                ["names"] = namesArray,
            };
        }

        private static JsonObject CreateProviderJson(ProviderSpec provider)
        {
            var providerJson = new JsonObject
            {
                ["id"] = provider.Id,
            };

            if (!string.IsNullOrWhiteSpace(provider.DisplayName))
            {
                providerJson["displayName"] = provider.DisplayName;
            }

            if (!string.IsNullOrWhiteSpace(provider.Description))
            {
                providerJson["description"] = provider.Description;
            }

            if (provider.Binary is { } binary && binary.HasEnvOverrides)
            {
                var envArray = new JsonArray();
                foreach (var envName in binary.Env)
                {
                    envArray.Add(envName);
                }

                if (envArray.Count > 0)
                {
                    providerJson["binary"] = new JsonObject
                    {
                        ["env"] = envArray,
                    };
                }
            }

            if (provider.Operations.Count > 0)
            {
                var operationsArray = new JsonArray();
                foreach (var operation in provider.Operations.OrderBy(op => op, StringComparer.OrdinalIgnoreCase))
                {
                    operationsArray.Add(operation);
                }

                providerJson["operations"] = operationsArray;
            }

            return providerJson;
        }
    }
}
