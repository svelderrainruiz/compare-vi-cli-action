import * as vscode from "vscode";
import * as path from "path";
import * as fs from "fs";
import { TextDecoder } from "util";

const TASK_BUILD = "Build CompareVI CLI (Release)";
const TASK_PARSE = "Parse CLI Compare Outcome (.NET)";
const TASK_AUTO_PUSH = "Integration (Standing Priority): Auto Push + Start + Watch";
const TASK_WATCH = "Integration (Standing Priority): Watch existing run";

const utf8Decoder = new TextDecoder("utf-8");

interface ArtifactDefinition {
    id: string;
    label: string;
    relativePath: string;
    summary?: boolean;
}

const artifactDefinitions: ArtifactDefinition[] = [
    {
        id: "queueSummary",
        label: "Queue Summary (compare-cli)",
        relativePath: "tests/results/compare-cli/queue-summary.json",
        summary: true
    },
    {
        id: "compareOutcome",
        label: "Compare Outcome (compare-cli)",
        relativePath: "tests/results/compare-cli/compare-outcome.json",
        summary: true
    },
    {
        id: "sessionIndex",
        label: "Session Index",
        relativePath: "tests/results/session-index.json"
    },
    {
        id: "phaseVars",
        label: "Phase Vars Manifest",
        relativePath: "tests/results/_phase/vars.json"
    }
];

class ArtifactItem extends vscode.TreeItem {
    constructor(
        public readonly definition: ArtifactDefinition,
        public readonly resourceUri: vscode.Uri
    ) {
        super(definition.label, vscode.TreeItemCollapsibleState.None);
        this.tooltip = resourceUri.fsPath;
        this.command = {
            command: "comparevi.openArtifact",
            title: "CompareVI: Open Artifact",
            arguments: [this]
        };
        const ext = path.extname(resourceUri.fsPath).toLowerCase();
        this.contextValue =
            definition.summary && ext === ".json"
                ? "compareviJsonArtifact"
                : "compareviArtifact";
    }
}

class ArtifactTreeProvider implements vscode.TreeDataProvider<ArtifactItem> {
    private readonly _onDidChangeTreeData = new vscode.EventEmitter<void>();
    readonly onDidChangeTreeData = this._onDidChangeTreeData.event;

    constructor(private workspaceFolder: vscode.WorkspaceFolder | undefined) {}

    setWorkspaceFolder(folder: vscode.WorkspaceFolder | undefined) {
        this.workspaceFolder = folder;
        this.refresh();
    }

    getWorkspaceFolder(): vscode.WorkspaceFolder | undefined {
        return this.workspaceFolder;
    }

    refresh(): void {
        this._onDidChangeTreeData.fire();
    }

    getTreeItem(element: ArtifactItem): vscode.TreeItem {
        return element;
    }

    async getChildren(element?: ArtifactItem): Promise<ArtifactItem[]> {
        if (element) {
            return [];
        }
        const folder = this.workspaceFolder;
        if (!folder) {
            return [];
        }
        const items: ArtifactItem[] = [];
        for (const def of artifactDefinitions) {
            const uri = vscode.Uri.joinPath(folder.uri, ...def.relativePath.split("/"));
            try {
                await vscode.workspace.fs.stat(uri);
                items.push(new ArtifactItem(def, uri));
            } catch {
                // Artifact not present yet
            }
        }
        return items;
    }

    async pickArtifact(filter?: (def: ArtifactDefinition) => boolean): Promise<ArtifactItem | undefined> {
        const roots = await this.getChildren();
        const filtered = filter ? roots.filter(item => filter(item.definition)) : roots;
        if (filtered.length === 0) {
            vscode.window.showInformationMessage("No CompareVI artifacts found yet.");
            return undefined;
        }
        if (filtered.length === 1) {
            return filtered[0];
        }
        const pick = await vscode.window.showQuickPick(
            filtered.map(item => ({
                label: item.definition.label,
                description: item.resourceUri.fsPath
            })),
            { placeHolder: "Select CompareVI artifact" }
        );
        if (!pick) {
            return undefined;
        }
        return filtered.find(item => item.definition.label === pick.label);
    }
}

