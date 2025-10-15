const path = require('path');
const fs = require('fs');
const { EventEmitter } = require('events');
const { PassThrough } = require('stream');
const { expect } = require('chai');
const vscode = require('vscode');
const gitHelpers = require('../../lib/git');

const EXTENSION_ID = 'local.comparevi-helper';
const workspaceRoot = path.resolve(__dirname, '../fixtures/workspace');

function extractOutputDir(args) {
  if (Array.isArray(args)) {
    const commandIndex = args.indexOf('-Command');
    if (commandIndex !== -1 && args[commandIndex + 1]) {
      const match = args[commandIndex + 1].match(/-OutputDir\s+'([^']+)'/);
      if (match) { return match[1].replace(/''/g, "'"); }
    }
    const idx = args.indexOf('-OutputDir');
    if (idx !== -1 && args[idx + 1]) {
      return args[idx + 1];
    }
  }
  return undefined;
}

function installSpawnStub(testing, handler) {
  testing.setSpawnOverride((args, options) => {
    const proc = new EventEmitter();
    proc.stdout = new PassThrough();
    proc.stderr = new PassThrough();
    const outputDir = extractOutputDir(args);

    setImmediate(() => {
      if (outputDir) {
        fs.mkdirSync(outputDir, { recursive: true });
        const capturePath = path.join(outputDir, 'lvcompare-capture.json');
        const reportPath = path.join(outputDir, 'compare-report.html');
        fs.writeFileSync(capturePath, JSON.stringify({ exitCode: 1, seconds: 0.1, command: 'stub' }));
        fs.writeFileSync(reportPath, '<html><body>stub</body></html>');
        const imagesDir = path.join(outputDir, 'cli-images');
        fs.mkdirSync(imagesDir, { recursive: true });
        fs.writeFileSync(path.join(imagesDir, 'diff-01.png'), 'png');
      }
      if (typeof handler === 'function') {
        handler(outputDir, args, options);
      }
      proc.stdout.end('stub stdout');
      proc.stderr.end();
      proc.emit('close', 1);
    });

    return proc;
  });
}

