using System;
using System.Linq;
using System.Text.Json.Nodes;
using CompareVi.Shared;
using Xunit;

namespace CompareVi.Shared.Tests
{
    public class ProviderCatalogFormatterTests
    {
        [Fact]
        public void CreateProvidersListPayload_ReturnsSchemaAndCount()
        {
            var payload = ProviderCatalogFormatter.CreateProvidersListPayload();

            Assert.Equal("comparevi-cli/providers@v1", payload["schema"]!.GetValue<string>());
            Assert.True(payload["providerCount"]!.GetValue<int>() > 0);

            var providers = Assert.IsType<JsonArray>(payload["providers"]);
            Assert.NotEmpty(providers);
        }

        [Fact]
        public void TryCreateProviderPayload_FindsProviderIgnoringCase()
        {
            var found = ProviderCatalogFormatter.TryCreateProviderPayload("LABVIEWCLI", out var payload);

            Assert.True(found);
            Assert.Equal("comparevi-cli/provider@v1", payload["schema"]!.GetValue<string>());
            Assert.Equal("labviewcli", payload["providerId"]!.GetValue<string>());

            var provider = Assert.IsType<JsonObject>(payload["provider"]);
            Assert.Equal("labviewcli", provider["id"]!.GetValue<string>());
        }

        [Fact]
        public void TryCreateProviderPayload_ReturnsFalseWhenMissing()
        {
            var found = ProviderCatalogFormatter.TryCreateProviderPayload("does-not-exist", out _);

            Assert.False(found);
        }

        [Fact]
        public void CreateProviderNamesPayload_ReturnsSortedIdentifiers()
        {
            var payload = ProviderCatalogFormatter.CreateProviderNamesPayload();

            Assert.Equal("comparevi-cli/provider-names@v1", payload["schema"]!.GetValue<string>());
            var names = Assert.IsType<JsonArray>(payload["names"]);
            Assert.NotEmpty(names);
            Assert.Equal(payload["providerCount"]!.GetValue<int>(), names.Count);

            var nameValues = names.Select(node => node!.GetValue<string>()).ToArray();
            var sorted = nameValues.OrderBy(n => n, StringComparer.OrdinalIgnoreCase).ToArray();
            Assert.Equal(sorted, nameValues);
        }
    }
}