interface DiagnosticState {
    lastOutcomeSignature?: string;
}

const diagnosticState: DiagnosticState = {};

async function runTask(label: string) {
    const tasks = await vscode.tasks.fetchTasks();
    const task = tasks.find(t => t.name === label);
    if (!task) {
        vscode.window.showErrorMessage(`VS Code task "${label}" not found.`);
        return;
    }
    await vscode.tasks.executeTask(task);
}

async function buildAndParse() {
    await runTask(TASK_BUILD);
    await runTask(TASK_PARSE);
}

function getConfiguration() {
    return vscode.workspace.getConfiguration("comparevi");
}

function getTokenFallbackPath(): string | undefined {
    const config = getConfiguration();
    const defaultPath = process.platform === "win32" ? "C\\\\github_token.txt" : "";
    const configured = config.get<string>("tokenFallbackPath", defaultPath);
    if (!configured || !configured.trim()) {
        return undefined;
    }
    return configured;
}

async function ensureAdminToken(): Promise<boolean> {
    if (process.env.GH_TOKEN || process.env.GITHUB_TOKEN) {
        return true;
    }
    const fallback = getTokenFallbackPath();
    if (fallback && fs.existsSync(fallback)) {
        return true;
    }
    const choice = await vscode.window.showWarningMessage(
        "GH_TOKEN/GITHUB_TOKEN not detected. Standing priority automation may fail when pushing or dispatching. Continue anyway?",
        { modal: true },
        "Continue",
        "Cancel"
    );
    return choice === "Continue";
}

async function pickStandingPriorityIssue(): Promise<string | undefined> {
    const config = getConfiguration();
    const cached = config.get<string>("standingPriorityIssue");
    const items: vscode.QuickPickItem[] = [];
    if (cached) {
        items.push({
            label: cached,
            description: "Cached standing priority issue"
        });
    }
    items.push({
        label: "Enter issue number…",
        description: "Manually enter issue number"
    });
    const choice = await vscode.window.showQuickPick(items, {
        placeHolder: "Standing priority issue"
    });
    if (!choice) {
        return undefined;
    }
    if (choice.label === "Enter issue number…") {
        const input = await vscode.window.showInputBox({
            prompt: "Enter issue number (e.g., 125)",
            validateInput: value =>
                value.match(/^\d+$/) ? undefined : "Issue number must be digits"
        });
        if (input) {
            await config.update(
                "standingPriorityIssue",
                input,
                vscode.ConfigurationTarget.Global
            );
        }
        return input;
    }
    return choice.label;
}

