using System;
using System.Collections.Generic;
using System.IO;
using System.Text.Json;
using System.Text.Json.Nodes;
using CompareVi.Shared;

internal static class Program
{
    private static int Main(string[] args)
    {
        try
        {
            if (args.Length == 0 || IsHelp(args[0]))
            {
                PrintHelp();
                return 0;
            }

            var cmd = args[0].ToLowerInvariant();
            switch (cmd)
            {
                case "version":
                    return CmdVersion();
                case "tokenize":
                    return CmdTokenize(args);
                case "procs":
                    return CmdProcs();
                case "quote":
                    return CmdQuote(args);
                case "operations":
                    return CmdOperations(args);
                default:
                    Console.Error.WriteLine($"Unknown command: {cmd}");
                    PrintHelp();
                    return 2;
            }
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine(ex.Message);
            return 1;
        }
    }

    private static bool IsHelp(string s) => s.Equals("-h", StringComparison.OrdinalIgnoreCase) || s.Equals("--help", StringComparison.OrdinalIgnoreCase) || s.Equals("help", StringComparison.OrdinalIgnoreCase);

    private static void PrintHelp()
    {
        Console.WriteLine("comparevi-cli — utilities for Compare VI workflows");
        Console.WriteLine();
        Console.WriteLine("Usage:");
        Console.WriteLine("  comparevi-cli version");
        Console.WriteLine("  comparevi-cli tokenize --input \"arg string\"");
        Console.WriteLine("  comparevi-cli procs");
        Console.WriteLine("  comparevi-cli quote --path <path>");
        Console.WriteLine("  comparevi-cli operations [--name <operation>] [--names-only]");
    }

    private static int CmdVersion()
    {
        var assembly = typeof(Program).Assembly;
        var asmName = assembly.GetName();
        var infoAttr = (System.Reflection.AssemblyInformationalVersionAttribute?)Attribute.GetCustomAttribute(
            assembly, typeof(System.Reflection.AssemblyInformationalVersionAttribute));
        var obj = new Dictionary<string, object?>
        {
            ["name"] = asmName.Name,
            ["assemblyVersion"] = asmName.Version?.ToString(),
            ["informationalVersion"] = infoAttr?.InformationalVersion,
            ["framework"] = System.Runtime.InteropServices.RuntimeInformation.FrameworkDescription,
            ["os"] = System.Runtime.InteropServices.RuntimeInformation.OSDescription,
        };
        Console.WriteLine(JsonSerializer.Serialize(obj, new JsonSerializerOptions { WriteIndented = true }));
        return 0;
    }

    private static int CmdTokenize(string[] args)
    {
        // Expect: tokenize --input "..."
        string? input = null;
        for (int i = 1; i < args.Length; i++)
        {
            if (args[i].Equals("--input", StringComparison.OrdinalIgnoreCase) && i + 1 < args.Length)
            {
                input = args[i + 1];
                i++;
            }
        }
        var tokens = ArgTokenizer.Tokenize(input);
        var normalized = ArgTokenizer.NormalizeFlagValuePairs(tokens);
        var obj = new Dictionary<string, object?>
        {
            ["raw"] = tokens,
            ["normalized"] = normalized,
        };
        Console.WriteLine(JsonSerializer.Serialize(obj, new JsonSerializerOptions { WriteIndented = true }));
        return 0;
    }

    private static int CmdProcs()
    {
        var snap = ProcSnapshot.Capture();
        var obj = new Dictionary<string, object?>
        {
            ["labviewPids"] = snap.LabViewPids,
            ["lvcomparePids"] = snap.LvComparePids,
            ["labviewCliPids"] = snap.LabViewCliPids,
            ["gcliPids"] = snap.GcliPids,
        };
        Console.WriteLine(JsonSerializer.Serialize(obj, new JsonSerializerOptions { WriteIndented = true }));
        return 0;
    }

    private static int CmdQuote(string[] args)
    {
        string? path = null;
        for (int i = 1; i < args.Length; i++)
        {
            if (args[i].Equals("--path", StringComparison.OrdinalIgnoreCase) && i + 1 < args.Length)
            {
                path = args[i + 1];
                i++;
            }
        }
        var quoted = PathUtils.Quote(path);
        var obj = new Dictionary<string, object?>
        {
            ["input"] = path,
            ["quoted"] = quoted,
        };
        Console.WriteLine(JsonSerializer.Serialize(obj, new JsonSerializerOptions { WriteIndented = true }));
        return 0;
    }

    private static int CmdOperations(string[] args)
    {
        string? operationName = null;
        var namesOnly = false;
        for (int i = 1; i < args.Length; i++)
        {
            if (args[i].Equals("--name", StringComparison.OrdinalIgnoreCase) && i + 1 < args.Length)
            {
                operationName = args[i + 1];
                i++;
                continue;
            }

            if (args[i].Equals("--names", StringComparison.OrdinalIgnoreCase) ||
                args[i].Equals("--names-only", StringComparison.OrdinalIgnoreCase))
            {
                namesOnly = true;
            }
        }

        operationName = operationName?.Trim();

        if (namesOnly && !string.IsNullOrEmpty(operationName))
        {
            Console.Error.WriteLine("--names-only cannot be combined with --name.");
            return 2;
        }

        if (namesOnly)
        {
            var payload = OperationCatalogFormatter.CreateOperationNamesPayload();
            Console.WriteLine(payload.ToJsonString(new JsonSerializerOptions { WriteIndented = true }));
            return 0;
        }

        if (string.IsNullOrEmpty(operationName))
        {
            var payload = OperationCatalogFormatter.CreateOperationsListPayload();
            Console.WriteLine(payload.ToJsonString(new JsonSerializerOptions { WriteIndented = true }));
            return 0;
        }

        if (OperationCatalogFormatter.TryCreateOperationPayload(operationName!, out var operationPayload))
        {
            Console.WriteLine(operationPayload.ToJsonString(new JsonSerializerOptions { WriteIndented = true }));
            return 0;
        }

        Console.Error.WriteLine($"Operation '{operationName}' was not found in the operations catalog.");
        return 3;
    }
}
