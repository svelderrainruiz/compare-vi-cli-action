import * as vscode from 'vscode';

const TASK_BUILD = 'Build CompareVI CLI (Release)';
const TASK_PARSE = 'Parse CLI Compare Outcome (.NET)';
const TASK_PREPUSH = 'Run PrePush Checks';
const TASK_PESTER_UNIT = 'Run Pester Tests (Unit)';
const TASK_PESTER_INTEGRATION = 'Run Pester Tests (Integration)';
const TASK_AUTO_PUSH = 'Integration (Standing Priority): Auto Push + Start + Watch';
const TASK_WATCH = 'Integration (Standing Priority): Watch existing run';

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

async function pickStandingPriorityIssue(): Promise<string | undefined> {
    const cached = vscode.workspace.getConfiguration('comparevi').get<string>('standingPriorityIssue');
    const items: vscode.QuickPickItem[] = [];
    if (cached) {
        items.push({ label: cached, description: 'Cached standing priority issue' });
    }
    items.push({ label: 'Enter issue number…', description: 'Manually enter issue number' });
    const choice = await vscode.window.showQuickPick(items, { placeHolder: 'Standing priority issue' });
    if (!choice) {
        return undefined;
    }
    if (choice.label === 'Enter issue number…') {
        const input = await vscode.window.showInputBox({ prompt: 'Enter issue number (e.g., 125)', validateInput: value => value.match(/^\d+$/) ? undefined : 'Issue number must be digits' });
        if (input) {
            await vscode.workspace.getConfiguration('comparevi').update('standingPriorityIssue', input, vscode.ConfigurationTarget.Global);
        }
        return input;
    }
    return choice.label;
}

async function startStandingPriorityRun() {
    const issue = await pickStandingPriorityIssue();
    if (!issue) {
        return;
    }
    await runTask(TASK_AUTO_PUSH);
}

async function watchStandingPriorityRun() {
    await runTask(TASK_WATCH);
}

export function activate(context: vscode.ExtensionContext) {
    const statusBar = vscode.window.createStatusBarItem(vscode.StatusBarAlignment.Left, 100);
    statusBar.command = 'comparevi.watchStandingPriority';
    statusBar.text = 'CompareVI: idle';
    statusBar.tooltip = 'Run CompareVI tasks or watch standing priority runs.';
    statusBar.show();

    vscode.tasks.onDidStartTaskProcess(e => {
        statusBar.text = `CompareVI: ${e.execution.task.name}…`;
    }, undefined, context.subscriptions);

    vscode.tasks.onDidEndTaskProcess(() => {
        statusBar.text = 'CompareVI: idle';
    }, undefined, context.subscriptions);

    context.subscriptions.push(
        vscode.commands.registerCommand('comparevi.buildAndParse', buildAndParse),
        vscode.commands.registerCommand('comparevi.startStandingPriority', startStandingPriorityRun),
        vscode.commands.registerCommand('comparevi.watchStandingPriority', watchStandingPriorityRun)
    );
}

export function deactivate() {}