suite('CompareVI extension', () => {
  /** @type {import('../../extension')} */
  let extensionExports;
  let testingApi;

  suiteSetup(async function suiteSetup() {
    this.timeout(20000);

    // Prepare fake LabVIEW installation
    const lvRoot = path.join(workspaceRoot, 'Program Files');
    const lvPath = path.join(lvRoot, 'National Instruments', 'LabVIEW 2025');
    fs.mkdirSync(lvPath, { recursive: true });
    fs.writeFileSync(path.join(lvPath, 'LabVIEW.exe'), '');
    process.env.ProgramW6432 = lvRoot;
    process.env.ProgramFiles = lvRoot;
    process.env['ProgramFiles(x86)'] = path.join(workspaceRoot, 'Program Files (x86)');

    const extension = vscode.extensions.getExtension(EXTENSION_ID);
    expect(extension).to.not.be.undefined;

    extensionExports = await extension.activate();
    testingApi = extensionExports.__testing;
    testingApi.resetSpawnOverride();
    gitHelpers.resetGitRunnerOverride();

    // Ensure workspace folder is set to fixtures workspace
    const workspaceUri = vscode.Uri.file(workspaceRoot);
    const folders = vscode.workspace.workspaceFolders || [];
    const alreadySet = folders.some((folder) => folder.uri.fsPath === workspaceRoot);
    if (!alreadySet) {
      vscode.workspace.updateWorkspaceFolders(0, folders.length, { uri: workspaceUri });
      await new Promise((resolve) => setTimeout(resolve, 250));
    }

    const config = vscode.workspace.getConfiguration();
    await config.update('comparevi.showFlagPicker', false, vscode.ConfigurationTarget.Workspace);
    await config.update('comparevi.passFlags', false, vscode.ConfigurationTarget.Workspace);
    await config.update('comparevi.showSourcePicker', false, vscode.ConfigurationTarget.Workspace);
    await vscode.commands.executeCommand('comparevi.openViCompare');

    gitHelpers.setGitRunnerOverride((_repoRoot, args) => {
      if (args[0] === 'show' && args[1] === '-s') {
        const ref = args[args.length - 1];
        const short = ref === 'HEAD' ? 'abcd123' : 'efgh456';
        return `${short.repeat(5)}\n${short}\n2025-10-15T00:00:00Z\n${ref} subject\n`;
      }
      if (args[0] === 'ls-tree') {
        return 'VI2.vi\n';
      }
      if (args[0] === 'show') {
        return Buffer.from('temp vi contents');
      }
      return '';
    });
  });

  suiteTeardown(async () => {
    if (testingApi) {
      testingApi.resetSpawnOverride();
    }
    gitHelpers.resetGitRunnerOverride();
  });

  teardown(() => {
    const outDir = path.join(workspaceRoot, 'tests', 'results', 'manual-vi2-compare');
    if (fs.existsSync(outDir)) {
      fs.rmSync(outDir, { recursive: true, force: true });
    }
  });

  test('task provider surfaces comparevi tasks', async () => {
    const tasks = await vscode.tasks.fetchTasks({ type: 'comparevi' });
    const compareTasks = tasks.filter((task) => task.definition.type === 'comparevi');
    expect(compareTasks.length).to.equal(0);
  });

  test('run profile command produces capture via stub', async () => {
    const config = vscode.workspace.getConfiguration();
    await config.update('comparevi.showFlagPicker', false, vscode.ConfigurationTarget.Workspace);
    await config.update('comparevi.passFlags', false, vscode.ConfigurationTarget.Workspace);
    await config.update('comparevi.showSourcePicker', false, vscode.ConfigurationTarget.Workspace);

    const outDir = path.join(workspaceRoot, 'tests', 'results', 'manual-vi2-compare');
    if (fs.existsSync(outDir)) {
      fs.rmSync(outDir, { recursive: true, force: true });
    }

    const capturePromise = new Promise((resolve) => {
      installSpawnStub(testingApi, (dir) => resolve(dir));
    });

    await vscode.commands.executeCommand('comparevi.runProfile');
    const outputDir = await capturePromise;
    testingApi.resetSpawnOverride();
    expect(outputDir).to.equal(outDir);

    const capturePath = path.join(outputDir, 'lvcompare-capture.json');
    expect(fs.existsSync(capturePath)).to.be.true;
    const capture = JSON.parse(fs.readFileSync(capturePath, 'utf8'));
    expect(capture.exitCode).to.equal(1);
    const statusItem = testingApi.getStatusItem();
    expect(statusItem.text).to.include('VI Diff');
  });

  test('compare active VI with previous commit produces capture via stub', async () => {
    const config = vscode.workspace.getConfiguration();
    await config.update('comparevi.showFlagPicker', false, vscode.ConfigurationTarget.Workspace);
    await config.update('comparevi.passFlags', false, vscode.ConfigurationTarget.Workspace);
    await config.update('comparevi.showSourcePicker', false, vscode.ConfigurationTarget.Workspace);

    const outDir = path.join(workspaceRoot, 'tests', 'results', 'manual-vi2-compare');
    if (fs.existsSync(outDir)) {
      fs.rmSync(outDir, { recursive: true, force: true });
    }

    // Ensure VI is opened to become the active editor
    const viPath = path.join(workspaceRoot, 'VI2.vi');
    const doc = await vscode.workspace.openTextDocument(vscode.Uri.file(viPath));
    await vscode.window.showTextDocument(doc);

    const capturePromise = new Promise((resolve) => {
      installSpawnStub(testingApi, (dir) => resolve(dir));
    });

    await vscode.commands.executeCommand('comparevi.compareActiveWithPrevious');
    const outputDir = await capturePromise;
    testingApi.resetSpawnOverride();
    expect(outputDir).to.equal(outDir);

    const capturePath = path.join(outputDir, 'lvcompare-capture.json');
    expect(fs.existsSync(capturePath)).to.be.true;
    const capture = JSON.parse(fs.readFileSync(capturePath, 'utf8'));
    expect(capture.exitCode).to.equal(1);
    const statusItem = testingApi.getStatusItem();
    expect(statusItem.text).to.include('VI Diff');
  });

  test('panel state exposes presets and commit refs', async () => {
    const config = vscode.workspace.getConfiguration();
    await config.update('comparevi.presets', { Quick: ['-nobdcosm'] }, vscode.ConfigurationTarget.Workspace);
    await config.update('comparevi.commitRefs.base', 'HEAD~2', vscode.ConfigurationTarget.Workspace);
    await config.update('comparevi.commitRefs.head', 'HEAD', vscode.ConfigurationTarget.Workspace);

    const state = testingApi.getPanelState();
    expect(state.commitRefs.base).to.equal('HEAD~2');
    const preset = state.presets.find((p) => p.name === 'Quick');
    expect(preset.flags).to.deep.equal(['-nobdcosm']);
    expect(state.preview.current.inline).to.be.a('string').that.includes('-OutputDir');
  });

  test('toggle diff as success command updates setting and status bar', async () => {
    const config = vscode.workspace.getConfiguration();
    await config.update('comparevi.diffAsSuccess', false, vscode.ConfigurationTarget.Workspace);
    await vscode.commands.executeCommand('comparevi.toggleDiffSuccess');
    expect(config.get('comparevi.diffAsSuccess')).to.be.true;
    testingApi.setStatusBarResult(1, true, true);
    const statusItem = testingApi.getStatusItem();
    expect(statusItem.text).to.include('VI Diff');
  });

  test('run commit compare respects custom refs and updates status bar', async () => {
    const config = vscode.workspace.getConfiguration();
    await config.update('comparevi.commitRefs.base', 'HEAD~4', vscode.ConfigurationTarget.Workspace);
    await config.update('comparevi.commitRefs.head', 'HEAD~1', vscode.ConfigurationTarget.Workspace);

    const outDir = path.join(workspaceRoot, 'tests', 'results', 'manual-vi2-compare');
    if (fs.existsSync(outDir)) {
      fs.rmSync(outDir, { recursive: true, force: true });
    }

    const capturePromise = new Promise((resolve) => {
      installSpawnStub(testingApi, (dir) => resolve(dir));
    });

    const result = await testingApi.runCommitCompare({ baseRef: 'HEAD~3', headRef: 'HEAD', updateSettings: true });
    const outputDir = await capturePromise;
    testingApi.resetSpawnOverride();
    expect(outputDir).to.equal(outDir);
    expect(result.outDir).to.equal(outDir);

    const updatedBase = config.get('comparevi.commitRefs.base');
    expect(updatedBase).to.equal('HEAD~3');
    const statusItem = testingApi.getStatusItem();
    expect(statusItem.text).to.include('VI Diff');
  });
});
