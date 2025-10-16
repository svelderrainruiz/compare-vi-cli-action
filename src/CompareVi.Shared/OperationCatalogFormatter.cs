using System;
using System.Collections.Generic;
using System.IO;
using System.Text.Json.Nodes;

namespace CompareVi.Shared
{
    public static class OperationCatalogFormatter
    {
        private const string OperationsSchema = "comparevi-cli/operations@v1";
        private const string OperationSchema = "comparevi-cli/operation@v1";
        private const string OperationNamesSchema = "comparevi-cli/operation-names@v1";

        public static JsonObject CreateOperationsListPayload()
        {
            var root = OperationCatalog.LoadRaw();
            var operationsArray = GetOperationsArray(root);

            return new JsonObject
            {
                ["schema"] = OperationsSchema,
                ["operationCount"] = operationsArray.Count,
                ["operations"] = operationsArray.DeepClone()
            };
        }

        public static bool TryCreateOperationPayload(string operationName, out JsonObject payload)
        {
            if (string.IsNullOrWhiteSpace(operationName))
            {
                throw new ArgumentException("Operation name must be provided.", nameof(operationName));
            }

            var root = OperationCatalog.LoadRaw();
            var operationsArray = GetOperationsArray(root);

            foreach (var item in operationsArray)
            {
                if (item is not JsonObject obj)
                {
                    continue;
                }

                if (!TryGetOperationName(obj, out var name))
                {
                    continue;
                }

                if (string.Equals(name, operationName, StringComparison.OrdinalIgnoreCase))
                {
                    payload = new JsonObject
                    {
                        ["schema"] = OperationSchema,
                        ["operationName"] = name,
                        ["operation"] = obj.DeepClone()
                    };
                    return true;
                }
            }

            payload = null!;
            return false;
        }

        public static JsonObject CreateOperationNamesPayload()
        {
            var root = OperationCatalog.LoadRaw();
            var operationsArray = GetOperationsArray(root);

            var names = new List<string>();
            foreach (var item in operationsArray)
            {
                if (item is not JsonObject obj)
                {
                    continue;
                }

                if (!TryGetOperationName(obj, out var name))
                {
                    continue;
                }

                names.Add(name!);
            }

            names.Sort(StringComparer.OrdinalIgnoreCase);

            var namesArray = new JsonArray();
            foreach (var name in names)
            {
                namesArray.Add(name);
            }

            return new JsonObject
            {
                ["schema"] = OperationNamesSchema,
                ["operationCount"] = names.Count,
                ["names"] = namesArray,
            };
        }

        private static JsonArray GetOperationsArray(JsonObject root)
        {
            if (!root.TryGetPropertyValue("operations", out var operationsNode) || operationsNode is not JsonArray operationsArray)
            {
                throw new InvalidDataException("Embedded operations spec is missing an operations array.");
            }

            return operationsArray;
        }

        private static bool TryGetOperationName(JsonObject operation, out string? name)
        {
            name = null;

            if (!operation.TryGetPropertyValue("name", out var nameNode) || nameNode is not JsonValue nameValue)
            {
                return false;
            }

            if (!nameValue.TryGetValue(out string? candidate) || string.IsNullOrWhiteSpace(candidate))
            {
                return false;
            }

            name = candidate;
            return true;
        }
    }
}