function escapeHtml(value: string): string {
    return value
        .replace(/&/g, "&amp;")
        .replace(/</g, "&lt;")
        .replace(/>/g, "&gt;")
        .replace(/"/g, "&quot;")
        .replace(/'/g, "&#39;");
}

function renderSummaryHTML(def: ArtifactDefinition, jsonText: string): string {
    try {
        const data = JSON.parse(jsonText);
        if (def.id === "compareOutcome" && Array.isArray(data?.cases)) {
            const rows = data.cases
                .map(
                    (c: any) =>
                        `<tr><td>${escapeHtml(String(c?.id ?? ""))}</td><td>${escapeHtml(
                            String(c?.status ?? "")
                        )}</td><td>${escapeHtml(String(c?.exit ?? ""))}</td><td>${escapeHtml(
                            String(c?.diff ?? "")
                        )}</td></tr>`
                )
                .join("");
            return `
                <h2>${escapeHtml(def.label)}</h2>
                <table>
                    <thead><tr><th>Case</th><th>Status</th><th>Exit</th><th>Diff</th></tr></thead>
                    <tbody>${rows}</tbody>
                </table>`;
        }
        if (def.id === "queueSummary" && Array.isArray(data?.cases)) {
            const rows = data.cases
                .map(
                    (c: any) =>
                        `<tr><td>${escapeHtml(String(c?.id ?? ""))}</td><td>${escapeHtml(
                            String(c?.status ?? "")
                        )}</td><td>${escapeHtml(String(c?.duration ?? ""))}</td></tr>`
                )
                .join("");
            return `
                <h2>${escapeHtml(def.label)}</h2>
                <table>
                    <thead><tr><th>Case</th><th>Status</th><th>Duration</th></tr></thead>
                    <tbody>${rows}</tbody>
                </table>`;
        }
        return `<h2>${escapeHtml(def.label)}</h2><pre>${escapeHtml(
            JSON.stringify(data, null, 2)
        )}</pre>`;
    } catch {
        return `<h2>${escapeHtml(def.label)}</h2><pre>${escapeHtml(jsonText)}</pre>`;
    }
}

async function showArtifactSummary(
    provider: ArtifactTreeProvider,
    item?: ArtifactItem
) {
    const target =
        item ?? (await provider.pickArtifact(def => Boolean(def.summary)));
    if (!target) {
        return;
    }
    if (!target.definition.summary) {
        vscode.window.showInformationMessage(
            `${target.definition.label} does not have a summary view.`
        );
        return;
    }
    try {
        const content = await vscode.workspace.fs.readFile(target.resourceUri);
        const text = utf8Decoder.decode(content);
        const panel = vscode.window.createWebviewPanel(
            "compareviArtifactSummary",
            `${target.definition.label} Summary`,
            vscode.ViewColumn.Beside,
            { enableScripts: false }
        );
        panel.webview.html = `<!DOCTYPE html>
        <html>
            <head>
                <meta charset="utf-8">
                <style>
                body { font-family: var(--vscode-font-family); padding: 16px; }
                table { border-collapse: collapse; width: 100%; }
                th, td { border: 1px solid var(--vscode-editor-foreground); padding: 4px 8px; text-align: left; }
                thead { background: var(--vscode-editor-background); }
                pre { background: var(--vscode-editor-background); padding: 12px; border-radius: 4px; overflow-x: auto; }
                </style>
            </head>
            <body>
                ${renderSummaryHTML(target.definition, text)}
            </body>
        </html>`;
    } catch (error) {
        vscode.window.showErrorMessage(
            `Failed to read artifact: ${(error as Error).message}`
        );
    }
}

async function openArtifact(
    provider: ArtifactTreeProvider,
    item?: ArtifactItem
) {
    const target = item ?? (await provider.pickArtifact());
    if (!target) {
        return;
    }
    await vscode.window.showTextDocument(target.resourceUri, { preview: true });
}

function computeOutcomeSignature(cases: any[]): string {
    return JSON.stringify(
        cases.map(c => ({
            id: c?.id,
            status: c?.status,
            exit: c?.exit,
            diff: c?.diff
        }))
    );
}

async function evaluateOutcomeDiagnostics(
    provider: ArtifactTreeProvider,
    state: DiagnosticState
) {
    const folder = provider.getWorkspaceFolder();
    if (!folder) {
        return;
    }
    const outcomeUri = vscode.Uri.joinPath(
        folder.uri,
        "tests/results/compare-cli/compare-outcome.json"
    );
    let content: Uint8Array;
    try {
        content = await vscode.workspace.fs.readFile(outcomeUri);
    } catch {
        delete state.lastOutcomeSignature;
        return;
    }
    const text = utf8Decoder.decode(content);
    let data: any;
    try {
        data = JSON.parse(text);
    } catch {
        return;
    }
    if (!Array.isArray(data?.cases)) {
        return;
    }
    const signature = computeOutcomeSignature(data.cases);
    if (signature === state.lastOutcomeSignature) {
        return;
    }
    state.lastOutcomeSignature = signature;
    const problems = data.cases.filter((c: any) => {
        const status = String(c?.status ?? "").toLowerCase();
        const exit = Number(c?.exit ?? 0);
        const diff = c?.diff;
        const statusBad = status && status !== "passed" && status !== "success";
        const exitBad = Number.isFinite(exit) && exit !== 0;
        const diffBad = diff === true || diff === "true";
        return statusBad || exitBad || diffBad;
    });
    if (problems.length > 0) {
        vscode.window.showWarningMessage(
            `CompareVI CLI outcome reports ${problems.length} non-passing case(s). Open the artifact summary for details.`,
            "Show Summary",
            "Dismiss"
        ).then(selection => {
            if (selection === "Show Summary") {
                showArtifactSummary(provider);
            }
        });
    }
}

export function activate(context: vscode.ExtensionContext) {
    const workspaceFolder = vscode.workspace.workspaceFolders?.[0];
    const artifactProvider = new ArtifactTreeProvider(workspaceFolder);

    const treeView = vscode.window.createTreeView("compareviArtifactExplorer", {
        treeDataProvider: artifactProvider
    });
    context.subscriptions.push(treeView);

    const statusBar = vscode.window.createStatusBarItem(
        vscode.StatusBarAlignment.Left,
        100
    );
    statusBar.command = "comparevi.watchStandingPriority";
    statusBar.text = "CompareVI: idle";
    statusBar.tooltip = "Run CompareVI tasks or watch standing priority runs.";
    statusBar.show();

    const disposables: vscode.Disposable[] = [];

    const refreshArtifacts = () => {
        artifactProvider.refresh();
        void evaluateOutcomeDiagnostics(artifactProvider, diagnosticState);
    };

    if (workspaceFolder) {
        const pattern = new vscode.RelativePattern(
            workspaceFolder,
            "tests/results/**/*"
        );
        const watcher = vscode.workspace.createFileSystemWatcher(pattern);
        watcher.onDidChange(refreshArtifacts, null, disposables);
        watcher.onDidCreate(refreshArtifacts, null, disposables);
        watcher.onDidDelete(refreshArtifacts, null, disposables);
        context.subscriptions.push(watcher);
    }

    vscode.workspace.onDidChangeWorkspaceFolders(
        () => {
            artifactProvider.setWorkspaceFolder(
                vscode.workspace.workspaceFolders?.[0]
            );
            void evaluateOutcomeDiagnostics(artifactProvider, diagnosticState);
        },
        undefined,
        context.subscriptions
    );

    vscode.tasks.onDidStartTaskProcess(
        e => {
            statusBar.text = `CompareVI: ${e.execution.task.name}…`;
        },
        undefined,
        context.subscriptions
    );

    vscode.tasks.onDidEndTaskProcess(
        () => {
            statusBar.text = "CompareVI: idle";
        },
        undefined,
        context.subscriptions
    );

    context.subscriptions.push(
        vscode.commands.registerCommand("comparevi.buildAndParse", buildAndParse),
        vscode.commands.registerCommand(
            "comparevi.startStandingPriority",
            async () => {
                const issue = await pickStandingPriorityIssue();
                if (!issue) {
                    return;
                }
                const tokenOk = await ensureAdminToken();
                if (!tokenOk) {
                    return;
                }
                await runTask(TASK_AUTO_PUSH);
            }
        ),
        vscode.commands.registerCommand(
            "comparevi.watchStandingPriority",
            async () => {
                await runTask(TASK_WATCH);
            }
        ),
        vscode.commands.registerCommand("comparevi.openArtifact", async (item?: ArtifactItem) => {
            await openArtifact(artifactProvider, item);
        }),
        vscode.commands.registerCommand(
            "comparevi.showArtifactSummary",
            async (item?: ArtifactItem) => {
                await showArtifactSummary(artifactProvider, item);
            }
        )
    );

    context.subscriptions.push(...disposables);

    void evaluateOutcomeDiagnostics(artifactProvider, diagnosticState);
}

export function deactivate() {}

