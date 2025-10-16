using System;
using System.Linq;
using System.Text.Json.Nodes;
using CompareVi.Shared;
using Xunit;

namespace CompareVi.Shared.Tests
{
    public class OperationCatalogFormatterTests
    {
        [Fact]
        public void CreateOperationsListPayload_ReturnsSchemaAndCount()
        {
            var payload = OperationCatalogFormatter.CreateOperationsListPayload();

            Assert.Equal("comparevi-cli/operations@v1", payload["schema"]!.GetValue<string>());
            Assert.True(payload["operationCount"]!.GetValue<int>() > 0);

            var operations = Assert.IsType<JsonArray>(payload["operations"]);
            Assert.NotEmpty(operations);
        }

        [Fact]
        public void TryCreateOperationPayload_FindsOperationIgnoringCase()
        {
            var found = OperationCatalogFormatter.TryCreateOperationPayload("createcomparisonreport", out var payload);

            Assert.True(found);
            Assert.Equal("comparevi-cli/operation@v1", payload["schema"]!.GetValue<string>());
            Assert.Equal("CreateComparisonReport", payload["operationName"]!.GetValue<string>());

            var operation = Assert.IsType<JsonObject>(payload["operation"]);
            Assert.Equal("CreateComparisonReport", operation["name"]!.GetValue<string>());
        }

        [Fact]
        public void TryCreateOperationPayload_ReturnsFalseWhenMissing()
        {
            var found = OperationCatalogFormatter.TryCreateOperationPayload("does-not-exist", out _);

            Assert.False(found);
        }

        [Fact]
        public void CreateOperationNamesPayload_ReturnsSortedNames()
        {
            var payload = OperationCatalogFormatter.CreateOperationNamesPayload();

            Assert.Equal("comparevi-cli/operation-names@v1", payload["schema"]!.GetValue<string>());
            var names = Assert.IsType<JsonArray>(payload["names"]);
            Assert.NotEmpty(names);
            Assert.Equal(payload["operationCount"]!.GetValue<int>(), names.Count);

            var nameStrings = names.Select(node => node!.GetValue<string>()).ToArray();
            var sorted = nameStrings.OrderBy(n => n, StringComparer.OrdinalIgnoreCase).ToArray();
            Assert.Equal(sorted, nameStrings);
        }
    }
}
