import * as assert from "assert";
import * as vscode from "vscode";

suite("CompareVI Extension", () => {
    test("commands are registered", async () => {
        const commands = await vscode.commands.getCommands(true);
        assert.ok(commands.includes("comparevi.buildAndParse"), "comparevi.buildAndParse not registered");
        assert.ok(commands.includes("comparevi.startStandingPriority"), "comparevi.startStandingPriority not registered");
        assert.ok(commands.includes("comparevi.watchStandingPriority"), "comparevi.watchStandingPriority not registered");
        assert.ok(commands.includes("comparevi.openArtifact"), "comparevi.openArtifact not registered");
        assert.ok(commands.includes("comparevi.showArtifactSummary"), "comparevi.showArtifactSummary not registered");
    });
});
