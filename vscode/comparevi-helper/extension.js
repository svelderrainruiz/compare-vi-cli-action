const vscode = require('vscode');
const path = require('path');
const fs = require('fs');
const fsp = fs.promises;
const os = require('os');
const childProcess = require('child_process');
const {
  resolveLabVIEWPath,
  buildPwshArgsFile,
  buildPwshCommandWrapper,
  summarizeCapture,
  detectCliArtifacts
} = require('./lib/core');
const git = require('./lib/git');
const telemetry = require('./lib/telemetry');
const providerRegistry = require('./providers');
const {
  registerProvider,
  unregisterProvider,
  listProviders,
  getProvider,
  listProviderMetadata,
  getActiveProvider,
  getActiveProviderId,
  setActiveProvider,
  onDidChangeActiveProvider
} = providerRegistry;
const createGcliProvider = require('./providers/gcli');

function interpolateWorkspaceFolder(input) {
  const folders = vscode.workspace.workspaceFolders;
  const ws = folders && folders.length ? folders[0].uri.fsPath : process.cwd();
  return input.replace(/\$\{workspaceFolder\}/g, ws);
}

let output;
let statusItem;
let workspaceState;
let spawnOverride;
let viCompareProvider;
let statusBarEnabled = true;
let lastStatusResult = { exitCode: null, diff: false };
let compareVIProviderRegistration;
let gcliProviderRegistration;

const SOURCE_STATE_KEY = 'comparevi.lastSources';
const TEMP_PREFIX = path.join(os.tmpdir(), 'comparevi-');
const DEFAULT_PARAMETER_FLAGS = ['-nobdcosm', '-nofppos', '-noattr', '-nofp'];
const DEFAULT_GCLI_PATH = process.platform === 'win32'
  ? 'C:\\Program Files\\G-CLI\\bin\\g-cli.exe'
  : '/usr/local/bin/g-cli';

function getKnownParameters(config) {
  const flags = config?.get?.('comparevi.knownFlags');
  return (Array.isArray(flags) && flags.length) ? flags : DEFAULT_PARAMETER_FLAGS;
}

function spawnPwsh(args, options) {
  if (spawnOverride) {
    return spawnOverride(args, options);
  }
  return childProcess.spawn('pwsh', args, options);
}

function setSpawnOverride(fn) {
  spawnOverride = fn;
}

function resetSpawnOverride() {
  spawnOverride = undefined;
}

async function recordTelemetry(event, data = {}) {
  const providerId = getActiveProviderId ? (getActiveProviderId() || 'comparevi') : 'comparevi';
  const payload = {
    provider: providerId,
    ...data
  };
  await telemetry.writeEvent(event, payload);
}

function getNonce() {
  const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
  let text = '';
  for (let i = 0; i < 16; i++) {
    text += chars.charAt(Math.floor(Math.random() * chars.length));
  }
  return text;
}

function toWorkspaceRelative(fsPath) {
  try {
    const folders = vscode.workspace.workspaceFolders;
    if (!folders || !folders.length) return fsPath;
    const ws = folders[0].uri.fsPath;
    const normFs = path.resolve(fsPath);
    const normWs = path.resolve(ws);
    if (normFs.toLowerCase().startsWith(normWs.toLowerCase() + path.sep)) {
      return normFs.replace(new RegExp('^' + normWs.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'), 'i'), '${workspaceFolder}');
    }
    return fsPath;
  } catch { return fsPath; }
}

function readPresets(config) {
  try {
    const obj = config.get('comparevi.presets');
    if (obj && typeof obj === 'object') return obj;
  } catch {}
  return {};
}

async function writePresets(next) {
  try {
    await vscode.workspace.getConfiguration().update('comparevi.presets', next, vscode.ConfigurationTarget.Workspace);
    return true;
  } catch { return false; }
}

async function persistLabviewSnapshot(outDir, labviewIniPath) {
  try {
    if (!labviewIniPath || !fs.existsSync(labviewIniPath)) {
      return false;
    }
    await fsp.mkdir(outDir, { recursive: true });
    const snapshotPath = path.join(outDir, 'LabVIEW.ini.snapshot');
    const iniContent = await fsp.readFile(labviewIniPath, 'utf8');
    await fsp.writeFile(snapshotPath, iniContent, 'utf8');
    return true;
  } catch {
    return false;
  }
}

async function pickFlags(knownFlags, initial) {
  const previous = workspaceState?.get('comparevi.lastFlags');
  const seed = Array.isArray(initial) && initial.length ? initial : (Array.isArray(previous) ? previous : []);
  const items = knownFlags.map((flag) => ({ label: flag, picked: seed.includes(flag) }));
  const selection = await vscode.window.showQuickPick(items, {
    canPickMany: true,
    placeHolder: 'Select LVCompare flags'
  });
  const chosen = selection ? selection.map((item) => item.label) : seed;
  if (workspaceState) {
    try { await workspaceState.update('comparevi.lastFlags', chosen); } catch {}
  }
  return chosen;
}

function getOutput() {
  if (!output) output = vscode.window.createOutputChannel('CompareVI');
  return output;
}

function getStatusItem() {
  if (!statusItem) {
    statusItem = vscode.window.createStatusBarItem(vscode.StatusBarAlignment.Left, 100);
    statusItem.tooltip = 'CompareVI result — click to toggle Treat Diff as Success';
    statusItem.hide();
  }
  return statusItem;
}

function applyStatusBarConfig(config) {
  statusBarEnabled = !!config.get('comparevi.statusBar');
  const item = getStatusItem();
  if (!statusBarEnabled) {
    item.hide();
    return;
  }
  item.command = 'comparevi.toggleDiffSuccess';
  const diffAsSuccess = !!config.get('comparevi.diffAsSuccess');
  const year = String(config.get('comparevi.labview.year') || '2025');
  const bits = String(config.get('comparevi.labview.bits') || '64');
  const labviewExePath = resolveLabVIEWPath(year, bits);
  const labviewIniPath = path.join(path.dirname(labviewExePath), 'LabVIEW.ini');
  const hasLabviewIni = fs.existsSync(labviewIniPath);
  if (!hasLabviewIni) {
    vscode.window.showWarningMessage(`LabVIEW.ini not found next to LabVIEW.exe (${labviewIniPath}). CompareVI may run with unexpected defaults.`);
  }
  setStatusBarResult(lastStatusResult.exitCode, lastStatusResult.diff, diffAsSuccess);
}

function setStatusBarPending(label = 'CompareVI running…') {
  if (!statusBarEnabled) return;
  const item = getStatusItem();
  item.text = `$(sync~spin) ${label}`;
  item.tooltip = `${label}\nClick to toggle Treat Diff as Success.`;
  item.command = 'comparevi.toggleDiffSuccess';
  item.show();
}

function setStatusBarResult(exitCode, diff, diffAsSuccess) {
  lastStatusResult = { exitCode, diff, timestamp: new Date() };
  if (!statusBarEnabled) return;
  const item = getStatusItem();
  const treatDiff = typeof diffAsSuccess === 'boolean' ? diffAsSuccess : !!vscode.workspace.getConfiguration().get('comparevi.diffAsSuccess');
  let text = '$(git-compare) CompareVI';
  let tooltip = 'CompareVI: awaiting run.';
  if (typeof exitCode === 'number') {
    if (exitCode === 0) {
      text = '$(check) VI: No Diff';
      tooltip = 'CompareVI finished without differences.';
    } else if (exitCode === 1) {
      if (treatDiff) {
        text = '$(git-compare) VI Diff';
        tooltip = 'Diff found (treated as success).';
      } else {
        text = '$(warning) VI Diff';
        tooltip = 'Diff found. Toggle Treat Diff as Success to suppress warnings.';
      }
    } else {
      text = `$(error) VI: Exit ${exitCode}`;
      tooltip = 'CompareVI error. Check output channel for details.';
    }
  }
  item.text = text;
  const when = lastStatusResult.timestamp ? `Last run: ${lastStatusResult.timestamp.toLocaleTimeString()}` : '';
  item.tooltip = `${tooltip}${when ? `\n${when}` : ''}\nClick to toggle Treat Diff as Success.`;
  item.command = 'comparevi.toggleDiffSuccess';
  if (statusBarEnabled) item.show();
}

function getRepoRoot() {
  const folders = vscode.workspace.workspaceFolders;
  if (!folders || !folders.length) {
    throw new Error('CompareVI requires an open workspace');
  }
  return folders[0].uri.fsPath;
}

function getSourceState() {
  return workspaceState?.get(SOURCE_STATE_KEY) || {};
}

async function updateSourceState(profileName, role, entryId, viPath) {
  if (!workspaceState) return;
  const state = getSourceState();
  const next = { ...(state[profileName] || {}) , [role]: { id: entryId, path: viPath } };
  const result = { ...state, [profileName]: next };
  await workspaceState.update(SOURCE_STATE_KEY, result);
}

function findVisEntry(profile, id) {
  if (!Array.isArray(profile.vis)) return undefined;
  return profile.vis.find((entry) => entry.id === id);
}

async function ensureViPath(repoRoot, entry, config, showPicker) {
  if (entry.path && !showPicker) {
    return entry.path;
  }

  const candidates = git.listVisAtCommit(repoRoot, entry.ref);
  if (!candidates.length) {
    throw new Error(`No VIs found in commit ${entry.ref}`);
  }

  let defaultPath = entry.path;
  if (!defaultPath || !candidates.includes(defaultPath)) {
    defaultPath = candidates[0];
  }

  if (!showPicker && defaultPath) {
    return defaultPath;
  }

  const pick = await vscode.window.showQuickPick(candidates.map((p) => ({ label: p })), {
    placeHolder: `Select VI from ${entry.ref}`,
    matchOnDescription: false,
    matchOnDetail: false
  });
  if (!pick) {
    throw new Error('Cancelled VI selection');
  }
  return pick.label;
}

async function selectCommitEntry(profile, role, repoRoot, config) {
  const entries = Array.isArray(profile.vis) ? profile.vis : [];
  if (!entries.length) {
    throw new Error('Profile does not define commit sources');
  }

  const showPicker = !!config.get('comparevi.showSourcePicker');
  const state = getSourceState();
  const remembered = state[profile.name]?.[role];
  const defaultId = remembered?.id
    || (role === 'base' ? profile.defaultBase : profile.defaultHead)
    || entries[0].id;

  const infoList = await Promise.all(entries.map(async (entry) => {
    const info = git.getCommitInfo(repoRoot, entry.ref);
    return { entry, info };
  }));

  let chosen;
  if (showPicker) {
    const items = infoList.map(({ entry, info }) => ({
      label: entry.id,
      description: `${info.shortHash || info.ref} ${info.subject || ''}`.trim(),
      detail: info.date || '',
      entry,
      info
    }));
    const active = items.find((item) => item.entry.id === defaultId);
    const pick = await vscode.window.showQuickPick(items, {
      placeHolder: `Select ${role} commit for ${profile.name}`,
      activeItem: active,
      matchOnDetail: true
    });
    chosen = pick || active || items[0];
  } else {
    chosen = infoList.find(({ entry }) => entry.id === defaultId) || infoList[0];
  }

  if (!chosen) {
    throw new Error('No commit entry selected');
  }

  const viPath = await ensureViPath(repoRoot, chosen.entry, config, showPicker);
  await updateSourceState(profile.name, role, chosen.entry.id, viPath);
  return {
    entry: chosen.entry,
    commit: chosen.info,
    viPath
  };
}

async function extractCommitEntry(repoRoot, selection, tempDir, role) {
  const target = path.join(tempDir, `${role}.vi`);
  git.extractFileAtCommit(repoRoot, selection.entry.ref, selection.viPath, target);
  return {
    tempPath: target,
    id: selection.entry.id,
    ref: selection.entry.ref,
    viPath: selection.viPath,
    commit: selection.commit
  };
}

async function prepareCommitSources(profile, config, repoRoot) {
  const keepTemp = !!config.get('comparevi.keepTempVi');
  const tempDir = await fsp.mkdtemp(TEMP_PREFIX);
  let baseSelection;
  let headSelection;
  try {
    baseSelection = await selectCommitEntry(profile, 'base', repoRoot, config);
    headSelection = await selectCommitEntry(profile, 'head', repoRoot, config);
    const base = await extractCommitEntry(repoRoot, baseSelection, tempDir, 'base');
    const head = await extractCommitEntry(repoRoot, headSelection, tempDir, 'head');
    return { tempDir, base, head, keepTemp };
  } catch (error) {
    if (!keepTemp) {
      await cleanupTempDir(tempDir);
    }
    throw error;
  }
}

async function cleanupTempDir(tempDir, keep = false) {
  if (keep) return;
  try {
    await fsp.rm(tempDir, { recursive: true, force: true });
  } catch {}
}

async function presentSummary({ repoRoot, outDir, capInfo, reportPath, diffAsSuccess, autoOpenReportOnDiff, showSummary, sources }) {
  const ch = getOutput();
  const diff = capInfo && capInfo.exitCode === 1;
  const normExit = diff && diffAsSuccess ? 0 : (capInfo ? capInfo.exitCode : undefined);
  const header = `CompareVI: ${diff ? 'Diff' : (normExit === 0 ? 'No Diff' : `Exit ${capInfo?.exitCode}`)}`;
  const lines = [];
  lines.push(`[${new Date().toISOString()}] ${header}`);
  lines.push(`- OutputDir: ${outDir}`);
  if (capInfo) {
    lines.push(`- Exit: ${capInfo.exitCode}`);
    if (typeof capInfo.seconds === 'number') lines.push(`- Duration: ${capInfo.seconds}s`);
    lines.push(`- Capture: ${capInfo.capPath}`);
    if (capInfo.command) lines.push(`- Command: ${capInfo.command}`);
  }
  if (sources?.base) {
    const baseCommit = sources.base.commit || {};
    lines.push(`- Base: ${sources.base.id || ''} (${baseCommit.shortHash || baseCommit.ref || ''}) ${baseCommit.subject || ''} [${sources.base.viPath || ''}]`.trim());
  }
  if (sources?.head) {
    const headCommit = sources.head.commit || {};
    lines.push(`- Head: ${sources.head.id || ''} (${headCommit.shortHash || headCommit.ref || ''}) ${headCommit.subject || ''} [${sources.head.viPath || ''}]`.trim());
  }
  const cli = detectCliArtifacts(outDir, capInfo);
  const hasReport = !!(reportPath && fs.existsSync(reportPath));
  lines.push(`- Report: ${hasReport}`);
  if (cli.lvcliStdout) lines.push(`- CLI stdout: ${cli.lvcliStdout}`);
  if (cli.lvcliStderr) lines.push(`- CLI stderr: ${cli.lvcliStderr}`);
  if (cli.lvcompareStdout) lines.push(`- LVCompare stdout: ${cli.lvcompareStdout}`);
  if (cli.lvcompareStderr) lines.push(`- LVCompare stderr: ${cli.lvcompareStderr}`);
  if (cli.imagesDir) lines.push(`- CLI images: ${cli.imagesDir} (${(cli.imageFiles||[]).length} files)`);
  ch.appendLine(lines.join('\n'));
  ch.show(true);

  setStatusBarResult(capInfo ? capInfo.exitCode : undefined, diff, diffAsSuccess);

  if (diff && autoOpenReportOnDiff && hasReport) {
    try { await vscode.env.openExternal(vscode.Uri.file(reportPath)); } catch {}
  }

  if (showSummary) {
    const actions = [];
    if (hasReport) actions.push('Open Report');
    actions.push('Reveal Output Folder');
    actions.push('More…');
    const pick = await vscode.window.showInformationMessage(header, ...actions);
    if (pick === 'Open Report') {
      await vscode.env.openExternal(vscode.Uri.file(reportPath));
    } else if (pick === 'Reveal Output Folder') {
      await vscode.commands.executeCommand('revealFileInOS', vscode.Uri.file(outDir));
    } else if (pick === 'More…') {
      const more = [];
      if (capInfo && capInfo.capPath && fs.existsSync(capInfo.capPath)) more.push({ label: 'Open Capture JSON', action: 'openCap' });
      if (cli.lvcliStdout) more.push({ label: 'Open CLI Stdout', action: 'openCliOut', path: cli.lvcliStdout });
      if (cli.lvcliStderr) more.push({ label: 'Open CLI Stderr', action: 'openCliErr', path: cli.lvcliStderr });
      if (cli.lvcompareStdout) more.push({ label: 'Open LVCompare Stdout', action: 'openLvOut', path: cli.lvcompareStdout });
      if (cli.lvcompareStderr) more.push({ label: 'Open LVCompare Stderr', action: 'openLvErr', path: cli.lvcompareStderr });
      if (cli.imagesDir && (cli.imageFiles || []).length) more.push({ label: 'Open CLI Images…', action: 'openImages', dir: cli.imagesDir, files: cli.imageFiles });
      if (sources?.base?.tempPath) more.push({ label: 'Open Base VI (temp)', action: 'openBaseVi', path: sources.base.tempPath });
      if (sources?.head?.tempPath) more.push({ label: 'Open Head VI (temp)', action: 'openHeadVi', path: sources.head.tempPath });
      if (!more.length) {
        await vscode.window.showInformationMessage('No additional artifacts found.');
      } else {
        const sel = await vscode.window.showQuickPick(more.map(m => m.label), { placeHolder: 'Choose an artifact action' });
        const chosen = more.find(m => m.label === sel);
        if (chosen) {
          if (chosen.action === 'openCap') {
            const doc = await vscode.workspace.openTextDocument(vscode.Uri.file(capInfo.capPath));
            await vscode.window.showTextDocument(doc);
          } else if (chosen.action === 'openCliOut' || chosen.action === 'openCliErr' || chosen.action === 'openLvOut' || chosen.action === 'openLvErr') {
            const doc = await vscode.workspace.openTextDocument(vscode.Uri.file(chosen.path));
            await vscode.window.showTextDocument(doc);
          } else if (chosen.action === 'openBaseVi' || chosen.action === 'openHeadVi') {
            const doc = await vscode.workspace.openTextDocument(vscode.Uri.file(chosen.path));
            await vscode.window.showTextDocument(doc, { preview: false });
          } else if (chosen.action === 'openImages') {
            const filePick = await vscode.window.showQuickPick((chosen.files || []).map(f => path.basename(f)), { placeHolder: 'Select an image to open' });
            if (filePick) {
              const full = path.join(chosen.dir, filePick);
              await vscode.commands.executeCommand('vscode.open', vscode.Uri.file(full));
    }
  }
  viCompareProvider?.refresh?.();
}
      }
    }
  }
async function runManualCompareInternal(options = {}) {
  const {
    flagsOverride,
    forcePassFlags = false,
    promptForLabVIEW = true,
    origin = 'manual'
  } = options;

  const folders = vscode.workspace.workspaceFolders;
  if (!folders || folders.length === 0) {
    vscode.window.showErrorMessage('Open the repository folder before running CompareVI.');
    return false;
  }
  const repoRoot = folders[0].uri.fsPath;

  const config = vscode.workspace.getConfiguration();
  let year = config.get('comparevi.labview.year') || '2025';
  let bits = config.get('comparevi.labview.bits') || '64';

  if (promptForLabVIEW) {
    const yearPick = await vscode.window.showQuickPick(['2021', '2022', '2023', '2024', '2025'], {
      placeHolder: `Select LabVIEW year (current ${year})`
    });
    if (yearPick) year = yearPick;
    const bitsPick = await vscode.window.showQuickPick(['64', '32'], {
      placeHolder: `Select LabVIEW bitness (current ${bits})`
    });
    if (bitsPick) bits = bitsPick;
  }

  const baseVi = interpolateWorkspaceFolder(config.get('comparevi.paths.baseVi') || '${workspaceFolder}/VI2.vi');
  const headVi = interpolateWorkspaceFolder(config.get('comparevi.paths.headVi') || '${workspaceFolder}/tmp-commit-236ffab/VI2.vi');
  const outDir = interpolateWorkspaceFolder(config.get('comparevi.output.dir') || 'tests/results/manual-vi2-compare');
  const labviewExePath = resolveLabVIEWPath(year, bits);
  const labviewIniPath = path.join(path.dirname(labviewExePath), 'LabVIEW.ini');
  const hasLabviewIni = fs.existsSync(labviewIniPath);

  if (process.platform !== 'win32') {
    vscode.window.showErrorMessage('CompareVI manual run requires Windows.');
    return false;
  }

  const missing = [];
  if (!fs.existsSync(baseVi)) missing.push(`Base VI: ${baseVi}`);
  if (!fs.existsSync(headVi)) missing.push(`Head VI: ${headVi}`);
  if (!fs.existsSync(labviewExePath)) missing.push(`LabVIEW.exe: ${labviewExePath}`);
  if (missing.length) {
    const ans = await vscode.window.showWarningMessage(
      `Some inputs do not exist. Continue anyway?\n\n${missing.join('\n')}`,
      { modal: true }, 'Continue', 'Cancel'
    );
    if (ans !== 'Continue') return false;
  }

  const diffAsSuccess = !!config.get('comparevi.diffAsSuccess');
  const autoOpen = !!config.get('comparevi.autoOpenReportOnDiff');
  const showSummary = !!config.get('comparevi.showSummary');
  const passFlagsConfig = !!config.get('comparevi.passFlags');
  const showFlagPicker = !!config.get('comparevi.showFlagPicker');
  const knownFlags = getKnownParameters(config);

  let selectedFlags;
  if (Array.isArray(flagsOverride)) {
    selectedFlags = flagsOverride;
  } else if (showFlagPicker && passFlagsConfig) {
    const defaults = config.get('comparevi.flags') || [];
    selectedFlags = await pickFlags(knownFlags, defaults);
  } else if (passFlagsConfig) {
    selectedFlags = config.get('comparevi.flags') || [];
  }

  const shouldPassFlags = forcePassFlags || passFlagsConfig || Array.isArray(flagsOverride);
  const flagsToUse = shouldPassFlags ? (Array.isArray(selectedFlags) ? selectedFlags : []) : undefined;

  if (shouldPassFlags && Array.isArray(flagsToUse) && workspaceState) {
    try { await workspaceState.update('comparevi.lastFlags', flagsToUse); } catch {}
    viCompareProvider?.refresh?.();
  }

  const scriptPath = path.join(repoRoot, 'tools', 'Invoke-LVCompare.ps1');
  const args = buildPwshCommandWrapper(scriptPath, baseVi, headVi, labviewExePath, outDir, flagsToUse, diffAsSuccess);
  const ch = getOutput();
  const originLabel = origin === 'panel' ? ' (noise tester)' : '';
  ch.appendLine(`[${new Date().toISOString()}] CompareVI started${originLabel}`);
  await recordTelemetry('comparevi.manual.start', {
    base: toWorkspaceRelative(baseVi),
    head: toWorkspaceRelative(headVi),
    outputDir: toWorkspaceRelative(outDir),
    flags: Array.isArray(flagsToUse) ? flagsToUse : [],
    origin
  });
  const proc = spawnPwsh(args, { cwd: repoRoot });
  proc.stdout.on('data', d => ch.append(String(d)));
  proc.stderr.on('data', d => ch.append(String(d)));
  proc.on('close', async (code) => {
    const capPath = path.join(outDir, 'lvcompare-capture.json');
    const reportPath = path.join(outDir, 'compare-report.html');
    const capInfo = summarizeCapture(capPath);
    const norm = (code === 1 && diffAsSuccess) ? 0 : code;
    const snapshotWritten = await persistLabviewSnapshot(outDir, hasLabviewIni ? labviewIniPath : undefined);
    await presentSummary({ repoRoot, outDir, capInfo, reportPath, diffAsSuccess, autoOpenReportOnDiff: autoOpen, showSummary });
    if (norm !== 0) {
      vscode.window.showErrorMessage(`CompareVI exited with code ${code}`);
    }
    await recordTelemetry('comparevi.manual.complete', {
      exitCode: code,
      normalizedExitCode: norm,
      diffDetected: capInfo ? capInfo.exitCode === 1 : undefined,
      outputDir: toWorkspaceRelative(outDir),
      origin,
      snapshotWritten
    });
    viCompareProvider?.refresh?.();
  });
  return true;
}

async function runManualCompare() {
  return runManualCompareInternal();
}

async function runCommitCompareFlow({ baseRef, headRef, updateSettings = false } = {}) {
  const config = vscode.workspace.getConfiguration();
  const repoRoot = getRepoRoot();
  const effectiveBase = String(baseRef || config.get('comparevi.commitRefs.base') || 'HEAD~1').trim();
  const effectiveHead = String(headRef || config.get('comparevi.commitRefs.head') || 'HEAD').trim();
  if (updateSettings) {
    await config.update('comparevi.commitRefs.base', effectiveBase, vscode.ConfigurationTarget.Workspace);
    await config.update('comparevi.commitRefs.head', effectiveHead, vscode.ConfigurationTarget.Workspace);
  }

  const year = String(config.get('comparevi.labview.year') || '2025');
  const bits = String(config.get('comparevi.labview.bits') || '64');
  const labviewExePath = resolveLabVIEWPath(year, bits);
  const labviewIniPath = path.join(path.dirname(labviewExePath), 'LabVIEW.ini');
  const outDir = interpolateWorkspaceFolder(config.get('comparevi.output.dir') || 'tests/results/manual-vi2-compare');
  const diffAsSuccess = !!config.get('comparevi.diffAsSuccess');
  const profile = {
    name: 'panel-commit',
    vis: [
      { id: 'base', ref: effectiveBase },
      { id: 'head', ref: effectiveHead }
    ],
    defaultBase: 'base',
    defaultHead: 'head'
  };

  setStatusBarPending('CompareVI commit compare…');

  let comparison;
  try {
    comparison = await prepareCommitSources(profile, config, repoRoot);
  } catch (error) {
    setStatusBarResult(lastStatusResult.exitCode, lastStatusResult.diff, diffAsSuccess);
    throw error;
  }

  const { tempDir, base, head, keepTemp } = comparison;
  const scriptPath = path.join(repoRoot, 'tools', 'Invoke-LVCompare.ps1');
  const args = buildPwshCommandWrapper(scriptPath, base.tempPath, head.tempPath, labviewExePath, outDir, undefined, diffAsSuccess);
  await recordTelemetry('comparevi.commit.start', {
    baseRef: effectiveBase,
    headRef: effectiveHead,
    outputDir: toWorkspaceRelative(outDir)
  });

  return await new Promise((resolve, reject) => {
    const proc = spawnPwsh(args, { cwd: repoRoot });
    proc.stdout.on('data', (d) => getOutput().append(String(d)));
    proc.stderr.on('data', (d) => getOutput().append(String(d)));
    proc.on('error', async (err) => {
      await cleanupTempDir(tempDir, keepTemp);
      setStatusBarResult(lastStatusResult.exitCode, lastStatusResult.diff, diffAsSuccess);
      reject(err);
    });
    proc.on('close', async (code) => {
      try {
        const capPath = path.join(outDir, 'lvcompare-capture.json');
        const reportPath = path.join(outDir, 'compare-report.html');
        const capInfo = summarizeCapture(capPath);
        const snapshotWritten = await persistLabviewSnapshot(outDir, labviewIniPath);
        await presentSummary({
          repoRoot,
          outDir,
          capInfo,
          reportPath,
          diffAsSuccess,
          autoOpenReportOnDiff: !!config.get('comparevi.autoOpenReportOnDiff'),
          showSummary: !!config.get('comparevi.showSummary'),
          sources: { base, head }
        });
        await recordTelemetry('comparevi.commit.complete', {
          exitCode: code,
          normalizedExitCode: (code === 1 && diffAsSuccess) ? 0 : code,
          diffDetected: capInfo ? capInfo.exitCode === 1 : undefined,
          outputDir: toWorkspaceRelative(outDir),
          baseRef: effectiveBase,
          headRef: effectiveHead,
          snapshotWritten
        });
      } finally {
        await cleanupTempDir(tempDir, keepTemp);
      }
      if (code !== 0 && !(code === 1 && diffAsSuccess)) {
        const err = new Error(`CompareVI exited with code ${code}`);
        err.exitCode = code;
        return reject(err);
      }
      resolve({ code, outDir });
    });
  });
}

// Compare the currently active VI with the previous commit version of the same path
async function compareActiveWithPrevious() {
  const folders = vscode.workspace.workspaceFolders;
  if (!folders || folders.length === 0) {
    vscode.window.showErrorMessage('Open the repository folder before running CompareVI.');
    return;
  }
  const repoRoot = folders[0].uri.fsPath;

  // Resolve active VI path
  const active = vscode.window.activeTextEditor?.document?.uri?.fsPath;
  if (!active || path.extname(active).toLowerCase() !== '.vi') {
    vscode.window.showInformationMessage('Open a .vi file in the editor to compare with previous commit.');
    return;
  }

  const relPath = path.relative(repoRoot, active);
  if (!relPath || relPath.startsWith('..') || path.isAbsolute(relPath)) {
    vscode.window.showInformationMessage('Active VI must live within the current workspace folder.');
    return;
  }
  const relGitPath = relPath.split(path.sep).join('/');

  const config = vscode.workspace.getConfiguration();
  const year = String(config.get('comparevi.labview.year') || '2025');
  const bits = String(config.get('comparevi.labview.bits') || '64');
  const labviewExePath = resolveLabVIEWPath(year, bits);
  const labviewIniPath = path.join(path.dirname(labviewExePath), 'LabVIEW.ini');
  const outDir = interpolateWorkspaceFolder(config.get('comparevi.output.dir') || 'tests/results/manual-vi2-compare');

  if (process.platform !== 'win32') {
    vscode.window.showErrorMessage('CompareVI requires Windows to launch LabVIEW.');
    return;
  }

  if (!fs.existsSync(labviewExePath)) {
    const installed = detectInstalledLabVIEWs();
    const available = installed[year] ? Object.entries(installed[year]).map(([b, p]) => `${year}-${b}: ${p}`) : [];
    const extra = available.length ? `\nAvailable for ${year}:\n${available.join('\n')}` : '';
    const res = await vscode.window.showWarningMessage(`LabVIEW.exe not found at configured path:\n${labviewExePath}${extra}\n\nContinue anyway?`, { modal: true }, 'Continue', 'Cancel');
    if (res !== 'Continue') return;
  }

  const diffAsSuccess = !!config.get('comparevi.diffAsSuccess');
  const autoOpen = !!config.get('comparevi.autoOpenReportOnDiff');
  const showSummary = !!config.get('comparevi.showSummary');
  const passFlags = !!config.get('comparevi.passFlags');
  const showFlagPicker = !!config.get('comparevi.showFlagPicker');
  const knownFlags = getKnownParameters(config);
  let selectedFlags;
  if (showFlagPicker) {
    selectedFlags = await pickFlags(knownFlags, passFlags ? (config.get('comparevi.flags') || []) : undefined);
  } else if (passFlags) {
    selectedFlags = config.get('comparevi.flags') || [];
  }

  const keepTemp = !!config.get('comparevi.keepTempVi');
  const tempDir = await fsp.mkdtemp(TEMP_PREFIX);

  // Prepare commit selections
  let baseCommitInfo, headCommitInfo;
  try {
    baseCommitInfo = git.getCommitInfo(repoRoot, 'HEAD~1');
    headCommitInfo = git.getCommitInfo(repoRoot, 'HEAD');
  } catch (e) {
    await cleanupTempDir(tempDir);
    vscode.window.showErrorMessage(`Failed to resolve commit info: ${e.message}`);
    return;
  }

  // Extract files
  let baseTemp, headTemp;
  try {
    baseTemp = path.join(tempDir, 'base.vi');
    headTemp = path.join(tempDir, 'head.vi');
    git.extractFileAtCommit(repoRoot, 'HEAD~1', relGitPath, baseTemp);
    git.extractFileAtCommit(repoRoot, 'HEAD', relGitPath, headTemp);
  } catch (e) {
    await cleanupTempDir(tempDir);
    vscode.window.showErrorMessage(`Failed to extract VI from git: ${e.message}`);
    return;
  }

  const scriptPath = path.join(repoRoot, 'tools', 'Invoke-LVCompare.ps1');
  setStatusBarPending('CompareVI running…');
  const args = buildPwshCommandWrapper(scriptPath, baseTemp, headTemp, labviewExePath, outDir, selectedFlags, diffAsSuccess);
  const ch = getOutput();
  ch.appendLine(`[${new Date().toISOString()}] CompareVI: Active vs Previous started`);
  await recordTelemetry('comparevi.active.start', {
    vi: toWorkspaceRelative(active),
    outputDir: toWorkspaceRelative(outDir)
  });
  const proc = spawnPwsh(args, { cwd: repoRoot });
  proc.stdout.on('data', d => ch.append(String(d)));
  proc.stderr.on('data', d => ch.append(String(d)));
  proc.on('close', async (code) => {
    const capPath = path.join(outDir, 'lvcompare-capture.json');
    const reportPath = path.join(outDir, 'compare-report.html');
    const capInfo = summarizeCapture(capPath);
    const norm = (code === 1 && diffAsSuccess) ? 0 : code;
    const snapshotWritten = await persistLabviewSnapshot(outDir, labviewIniPath);
    await presentSummary({
      repoRoot,
      outDir,
      capInfo,
      reportPath,
      diffAsSuccess,
      autoOpenReportOnDiff: autoOpen,
      showSummary,
      sources: {
        base: { tempPath: baseTemp, id: 'previous', viPath: relGitPath, commit: baseCommitInfo },
        head: { tempPath: headTemp, id: 'root', viPath: relGitPath, commit: headCommitInfo }
      }
    });
    await cleanupTempDir(tempDir, keepTemp);
    if (norm !== 0) {
      vscode.window.showErrorMessage(`CompareVI exited with code ${code}`);
    }
    await recordTelemetry('comparevi.active.complete', {
      exitCode: code,
      normalizedExitCode: norm,
      diffDetected: capInfo ? capInfo.exitCode === 1 : undefined,
      outputDir: toWorkspaceRelative(outDir),
      vi: toWorkspaceRelative(active),
      snapshotWritten
    });
  });
}

function resolveProfilesPath(config) {
  const rel = config.get('comparevi.profilesPath') || 'tools/comparevi.profiles.json';
  const folders = vscode.workspace.workspaceFolders;
  const ws = folders && folders.length ? folders[0].uri.fsPath : process.cwd();
  return path.isAbsolute(rel) ? rel : path.join(ws, rel);
}

function loadProfiles(profilesPath) {
  try {
    if (!fs.existsSync(profilesPath)) return [];
    const raw = fs.readFileSync(profilesPath, 'utf8');
    const obj = JSON.parse(raw);
    if (Array.isArray(obj)) return obj;
    if (obj && Array.isArray(obj.profiles)) return obj.profiles;
    return [];
  } catch (e) {
    vscode.window.showErrorMessage(`Failed to read profiles: ${e.message}`);
    return [];
  }
}

function expandProfile(profile) {
  const p = Object.assign({}, profile);
  if (p.baseVi) p.baseVi = interpolateWorkspaceFolder(p.baseVi);
  if (p.headVi) p.headVi = interpolateWorkspaceFolder(p.headVi);
  if (p.outputDir) p.outputDir = interpolateWorkspaceFolder(p.outputDir);
  return p;
}

function detectInstalledLabVIEWs() {
  const env = process.env;
  const pf64 = env['ProgramW6432'] || env['ProgramFiles'] || 'C:\\Program Files';
  const pf86 = env['ProgramFiles(x86)'] || pf64;
  const years = ['2021','2022','2023','2024','2025'];
  const bits = ['64','32'];
  const map = {};
  for (const y of years) {
    map[y] = {};
    for (const b of bits) {
      const parent = b === '32' ? pf86 : pf64;
      const exe = path.join(parent, 'National Instruments', `LabVIEW ${y}`, 'LabVIEW.exe');
      if (fs.existsSync(exe)) map[y][b] = exe;
    }
  }
  return map;
}

async function runProfileCommand() {
  const config = vscode.workspace.getConfiguration();
  const profilesPath = resolveProfilesPath(config);
  const profiles = loadProfiles(profilesPath);
  if (!profiles.length) {
    const ans = await vscode.window.showWarningMessage('No profiles found. Create sample profiles?', 'Create', 'Cancel');
    if (ans === 'Create') {
      await createSampleProfiles(profilesPath);
      const doc = await vscode.workspace.openTextDocument(vscode.Uri.file(profilesPath));
      await vscode.window.showTextDocument(doc);
    }
    return;
  }

  const items = profiles.map(p => ({ label: p.name || 'unnamed', description: `${p.year || '?'}-${p.bits || '?'}`, profile: p }));
  const pick = await vscode.window.showQuickPick(items, { placeHolder: 'Select CompareVI profile' });
  if (!pick) return;
  const profile = pick.profile;
  await runProfileWithProfile(profile, config, 'command');
}

async function runProfileWithProfile(profile, config, origin = 'command') {
  const repoRoot = getRepoRoot();
  const year = String(profile.year || config.get('comparevi.labview.year') || '2025');
  const bits = String(profile.bits || config.get('comparevi.labview.bits') || '64');
  const labviewExePath = profile.labviewExePath || resolveLabVIEWPath(year, bits);
  const outDir = profile.outputDir
    ? interpolateWorkspaceFolder(profile.outputDir)
    : interpolateWorkspaceFolder(config.get('comparevi.output.dir') || 'tests/results/manual-vi2-compare');
  const labviewIniPath = path.join(path.dirname(labviewExePath), 'LabVIEW.ini');

  if (!fs.existsSync(labviewExePath)) {
    const installed = detectInstalledLabVIEWs();
    const available = installed[year] ? Object.entries(installed[year]).map(([b,p]) => `${year}-${b}: ${p}`) : [];
    const extra = available.length ? `\nAvailable for ${year}:\n${available.join('\n')}` : '';
    const res = await vscode.window.showWarningMessage(`LabVIEW.exe not found at configured path:\n${labviewExePath}${extra}\n\nContinue anyway?`, { modal: true }, 'Continue', 'Cancel');
    if (res !== 'Continue') return;
  }

  const diffAsSuccess = !!config.get('comparevi.diffAsSuccess');
  const autoOpen = !!config.get('comparevi.autoOpenReportOnDiff');
  const showSummary = !!config.get('comparevi.showSummary');
  const passFlags = !!config.get('comparevi.passFlags');
  const showFlagPicker = !!config.get('comparevi.showFlagPicker');
  const knownFlags = getKnownParameters(config);
  let selectedFlags;
  if (showFlagPicker) {
    selectedFlags = await pickFlags(knownFlags, passFlags ? profile.flags : undefined);
  } else if (passFlags) {
    selectedFlags = profile.flags;
  }

  const scriptPath = path.join(repoRoot, 'tools', 'Invoke-LVCompare.ps1');
  const ch = getOutput();

  if (Array.isArray(profile.vis) && profile.vis.length) {
    let comparison;
    try {
      comparison = await prepareCommitSources(profile, config, repoRoot);
    } catch (error) {
      vscode.window.showErrorMessage(`CompareVI prepare failed: ${error.message}`);
      return;
    }
    const { tempDir, base, head, keepTemp } = comparison;
    setStatusBarPending('CompareVI running…');
    const args = buildPwshCommandWrapper(scriptPath, base.tempPath, head.tempPath, labviewExePath, outDir, selectedFlags, diffAsSuccess);
    await recordTelemetry('comparevi.profile.start', {
      profile: profile.name || 'unnamed',
      mode: 'commit',
      origin,
      outputDir: toWorkspaceRelative(outDir)
    });
    const proc = spawnPwsh(args, { cwd: repoRoot });
    const originLabel = origin === 'tree' ? '(from view)' : '(commit sources)';
    ch.appendLine(`[${new Date().toISOString()}] CompareVI profile '${profile.name || 'unnamed'}' started ${originLabel}`);
    proc.stdout.on('data', d => ch.append(String(d)));
    proc.stderr.on('data', d => ch.append(String(d)));
    proc.on('close', async (code) => {
      const capPath = path.join(outDir, 'lvcompare-capture.json');
      const reportPath = path.join(outDir, 'compare-report.html');
      const capInfo = summarizeCapture(capPath);
      const norm = (code === 1 && diffAsSuccess) ? 0 : code;
      const snapshotWritten = await persistLabviewSnapshot(outDir, labviewIniPath);
      await presentSummary({ repoRoot, outDir, capInfo, reportPath, diffAsSuccess, autoOpenReportOnDiff: autoOpen, showSummary, sources: { base, head } });
      await cleanupTempDir(tempDir, keepTemp);
      if (norm !== 0) {
        vscode.window.showErrorMessage(`CompareVI exited with code ${code}`);
      }
      await recordTelemetry('comparevi.profile.complete', {
        profile: profile.name || 'unnamed',
        mode: 'commit',
        origin,
        exitCode: code,
        normalizedExitCode: norm,
        diffDetected: capInfo ? capInfo.exitCode === 1 : undefined,
        outputDir: toWorkspaceRelative(outDir),
        snapshotWritten
      });
    });
    return;
  }

  const baseVi = profile.baseVi || interpolateWorkspaceFolder(config.get('comparevi.paths.baseVi') || '${workspaceFolder}/VI2.vi');
  const headVi = profile.headVi || interpolateWorkspaceFolder(config.get('comparevi.paths.headVi') || '${workspaceFolder}/tmp-commit-236ffab/VI2.vi');
  setStatusBarPending('CompareVI running…');
  const args = buildPwshCommandWrapper(scriptPath, baseVi, headVi, labviewExePath, outDir, selectedFlags, diffAsSuccess);
  await recordTelemetry('comparevi.profile.start', {
    profile: profile.name || 'unnamed',
    mode: 'manual',
    origin,
    outputDir: toWorkspaceRelative(outDir)
  });
  const proc = spawnPwsh(args, { cwd: repoRoot });
  ch.appendLine(`[${new Date().toISOString()}] CompareVI profile '${profile.name || 'unnamed'}' started${origin === 'tree' ? ' (from view)' : ''}`);
  proc.stdout.on('data', d => ch.append(String(d)));
  proc.stderr.on('data', d => ch.append(String(d)));
  proc.on('close', async (code) => {
    const capPath = path.join(outDir, 'lvcompare-capture.json');
    const reportPath = path.join(outDir, 'compare-report.html');
    const capInfo = summarizeCapture(capPath);
    const norm = (code === 1 && diffAsSuccess) ? 0 : code;
    const snapshotWritten = await persistLabviewSnapshot(outDir, labviewIniPath);
    await presentSummary({ repoRoot, outDir, capInfo, reportPath, diffAsSuccess, autoOpenReportOnDiff: autoOpen, showSummary });
    if (norm !== 0) {
      vscode.window.showErrorMessage(`CompareVI exited with code ${code}`);
    }
    await recordTelemetry('comparevi.profile.complete', {
      profile: profile.name || 'unnamed',
      mode: 'manual',
      origin,
      exitCode: code,
      normalizedExitCode: norm,
      diffDetected: capInfo ? capInfo.exitCode === 1 : undefined,
      outputDir: toWorkspaceRelative(outDir),
      snapshotWritten
    });
  });
}

async function createSampleProfiles(targetPath) {
  const sample = {
    profiles: [
      {
        name: "vi2-root-vs-tmp-commit",
        year: "2025",
        bits: "64",
        vis: [
          { "id": "root", "ref": "HEAD", "path": "VI2.vi" },
          { "id": "previous", "ref": "HEAD~1", "path": "VI2.vi" }
        ],
        defaultBase: "previous",
        defaultHead: "root",
        outputDir: "${workspaceFolder}/tests/results/manual-vi2-compare",
        flags: []
      }
    ]
  };
  await fs.promises.mkdir(path.dirname(targetPath), { recursive: true });
  await fs.promises.writeFile(targetPath, JSON.stringify(sample, null, 2), 'utf8');
}

async function openProfilesCommand() {
  const config = vscode.workspace.getConfiguration();
  const profilesPath = resolveProfilesPath(config);
  if (!fs.existsSync(profilesPath)) {
    await createSampleProfiles(profilesPath);
  }
  const doc = await vscode.workspace.openTextDocument(vscode.Uri.file(profilesPath));
  await vscode.window.showTextDocument(doc);
}

async function executeCompare(baseVi, headVi, labviewExePath, outDir, flags) {
  const folders = vscode.workspace.workspaceFolders;
  const repoRoot = folders && folders.length ? folders[0].uri.fsPath : process.cwd();
  const scriptPath = path.join(repoRoot, 'tools', 'Invoke-LVCompare.ps1');
  const pwshArgs = ['-NoLogo', '-NoProfile', '-File', scriptPath, '-BaseVi', baseVi, '-HeadVi', headVi, '-LabVIEWExePath', labviewExePath, '-OutputDir', outDir, '-RenderReport'];
  if (Array.isArray(flags) && flags.length) {
    pwshArgs.push('-Flags', ...flags);
  }
  const terminal = vscode.window.createTerminal({ name: 'CompareVI Manual', shellPath: 'pwsh', shellArgs: pwshArgs });
  terminal.show();
}

class ViCompareViewProvider {
  constructor(context) {
    this.context = context;
    this.view = undefined;
  }

  resolveWebviewView(webviewView) {
    this.view = webviewView;
    const roots = [vscode.Uri.joinPath(this.context.extensionUri, 'vscode', 'comparevi-helper')];
    const folders = vscode.workspace.workspaceFolders;
    if (folders) {
      for (const folder of folders) roots.push(folder.uri);
    }
    webviewView.webview.options = {
      enableScripts: true,
      localResourceRoots: roots
    };
    webviewView.webview.html = this._getHtml(webviewView.webview);
    webviewView.webview.onDidReceiveMessage(async (message) => {
      if (!message) return;
      if (message.type === 'ready') {
        this.refresh();
      } else if (message.type === 'runCompare') {
        const incoming = Array.isArray(message.flags) ? message.flags : [];
        const uniqueFlags = Array.from(new Set(incoming.filter((flag) => typeof flag === 'string' && flag.trim().length)));
        this.view?.webview.postMessage({ type: 'status', status: 'compare-running' });
        const started = await runManualCompareInternal({
          flagsOverride: uniqueFlags,
          forcePassFlags: true,
          promptForLabVIEW: false,
          origin: 'panel'
        });
        this.view?.webview.postMessage({ type: 'status', status: started ? 'compare-submitted' : 'idle' });
      } else if (message.type === 'runTests') {
        const ok = await this._runConfiguredTests();
        this.view?.webview.postMessage({ type: 'status', status: ok ? 'tests-started' : 'idle' });
      } else if (message.type === 'revealOutDir') {
        try {
          const config = vscode.workspace.getConfiguration();
          const outDir = config.get('comparevi.output.dir') || 'tests/results/manual-vi2-compare';
          await vscode.commands.executeCommand('revealFileInOS', vscode.Uri.file(interpolateWorkspaceFolder(outDir)));
        } catch (err) {
          vscode.window.showErrorMessage(`Failed to reveal output directory: ${err instanceof Error ? err.message : String(err)}`);
        }
      } else if (message.type === 'openSettings') {
        try {
          const query = (message.query && String(message.query).trim().length) ? String(message.query).trim() : 'comparevi';
          await vscode.commands.executeCommand('workbench.action.openSettings', query);
        } catch {
          try { await vscode.commands.executeCommand('workbench.action.openSettings'); } catch {}
        }
      } else if (message.type === 'switchProvider') {
        const providerId = String(message.id || '').trim();
        if (!providerId) {
          vscode.window.showWarningMessage('Provider id was empty.');
          return;
        }
        if (!setActiveProvider(providerId)) {
          vscode.window.showWarningMessage(`Provider '${providerId}' is not available.`);
        } else {
          this.refresh();
        }
      } else if (message.type === 'openProviderDocs') {
        const providerId = String(message.id || '').trim() || getActiveProviderId();
        const provider = getProvider(providerId);
        const url = provider?.docsUrl;
        if (url) {
          try {
            await vscode.env.openExternal(vscode.Uri.parse(url));
          } catch (err) {
            vscode.window.showErrorMessage(`Failed to open provider docs: ${err instanceof Error ? err.message : String(err)}`);
          }
        } else {
          vscode.window.showInformationMessage('Documentation is not available for the selected provider yet.');
        }
      } else if (message.type === 'toggleDiffSuccess') {
        try {
          const enable = !!message.value;
          await vscode.workspace.getConfiguration().update('comparevi.diffAsSuccess', enable, vscode.ConfigurationTarget.Workspace);
          this.refresh();
        } catch (err) {
          vscode.window.showErrorMessage(`Failed to update setting: ${err instanceof Error ? err.message : String(err)}`);
        }
      } else if (message.type === 'updateLabVIEW') {
        try {
          const y = String(message.year || '').trim();
          const b = String(message.bits || '').trim();
          if (y) { await vscode.workspace.getConfiguration().update('comparevi.labview.year', y, vscode.ConfigurationTarget.Workspace); }
          if (b) { await vscode.workspace.getConfiguration().update('comparevi.labview.bits', b, vscode.ConfigurationTarget.Workspace); }
          this.refresh();
        } catch (err) {
          vscode.window.showErrorMessage(`Failed to update LabVIEW settings: ${err instanceof Error ? err.message : String(err)}`);
        }
      } else if (message.type === 'openReport') {
        try {
          const config = vscode.workspace.getConfiguration();
          const outDir = interpolateWorkspaceFolder(config.get('comparevi.output.dir') || 'tests/results/manual-vi2-compare');
          const report = path.join(outDir, 'compare-report.html');
          await vscode.env.openExternal(vscode.Uri.file(report));
        } catch (err) {
          vscode.window.showErrorMessage(`Failed to open report: ${err instanceof Error ? err.message : String(err)}`);
        }
      } else if (message.type === 'openCapture') {
        try {
          const config = vscode.workspace.getConfiguration();
          const outDir = interpolateWorkspaceFolder(config.get('comparevi.output.dir') || 'tests/results/manual-vi2-compare');
          const cap = path.join(outDir, 'lvcompare-capture.json');
          const doc = await vscode.workspace.openTextDocument(vscode.Uri.file(cap));
          await vscode.window.showTextDocument(doc);
        } catch (err) {
          vscode.window.showErrorMessage(`Failed to open capture: ${err instanceof Error ? err.message : String(err)}`);
        }
      } else if (message.type === 'compareActive') {
        try {
          await compareActiveWithPrevious();
        } catch (err) {
          vscode.window.showErrorMessage(`Failed to compare active VI: ${err instanceof Error ? err.message : String(err)}`);
        }
      } else if (message.type === 'runCommitCompare') {
        try {
          await runCommitCompareFlow({ baseRef: message.baseRef, headRef: message.headRef, updateSettings: true });
        } catch (err) {
          vscode.window.showErrorMessage(`Failed to run commit compare: ${err instanceof Error ? err.message : String(err)}`);
        }
      } else if (message.type === 'copyCli') {
        try {
          const variant = message.variant || 'current';
          const state = this._getState(this.view?.webview);
          const preview = state.preview || {};
          const text = variant === 'last'
            ? (preview.last || '')
            : ((preview.current && (preview.current.pwsh || preview.current.inline)) || '');
          if (!text) { vscode.window.showInformationMessage('No CLI command available to copy.'); }
          else { await vscode.env.clipboard.writeText(text); vscode.window.showInformationMessage('CLI command copied to clipboard.'); }
        } catch (e) {
          vscode.window.showErrorMessage('Failed to copy CLI: ' + (e && e.message ? e.message : String(e)));
        }
      } else if (message.type === 'openCli') {
        try {
          const state = this._getState(this.view?.webview);
          const inline = state.preview && state.preview.current && state.preview.current.inline;
          if (!inline) { vscode.window.showInformationMessage('No CLI command available to open in terminal.'); }
          else {
            const term = vscode.window.createTerminal({ name: 'CompareVI CLI Preview', shellPath: 'pwsh' });
            term.show();
            term.sendText(inline, true);
          }
        } catch (e) {
          vscode.window.showErrorMessage('Failed to open terminal: ' + (e && e.message ? e.message : String(e)));
        }
      } else if (message.type === 'openImage') {
        try {
          const img = String(message.path || '');
          if (!img) return;
          await vscode.commands.executeCommand('vscode.open', vscode.Uri.file(img));
        } catch (e) {
          vscode.window.showErrorMessage('Failed to open image: ' + (e && e.message ? e.message : String(e)));
        }
      } else if (message.type === 'savePresetPrompt') {
        try {
          const flags = Array.isArray(message.flags) ? Array.from(new Set(message.flags)) : [];
          const name = await vscode.window.showInputBox({ prompt: 'Preset name', placeHolder: 'e.g. No Block Diagram & No FP Pos' });
          if (!name) return;
          const config = vscode.workspace.getConfiguration();
          const map = readPresets(config);
          map[name] = flags;
          await writePresets(map);
          this.refresh();
        } catch (e) {
          vscode.window.showErrorMessage('Failed to save preset: ' + (e && e.message ? e.message : String(e)));
        }
      } else if (message.type === 'deletePreset') {
        try {
          const name = String(message.name || '');
          if (!name) return;
          const config = vscode.workspace.getConfiguration();
          const map = readPresets(config);
          if (Object.prototype.hasOwnProperty.call(map, name)) { delete map[name]; await writePresets(map); }
          this.refresh();
        } catch (e) {
          vscode.window.showErrorMessage('Failed to delete preset: ' + (e && e.message ? e.message : String(e)));
        }
      } else if (message.type === 'setLastFlags') {
        try {
          const flags = Array.isArray(message.flags) ? Array.from(new Set(message.flags)) : [];
          if (workspaceState) { await workspaceState.update('comparevi.lastFlags', flags); }
          this.refresh();
        } catch (e) {
          vscode.window.showErrorMessage('Failed to update last flags: ' + (e && e.message ? e.message : String(e)));
        }
      } else if (message.type === 'updateCommitRefs') {
        try {
          const base = String(message.base || '').trim();
          const head = String(message.head || '').trim();
          const config = vscode.workspace.getConfiguration();
          if (base) { await config.update('comparevi.commitRefs.base', base, vscode.ConfigurationTarget.Workspace); }
          if (head) { await config.update('comparevi.commitRefs.head', head, vscode.ConfigurationTarget.Workspace); }
          this.refresh();
        } catch (e) {
          vscode.window.showErrorMessage('Failed to update commit refs: ' + (e && e.message ? e.message : String(e)));
        }
      } else if (message.type === 'pickBasePath' || message.type === 'pickHeadPath') {
        try {
          const isBase = message.type === 'pickBasePath';
          const selected = await vscode.window.showOpenDialog({
            canSelectFiles: true,
            canSelectFolders: false,
            canSelectMany: false,
            filters: { 'LabVIEW VI': ['vi'] }
          });
          if (selected && selected[0]) {
            const fsPath = selected[0].fsPath;
            const rel = toWorkspaceRelative(fsPath);
            const key = isBase ? 'comparevi.paths.baseVi' : 'comparevi.paths.headVi';
            await vscode.workspace.getConfiguration().update(key, rel, vscode.ConfigurationTarget.Workspace);
            this.refresh();
          }
        } catch (err) {
          vscode.window.showErrorMessage(`Failed to pick path: ${err instanceof Error ? err.message : String(err)}`);
        }
      } else if (message.type === 'runProfile') {
        try {
          const name = (message.name || '').trim();
          const config = vscode.workspace.getConfiguration();
          const profiles = loadProfiles(resolveProfilesPath(config));
          const profile = profiles.find(p => (p.name || '').trim().toLowerCase() === name.toLowerCase());
          if (!profile) {
            vscode.window.showErrorMessage(`Profile not found: ${name}`);
          } else {
            await runProfileWithProfile(profile, config, 'panel');
          }
        } catch (err) {
          vscode.window.showErrorMessage(`Failed to run profile: ${err instanceof Error ? err.message : String(err)}`);
        }
      }
    });
    webviewView.onDidChangeVisibility(() => {
      if (webviewView.visible) {
        this.refresh();
      }
    });
  }

  refresh() {
    if (!this.view) return;
    this.view.webview.postMessage({ type: 'state', payload: this._getState(this.view.webview) });
  }

  async _runConfiguredTests() {
    const config = vscode.workspace.getConfiguration();
    const taskName = (config.get('comparevi.panel.testTask') || '').trim();
    const commandId = (config.get('comparevi.panel.testCommand') || '').trim();

    if (taskName) {
      try {
        const tasks = await vscode.tasks.fetchTasks();
        const target = tasks.find((task) => {
          if (task.name === taskName) return true;
          const def = task.definition || {};
          return def.label === taskName || def.profile === taskName || def.task === taskName;
        });
        if (!target) {
          vscode.window.showErrorMessage(`VI Compare panel: task '${taskName}' not found. Update comparevi.panel.testTask or run the task once so VS Code caches it.`);
          return false;
        }
        await vscode.tasks.executeTask(target);
        return true;
      } catch (error) {
        vscode.window.showErrorMessage(`VI Compare panel failed to launch task '${taskName}': ${error instanceof Error ? error.message : String(error)}`);
        return false;
      }
    }

    if (commandId) {
      try {
        await vscode.commands.executeCommand(commandId);
        return true;
      } catch (error) {
        vscode.window.showErrorMessage(`VI Compare panel failed to execute command '${commandId}': ${error instanceof Error ? error.message : String(error)}`);
        return false;
      }
    }

    vscode.window.showInformationMessage('VI Compare panel: configure comparevi.panel.testTask or comparevi.panel.testCommand to enable Run Tests.');
    return false;
  }

  async show() {
    if (this.view) {
      this.view.show?.(true);
      this.refresh();
      return;
    }
    try {
      await vscode.commands.executeCommand('comparevi.viCompare.focus');
    } catch {
      await vscode.commands.executeCommand('workbench.view.extension.comparevi');
    }
  }

  _getState(webview) {
    const config = vscode.workspace.getConfiguration();
    const baseVi = config.get('comparevi.paths.baseVi') || '${workspaceFolder}/VI2.vi';
    const headVi = config.get('comparevi.paths.headVi') || '${workspaceFolder}/tmp-commit-236ffab/VI2.vi';
    const outDir = config.get('comparevi.output.dir') || 'tests/results/manual-vi2-compare';
    const known = getKnownParameters(config);
    const year = String(config.get('comparevi.labview.year') || '2025');
    const bits = String(config.get('comparevi.labview.bits') || '64');
    const installMap = detectInstalledLabVIEWs();
    const availableYears = Object.keys(installMap).filter((y) => Object.keys(installMap[y] || {}).length);
    const defaultYears = ['2021','2022','2023','2024','2025'];
    let years = availableYears.length ? [...availableYears] : [...defaultYears];
    let bitsOptions = ['64','32'];
    if (installMap[year]) {
      const combos = Object.keys(installMap[year]);
      if (combos.length) bitsOptions = combos;
    }
    if (!years.includes(year)) years.push(year);
    years = Array.from(new Set(years)).sort((a, b) => Number(b) - Number(a));
    const fallbackExe = resolveLabVIEWPath(year, bits);
    const lvExe = installMap[year]?.[bits] || fallbackExe;
    if (!bitsOptions.includes(bits)) bitsOptions = [...bitsOptions, bits];
    bitsOptions = Array.from(new Set(bitsOptions)).sort((a, b) => Number(b) - Number(a));
    const wsBase = interpolateWorkspaceFolder(baseVi);
    const wsHead = interpolateWorkspaceFolder(headVi);
    const wsOut = interpolateWorkspaceFolder(outDir);
    // Capture/report
    const capPath = path.join(wsOut, 'lvcompare-capture.json');
    const reportPath = path.join(wsOut, 'compare-report.html');
    const capInfo = summarizeCapture(capPath);
    const cliArtifacts = detectCliArtifacts(wsOut, capInfo);
    const labviewIni = path.join(path.dirname(lvExe), 'LabVIEW.ini');
    const labviewIniExists = fs.existsSync(labviewIni);
    const gcliPath = config.get('comparevi.providers.gcli.path') || DEFAULT_GCLI_PATH;
    const gcliExists = fs.existsSync(gcliPath);
    const diag = {
      baseExists: fs.existsSync(wsBase),
      headExists: fs.existsSync(wsHead),
      outDirExists: fs.existsSync(wsOut),
      lvExists: fs.existsSync(lvExe),
      lvExePath: lvExe,
      basePath: wsBase,
      headPath: wsHead,
      outDirPath: wsOut,
      capExists: fs.existsSync(capPath),
      capPath,
      reportExists: fs.existsSync(reportPath),
      reportPath,
      cliStdout: cliArtifacts?.lvcliStdout,
      cliStderr: cliArtifacts?.lvcliStderr,
      labviewIniExists,
      labviewIniPath: labviewIni,
      gcliExists,
      gcliPath
    };
    const parameters = [];
    const seen = new Set();
    for (const flag of [...known, ...DEFAULT_PARAMETER_FLAGS]) {
      if (typeof flag !== 'string') continue;
      const trimmed = flag.trim();
      if (!trimmed || seen.has(trimmed)) continue;
      seen.add(trimmed);
      parameters.push(trimmed);
      if (parameters.length >= 4) break;
    }
    const defaults = Array.isArray(config.get('comparevi.flags')) ? config.get('comparevi.flags') : [];
    const last = Array.isArray(workspaceState?.get('comparevi.lastFlags')) ? workspaceState.get('comparevi.lastFlags') : undefined;
    const source = (Array.isArray(last) && last.length) ? last : defaults;
    const selected = (Array.isArray(source) ? source : []).filter((flag) => parameters.includes(flag));
    const testTask = config.get('comparevi.panel.testTask');
    const testCommand = config.get('comparevi.panel.testCommand');
    const testConfigured = !!((typeof testTask === 'string' && testTask.trim().length) || (typeof testCommand === 'string' && testCommand.trim().length));
    let testSummary = '';
    if (typeof testTask === 'string' && testTask.trim().length) {
      testSummary = `Task: ${testTask.trim()}`;
    } else if (typeof testCommand === 'string' && testCommand.trim().length) {
      testSummary = `Command: ${testCommand.trim()}`;
    }
    // Last run result (from capture)
    let last = undefined;
    try {
      const cap = capInfo;
      if (cap && typeof cap.exitCode === 'number') {
        last = { exitCode: cap.exitCode, isDiff: cap.exitCode === 1 };
      }
    } catch {}
    const diffAsSuccess = !!config.get('comparevi.diffAsSuccess');
    // CLI preview (current)
    let preview = { current: { pwsh: '', inline: '' }, last: '' };
    try {
      const repoRoot = getRepoRoot();
      const scriptPath = path.join(repoRoot, 'tools', 'Invoke-LVCompare.ps1');
      const passFlags = !!config.get('comparevi.passFlags');
      const lastFlags = workspaceState && workspaceState.get('comparevi.lastFlags');
      const flagsForPreview = passFlags ? ((Array.isArray(lastFlags) && lastFlags.length) ? lastFlags : (config.get('comparevi.flags') || [])) : undefined;
      const args = buildPwshCommandWrapper(scriptPath, wsBase, wsHead, lvExe, wsOut, flagsForPreview, diffAsSuccess);
      const pwshFull = ['pwsh'].concat(args).join(' ');
      const inline = args[args.length - 1];
      preview.current = { pwsh: pwshFull, inline };
      preview.last = (capInfo && capInfo.command) ? capInfo.command : '';
    } catch {}
    // Profiles list for dropdown
    let profiles = [];
    try {
      profiles = (loadProfiles(resolveProfilesPath(config)) || [])
        .map(p => ({ name: p.name || 'unnamed', summary: `${p.year || '?'}-${p.bits || '?'}` }));
    } catch {}
    // Images summary
    const images = (cliArtifacts && Array.isArray(cliArtifacts.imageFiles))
      ? cliArtifacts.imageFiles.map((p) => {
          const thumb = webview ? webview.asWebviewUri(vscode.Uri.file(p)).toString() : undefined;
          return { path: p, name: path.basename(p), thumbnail: thumb };
        })
      : [];
    const presetsMap = readPresets(config);
    const presets = Object.entries(presetsMap)
      .map(([name, flags]) => ({ name, flags: Array.isArray(flags) ? flags : [], count: Array.isArray(flags) ? flags.length : 0 }))
      .sort((a, b) => a.name.localeCompare(b.name));
    const commitRefs = {
      base: String(config.get('comparevi.commitRefs.base') || 'HEAD~1'),
      head: String(config.get('comparevi.commitRefs.head') || 'HEAD')
    };
    const availMap = {};
    Object.entries(installMap).forEach(([y, combos]) => {
      const keys = Object.keys(combos || {});
      if (keys.length) availMap[y] = keys;
    });
    const providersMeta = listProviderMetadata().map((meta) => ({
      id: meta.id,
      displayName: meta.displayName,
      docsUrl: getProvider(meta.id)?.docsUrl || null,
      disabled: !!meta.disabled,
      status: meta.status || null
    }));
    const activeId = getActiveProviderId() || 'comparevi';
    return {
      baseVi,
      headVi,
      outDir,
      parameters,
      selected,
      testConfigured,
      testSummary,
      diag,
      last,
      diffAsSuccess,
      profiles,
      year,
      bits,
      years,
      bitsOptions,
      preview,
      images,
      presets,
      commitRefs,
      labviewAvailability: availMap,
      providers: providersMeta,
      activeProviderId: activeId
    };
  }

  _getHtml(webview) {
    const nonce = getNonce();
  const styles = `
      body { font-family: var(--vscode-font-family); padding: 12px; }
      h2 { font-size: 16px; margin-bottom: 8px; }
      .paths { font-size: 11px; color: var(--vscode-descriptionForeground); margin-bottom: 12px; }
      .paths div { margin-bottom: 2px; }
      .lv-config { margin: 6px 0 10px 0; font-size: 12px; }
      .lv-config select { margin-left: 6px; margin-right: 6px; }
      .parameter-list { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 6px; margin-bottom: 12px; }
      label { display: flex; align-items: center; gap: 6px; font-size: 13px; }
      button { background: var(--vscode-button-background); color: var(--vscode-button-foreground); border: none; padding: 6px 12px; border-radius: 2px; cursor: pointer; }
      button:hover { background: var(--vscode-button-hoverBackground); }
      button[disabled] { opacity: 0.6; cursor: default; }
      .status { margin-top: 10px; font-size: 12px; color: var(--vscode-descriptionForeground); min-height: 14px; }
      .actions { display: flex; gap: 8px; margin-bottom: 6px; }
      .hint { font-size: 11px; color: var(--vscode-descriptionForeground); }
      .diags { margin-top: 10px; font-size: 12px; }
      .diag-item { display: flex; align-items: center; gap: 6px; margin: 2px 0; }
      .ok { color: var(--vscode-terminal-ansiGreen); }
      .bad { color: var(--vscode-terminal-ansiRed); }
      .result { margin-top: 8px; font-size: 12px; }
      .chip { display: inline-block; padding: 2px 6px; border-radius: 10px; color: white; font-size: 11px; }
      .chip.diff { background: #d97706; }
      .chip.nodiff { background: #16a34a; }
      .chip.error { background: #dc2626; }
      .linkbtn { background: transparent; border: none; color: var(--vscode-textLink-foreground); cursor: pointer; padding: 0 4px; font-size: 11px; }
      .linkbtn:hover { text-decoration: underline; }
      .commit-refs input { width: 120px; margin-left: 4px; margin-right: 8px; }
      .commit-refs button { margin-left: 6px; }
      .images { display: flex; flex-wrap: wrap; gap: 12px; margin-top: 4px; }
      .image-item { width: 120px; text-align: center; font-size: 11px; }
      .image-item img { max-width: 120px; border: 1px solid var(--vscode-widget-border, #666); border-radius: 2px; cursor: pointer; margin-bottom: 4px; }
    `;
    return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; script-src 'nonce-${nonce}';">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>CompareVI Panel</title>
  <style>${styles}</style>
</head>
<body>
  <div class="header" style="display:flex; align-items:center; gap:8px;">
    <h2 style="flex:1; margin:0;">Providers</h2>
    <select id="providerSelect"></select>
    <button id="openProviderDocs" type="button" style="margin-left:4px;">Docs</button>
  </div>
  <div id="providerStatus" class="hint" style="margin-top:4px;"></div>
  <h2 style="margin-top:12px;">VI Compare Parameters</h2>
  <div class="paths">
    <div><strong>Base:</strong> <span id="baseVi"></span> <button id="editBase" class="linkbtn" type="button">Edit</button> <button id="pickBase" class="linkbtn" type="button">Pick…</button></div>
    <div><strong>Head:</strong> <span id="headVi"></span> <button id="editHead" class="linkbtn" type="button">Edit</button> <button id="pickHead" class="linkbtn" type="button">Pick…</button></div>
    <div><strong>Output:</strong> <span id="outDir"></span></div>
  </div>
  <div style="margin: 6px 0;">
    <strong>Run Profile:</strong> <select id="profileSelect"></select>
    <button id="runProfileBtn" type="button">Run</button>
  </div>
  <div style="margin: 6px 0;">
    <strong>Presets:</strong> <select id="presetSelect"></select>
    <button id="applyPresetBtn" type="button">Apply</button>
    <button id="savePresetBtn" type="button">Save As…</button>
    <button id="deletePresetBtn" type="button">Delete</button>
  </div>
  <div class="commit-refs" style="margin: 6px 0;">
    <strong>Commit Compare:</strong>
    <label for="baseRef">Base</label>
    <input id="baseRef" type="text" />
    <label for="headRef">Head</label>
    <input id="headRef" type="text" />
    <button id="swapRefsBtn" type="button">Swap</button>
  </div>
  <div class="parameter-list" id="parameterList"></div>
  <div class="lv-config">
    <strong>LabVIEW:</strong>
    <label for="yearSelect">Year</label>
    <select id="yearSelect"></select>
    <label for="bitsSelect">Bits</label>
    <select id="bitsSelect"></select>
  </div>
  <div class="actions">
    <button id="runBtn" type="button">Compare</button>
    <button id="compareActiveBtn" type="button">Compare Active (vs prev)</button>
    <button id="runCommitBtn" type="button">Run Commit Compare</button>
    <button id="testBtn" type="button">Run Tests</button>
    <button id="revealBtn" type="button">Reveal Output</button>
    <button id="editBtn" type="button">Edit Settings</button>
    <button id="openReportBtn" type="button">Open Report</button>
    <button id="openCaptureBtn" type="button">Open Capture</button>
  </div>
  <div class="hint" id="testHint"></div>
  <div class="diags" id="diags">
    <div class="diag-item"><span id="diagBaseIcon">●</span><span id="diagBaseText"></span></div>
    <div class="diag-item"><span id="diagHeadIcon">●</span><span id="diagHeadText"></span></div>
    <div class="diag-item"><span id="diagLvIcon">●</span><span id="diagLvText"></span></div>
    <div class="diag-item"><span id="diagOutIcon">●</span><span id="diagOutText"></span></div>
    <div class="diag-item"><span id="diagIniIcon">●</span><span id="diagIniText"></span></div>
    <div class="diag-item"><span id="diagGcliIcon">●</span><span id="diagGcliText"></span></div>
  </div>
  <div class="result"><strong>Last Result:</strong> <span id="resChip"></span> <label style="margin-left:10px;"><input type="checkbox" id="diffAsSuccess"> Treat diff as success</label></div>
  <div style="margin-top:8px;">
    <strong>CLI Preview:</strong>
    <div style="margin-top:4px;">
      <code id="cliInline" style="display:block; white-space:pre; font-size:11px;">(no command)</code>
      <button id="copyCliBtn" type="button">Copy (Current)</button>
      <button id="openCliBtn" type="button">Open in Terminal</button>
      <button id="copyCliLastBtn" type="button">Copy Last</button>
    </div>
  </div>
  <div style="margin-top:8px;">
    <strong>CLI Images:</strong>
    <div id="images" class="images"></div>
  </div>
  <div class="status" id="status"></div>
  <script nonce="${nonce}">
    const vscode = acquireVsCodeApi();
    const parameterListEl = document.getElementById('parameterList');
    const statusEl = document.getElementById('status');
    const providerSelect = document.getElementById('providerSelect');
    const providerDocsBtn = document.getElementById('openProviderDocs');
    const providerStatusEl = document.getElementById('providerStatus');
    const baseEl = document.getElementById('baseVi');
    const headEl = document.getElementById('headVi');
    const outEl = document.getElementById('outDir');
    const runBtn = document.getElementById('runBtn');
    const testBtn = document.getElementById('testBtn');
    const revealBtn = document.getElementById('revealBtn');
    const editBtn = document.getElementById('editBtn');
    const compareActiveBtn = document.getElementById('compareActiveBtn');
    const runCommitBtn = document.getElementById('runCommitBtn');
    const openReportBtn = document.getElementById('openReportBtn');
    const openCaptureBtn = document.getElementById('openCaptureBtn');
    const yearSelect = document.getElementById('yearSelect');
    const bitsSelect = document.getElementById('bitsSelect');
    const editBase = document.getElementById('editBase');
    const pickBase = document.getElementById('pickBase');
    const editHead = document.getElementById('editHead');
    const pickHead = document.getElementById('pickHead');
    const profileSelect = document.getElementById('profileSelect');
    const runProfileBtn = document.getElementById('runProfileBtn');
    const presetSelect = document.getElementById('presetSelect');
    const applyPresetBtn = document.getElementById('applyPresetBtn');
    const savePresetBtn = document.getElementById('savePresetBtn');
    const deletePresetBtn = document.getElementById('deletePresetBtn');
    const baseRefInput = document.getElementById('baseRef');
    const headRefInput = document.getElementById('headRef');
    const swapRefsBtn = document.getElementById('swapRefsBtn');
    const testHintEl = document.getElementById('testHint');
    const diagBaseIcon = document.getElementById('diagBaseIcon');
    const diagHeadIcon = document.getElementById('diagHeadIcon');
    const diagLvIcon = document.getElementById('diagLvIcon');
    const diagOutIcon = document.getElementById('diagOutIcon');
    const diagBaseText = document.getElementById('diagBaseText');
    const diagHeadText = document.getElementById('diagHeadText');
    const diagLvText = document.getElementById('diagLvText');
    const diagOutText = document.getElementById('diagOutText');
    const diagIniIcon = document.getElementById('diagIniIcon');
    const diagIniText = document.getElementById('diagIniText');
    const diagGcliIcon = document.getElementById('diagGcliIcon');
    const diagGcliText = document.getElementById('diagGcliText');
    const resChip = document.getElementById('resChip');
    const cliInline = document.getElementById('cliInline');
    const copyCliBtn = document.getElementById('copyCliBtn');
    const openCliBtn = document.getElementById('openCliBtn');
    const copyCliLastBtn = document.getElementById('copyCliLastBtn');
    const imagesEl = document.getElementById('images');
    const diffAsSuccess = document.getElementById('diffAsSuccess');
    let parameters = [];
    let selected = new Set();
    let providerCache = [];
    let activeProviderState = 'comparevi';
    window.__presets = [];
    copyCliBtn.disabled = true;
    openCliBtn.disabled = true;
    copyCliLastBtn.disabled = true;
    applyPresetBtn.disabled = true;
    deletePresetBtn.disabled = true;
    presetSelect.disabled = true;

    function renderParameters() {
      parameterListEl.innerHTML = '';
      if (!parameters.length) {
        const empty = document.createElement('div');
        empty.textContent = 'No parameters configured.';
        parameterListEl.appendChild(empty);
        return;
      }
      const columns = parameters.length >= 4 ? 2 : 1;
      parameterListEl.style.gridTemplateColumns = 'repeat(' + columns + ', minmax(0, 1fr))';
      for (const flag of parameters) {
        const wrapper = document.createElement('label');
        const cb = document.createElement('input');
        cb.type = 'checkbox';
        cb.value = flag;
        cb.checked = selected.has(flag);
        cb.addEventListener('change', () => {
          if (cb.checked) selected.add(flag);
          else selected.delete(flag);
        });
        const span = document.createElement('span');
        span.textContent = flag;
        wrapper.appendChild(cb);
        wrapper.appendChild(span);
        parameterListEl.appendChild(wrapper);
      }
    }

    function setStatus(message) {
      statusEl.textContent = message || '';
    }

    runBtn.addEventListener('click', () => {
      setStatus('Starting compare…');
      vscode.postMessage({ type: 'runCompare', flags: Array.from(selected) });
    });

    compareActiveBtn.addEventListener('click', () => {
      setStatus('Starting active vs previous…');
      vscode.postMessage({ type: 'compareActive' });
    });

    runCommitBtn.addEventListener('click', () => {
      setStatus('Starting commit compare…');
      vscode.postMessage({ type: 'runCommitCompare', baseRef: (baseRefInput.value || '').trim(), headRef: (headRefInput.value || '').trim() });
    });

    testBtn.addEventListener('click', () => {
      if (testBtn.disabled) { return; }
      setStatus('Dispatching tests…');
      vscode.postMessage({ type: 'runTests' });
    });

    revealBtn.addEventListener('click', () => {
      if (revealBtn.disabled) { return; }
      vscode.postMessage({ type: 'revealOutDir' });
    });

    editBtn.addEventListener('click', () => {
      vscode.postMessage({ type: 'openSettings' });
    });

    openReportBtn.addEventListener('click', () => {
      if (openReportBtn.disabled) return;
      vscode.postMessage({ type: 'openReport' });
    });
    openCaptureBtn.addEventListener('click', () => {
      if (openCaptureBtn.disabled) return;
      vscode.postMessage({ type: 'openCapture' });
    });

    editBase.addEventListener('click', () => {
      vscode.postMessage({ type: 'openSettings', query: 'comparevi.paths.baseVi' });
    });
    editHead.addEventListener('click', () => {
      vscode.postMessage({ type: 'openSettings', query: 'comparevi.paths.headVi' });
    });
    pickBase.addEventListener('click', () => {
      vscode.postMessage({ type: 'pickBasePath' });
    });
    pickHead.addEventListener('click', () => {
      vscode.postMessage({ type: 'pickHeadPath' });
    });

  function populateProfiles(list) {
      profileSelect.innerHTML = '';
      if (!Array.isArray(list) || list.length === 0) {
        profileSelect.disabled = true;
        runProfileBtn.disabled = true;
        return;
      }
      profileSelect.disabled = false;
      runProfileBtn.disabled = false;
      for (const p of list) {
        const opt = document.createElement('option');
        opt.value = p.name;
        opt.textContent = p.summary ? `${p.name} (${p.summary})` : p.name;
        profileSelect.appendChild(opt);
      }
    }

    function populatePresets(list) {
      presetSelect.innerHTML = '';
      if (!Array.isArray(list) || list.length === 0) {
        presetSelect.disabled = true;
        applyPresetBtn.disabled = true;
        deletePresetBtn.disabled = true;
        return;
      }
      presetSelect.disabled = false;
      applyPresetBtn.disabled = false;
      deletePresetBtn.disabled = false;
      for (const preset of list) {
        const opt = document.createElement('option');
        opt.value = preset.name;
        opt.textContent = preset.count ? `${preset.name} (${preset.count})` : preset.name;
        presetSelect.appendChild(opt);
      }
    }

    function populateCommitRefs(refs) {
      const base = refs && refs.base ? refs.base : 'HEAD~1';
      const head = refs && refs.head ? refs.head : 'HEAD';
      baseRefInput.value = base;
      headRefInput.value = head;
    }

    function populateLabVIEW(payload) {
      const years = payload.years || [];
      const bitsOpts = payload.bitsOptions || [];
      const availability = payload.labviewAvailability || {};
      const curYear = payload.year || '';
      const curBits = payload.bits || '';
      const setOptions = (select, opts, current, format) => {
        select.innerHTML = '';
        opts.forEach((val) => {
          const opt = document.createElement('option');
          opt.value = val;
          opt.textContent = format ? format(val) : val;
          if (val === current) opt.selected = true;
          select.appendChild(opt);
        });
      };
      const formatYear = (y) => (availability[y] ? `${y} (installed)` : y);
      const formatBits = (b) => ((availability[curYear] || []).includes(b) ? `${b} (installed)` : b);
      setOptions(yearSelect, years, curYear, formatYear);
      setOptions(bitsSelect, bitsOpts, curBits, formatBits);
    }

    runProfileBtn.addEventListener('click', () => {
      const name = profileSelect.value;
      if (!name) return;
      vscode.postMessage({ type: 'runProfile', name });
    });

    providerSelect.addEventListener('change', () => {
      const providerId = providerSelect.value;
      updateProviderStatus(providerId, providerCache);
      vscode.postMessage({ type: 'switchProvider', id: providerId });
    });

    providerDocsBtn.addEventListener('click', () => {
      vscode.postMessage({ type: 'openProviderDocs', id: providerSelect.value });
    });

    applyPresetBtn.addEventListener('click', () => {
      const name = presetSelect.value;
      if (!name) return;
      const preset = (window.__presets || []).find((p) => p.name === name);
      if (!preset) return;
      selected = new Set(preset.flags || []);
      renderParameters();
      vscode.postMessage({ type: 'setLastFlags', flags: Array.from(selected) });
    });

    savePresetBtn.addEventListener('click', () => {
      vscode.postMessage({ type: 'savePresetPrompt', flags: Array.from(selected) });
    });

    deletePresetBtn.addEventListener('click', () => {
      const name = presetSelect.value;
      if (!name) return;
      vscode.postMessage({ type: 'deletePreset', name });
    });

    const emitCommitRefs = () => {
      vscode.postMessage({ type: 'updateCommitRefs', base: (baseRefInput.value || '').trim(), head: (headRefInput.value || '').trim() });
    };

    baseRefInput.addEventListener('change', emitCommitRefs);
    headRefInput.addEventListener('change', emitCommitRefs);
    swapRefsBtn.addEventListener('click', () => {
      const base = baseRefInput.value;
      baseRefInput.value = headRefInput.value;
      headRefInput.value = base;
      emitCommitRefs();
    });

    function renderDiag(ok, iconEl, textEl, label, extra) {
      const okClass = ok ? 'ok' : 'bad';
      iconEl.className = okClass;
      iconEl.textContent = ok ? '✔' : '✖';
      textEl.textContent = label + (extra ? ' ' + extra : '');
      textEl.className = okClass;
    }

    window.addEventListener('message', event => {
      const { type, payload, status } = event.data || {};
      if (type === 'state' && payload) {
        parameters = payload.parameters || [];
        selected = new Set(payload.selected || []);
        baseEl.textContent = payload.baseVi || '—';
        headEl.textContent = payload.headVi || '—';
        outEl.textContent = payload.outDir || '—';
        renderParameters();
        populateLabVIEW(payload);
        populateProfiles(payload.profiles || []);
        const canRun = populateProviders(payload.providers || [], payload.activeProviderId);
        window.__presets = payload.presets || [];
        populatePresets(window.__presets);
        populateCommitRefs(payload.commitRefs || {});
        testBtn.disabled = !payload.testConfigured || !canRun;
        runBtn.disabled = !canRun;
        compareActiveBtn.disabled = !canRun;
        runCommitBtn.disabled = !canRun;
        if (!canRun) {
          runProfileBtn.disabled = true;
        }
        testHintEl.textContent = payload.testSummary || (payload.testConfigured ? '' : 'Configure comparevi.panel.testTask or comparevi.panel.testCommand to enable Run Tests.');
        const d = payload.diag || {};
        renderDiag(!!d.baseExists, diagBaseIcon, diagBaseText, 'Base VI exists', d.basePath ? '(' + d.basePath + ')' : '');
        renderDiag(!!d.headExists, diagHeadIcon, diagHeadText, 'Head VI exists', d.headPath ? '(' + d.headPath + ')' : '');
        renderDiag(!!d.lvExists, diagLvIcon, diagLvText, 'LabVIEW.exe', d.lvExePath ? '(' + d.lvExePath + ')' : '');
        renderDiag(!!d.outDirExists, diagOutIcon, diagOutText, 'Output directory exists', d.outDirPath ? '(' + d.outDirPath + ')' : '');
        renderDiag(!!d.labviewIniExists, diagIniIcon, diagIniText, 'LabVIEW.ini present', d.labviewIniPath ? '(' + d.labviewIniPath + ')' : '');
        renderDiag(!!d.gcliExists, diagGcliIcon, diagGcliText, 'g-cli executable', d.gcliPath ? '(' + d.gcliPath + ')' : '');
        const allowArtifacts = !!canRun;
        revealBtn.disabled = !allowArtifacts || !d.outDirExists;
        openReportBtn.disabled = !allowArtifacts || !d.reportExists;
        openCaptureBtn.disabled = !allowArtifacts || !d.capExists;
        if (activeProviderState === 'comparevi') {
          if (!d.labviewIniExists) {
            providerStatusEl.textContent = `LabVIEW.ini missing at ${d.labviewIniPath || 'expected location'}.`;
            providerStatusEl.className = 'hint bad';
          } else if (!providerStatusEl.className.includes('bad')) {
            providerStatusEl.textContent = 'CompareVI active.';
            providerStatusEl.className = 'hint ok';
          }
        }
        // Last result chip
        const last = payload.last || {};
        let label = '—';
        let cls = 'chip';
        if (typeof last.exitCode === 'number') {
          if (last.exitCode === 0) { label = 'No Diff'; cls += ' nodiff'; }
          else if (last.exitCode === 1) { label = 'Diff'; cls += ' diff'; }
          else { label = 'Error (' + last.exitCode + ')'; cls += ' error'; }
        }
        resChip.className = cls;
        resChip.textContent = label;
        // CLI preview
        const inlineCommand = (payload.preview && payload.preview.current && payload.preview.current.inline) || '';
        cliInline.textContent = inlineCommand || '(no command)';
        const hasCurrentCli = !!inlineCommand;
        copyCliBtn.disabled = !hasCurrentCli || !canRun;
        openCliBtn.disabled = !hasCurrentCli || !canRun;
        copyCliLastBtn.disabled = !(payload.preview && payload.preview.last) || !canRun;
        // Toggle for diff-as-success
        diffAsSuccess.checked = !!payload.diffAsSuccess;
        diffAsSuccess.onchange = () => {
          vscode.postMessage({ type: 'toggleDiffSuccess', value: diffAsSuccess.checked });
        };
        // Images
        renderImages(payload.images || []);
        setStatus('');
      } else if (type === 'status') {
        if (status === 'compare-running') {
          setStatus('Compare launched. Check output channel for progress.');
        } else if (status === 'compare-submitted') {
          setStatus('Compare launched. Report updates when finished.');
        } else if (status === 'tests-started') {
          setStatus('Tests command dispatched.');
        } else {
          setStatus('');
        }
      }
    });

    vscode.postMessage({ type: 'ready' });
  </script>
</body>
</html>`;
  }
}

class CompareViTaskProvider {
  constructor() {}
  provideTasks() {
    const config = vscode.workspace.getConfiguration();
    const profiles = loadProfiles(resolveProfilesPath(config));
    const tasks = [];
    const folders = vscode.workspace.workspaceFolders;
    const repoRoot = folders && folders.length ? folders[0].uri.fsPath : process.cwd();
    const passFlags = !!config.get('comparevi.passFlags');
    const lastFlags = workspaceState?.get('comparevi.lastFlags');
    for (const p of profiles) {
      const expanded = expandProfile(p);
      if (Array.isArray(p.vis) && p.vis.length) {
        // Commit-based profiles require interactive resolution; skip task generation for now.
        continue;
      }
      const year = String(expanded.year || config.get('comparevi.labview.year') || '2025');
      const bits = String(expanded.bits || config.get('comparevi.labview.bits') || '64');
      const labviewExePath = expanded.labviewExePath || resolveLabVIEWPath(year, bits);

      const scriptPath = path.join(repoRoot, 'tools', 'Invoke-LVCompare.ps1');
      const diffAsSuccess = !!(vscode.workspace.getConfiguration().get('comparevi.diffAsSuccess'));
      const baseVi = expanded.baseVi || path.join(repoRoot,'VI2.vi');
      const headVi = expanded.headVi || path.join(repoRoot,'tmp-commit-236ffab','VI2.vi');
      const outDir = expanded.outputDir || path.join(repoRoot,'tests','results','manual-vi2-compare');
      const flagsForTask = passFlags ? ((Array.isArray(lastFlags) && lastFlags.length) ? lastFlags : expanded.flags) : undefined;
      const cmdArgs = buildPwshCommandWrapper(scriptPath, baseVi, headVi, labviewExePath, outDir, flagsForTask, diffAsSuccess);
      const def = { type: 'comparevi', profile: p.name || 'unnamed' };
      const exec = new vscode.ProcessExecution('pwsh', cmdArgs, { cwd: repoRoot });
      const task = new vscode.Task(def, vscode.TaskScope.Workspace, `CompareVI: ${p.name || 'unnamed'}`, 'comparevi', exec, []);
      tasks.push(task);
    }
    return tasks;
  }
  resolveTask(task) { return task; }
}

function activateCompareVI(context) {
  workspaceState = context.workspaceState;
  context.subscriptions.push(vscode.commands.registerCommand('comparevi.toggleDiffSuccess', async () => {
    const config = vscode.workspace.getConfiguration();
    const current = !!config.get('comparevi.diffAsSuccess');
    await config.update('comparevi.diffAsSuccess', !current, vscode.ConfigurationTarget.Workspace);
  }));
  applyStatusBarConfig(vscode.workspace.getConfiguration());
  context.subscriptions.push(getStatusItem());
  viCompareProvider = new ViCompareViewProvider(context);
  context.subscriptions.push(vscode.window.registerWebviewViewProvider('comparevi.viCompare', viCompareProvider));
  context.subscriptions.push(vscode.commands.registerCommand('comparevi.runManualCompare', runManualCompare));
  context.subscriptions.push(vscode.commands.registerCommand('comparevi.runProfile', runProfileCommand));
  context.subscriptions.push(vscode.commands.registerCommand('comparevi.compareActiveWithPrevious', compareActiveWithPrevious));
  context.subscriptions.push(vscode.commands.registerCommand('comparevi.openProfiles', openProfilesCommand));
  context.subscriptions.push(vscode.commands.registerCommand('comparevi.openViCompare', () => viCompareProvider?.show()));
  context.subscriptions.push(vscode.tasks.registerTaskProvider('comparevi', new CompareViTaskProvider()));
  context.subscriptions.push(vscode.workspace.onDidChangeConfiguration((event) => {
    const config = vscode.workspace.getConfiguration();
    if (event.affectsConfiguration('comparevi.statusBar') || event.affectsConfiguration('comparevi.diffAsSuccess')) {
      applyStatusBarConfig(config);
    }
    if (!viCompareProvider) return;
    if (
      event.affectsConfiguration('comparevi.knownFlags') ||
      event.affectsConfiguration('comparevi.flags') ||
      event.affectsConfiguration('comparevi.paths') ||
      event.affectsConfiguration('comparevi.output.dir') ||
      event.affectsConfiguration('comparevi.panel.testTask') ||
      event.affectsConfiguration('comparevi.panel.testCommand') ||
      event.affectsConfiguration('comparevi.diffAsSuccess') ||
      event.affectsConfiguration('comparevi.commitRefs.base') ||
      event.affectsConfiguration('comparevi.commitRefs.head') ||
      event.affectsConfiguration('comparevi.presets') ||
      event.affectsConfiguration('comparevi.providers.gcli.path')
    ) {
      viCompareProvider.refresh();
    }
  }));

  // Tree View: Profiles
  const profilesProvider = new CompareViProfilesProvider();
  context.subscriptions.push(vscode.window.registerTreeDataProvider('comparevi.profiles', profilesProvider));
  context.subscriptions.push(vscode.commands.registerCommand('comparevi.refreshProfiles', () => profilesProvider.refresh()));
  context.subscriptions.push(vscode.commands.registerCommand('comparevi.runProfileItem', (node) => profilesProvider.runProfileFromNode(node)));
  context.subscriptions.push(vscode.commands.registerCommand('comparevi.openReportForProfile', (node) => profilesProvider.openReportFromNode(node)));
  context.subscriptions.push(vscode.commands.registerCommand('comparevi.openCaptureForProfile', (node) => profilesProvider.openCaptureFromNode(node)));
  context.subscriptions.push(vscode.commands.registerCommand('comparevi.revealOutputForProfile', (node) => profilesProvider.revealOutputFromNode(node)));
}

function deactivateCompareVI() {
  viCompareProvider = undefined;
  if (statusItem) {
    statusItem.dispose();
    statusItem = undefined;
  }
}

function createCompareVIProvider() {
  return {
    id: 'comparevi',
    displayName: 'CompareVI',
    docsUrl: 'https://github.com/LabVIEW-Community-CI-CD/compare-vi-cli-action/blob/develop/README.md#comparevi-helper',
    activate(context) {
      activateCompareVI(context);
    },
    deactivate() {
      deactivateCompareVI();
    },
    getState(webview) {
      return viCompareProvider?._getState(webview);
    }
  };
}

function activate(context) {
  compareVIProviderRegistration = createCompareVIProvider();
  gcliProviderRegistration = createGcliProvider();

  registerProvider(compareVIProviderRegistration);
  registerProvider(gcliProviderRegistration);

  context.subscriptions.push({
    dispose: () => unregisterProvider(compareVIProviderRegistration?.id || 'comparevi')
  });
  context.subscriptions.push({
    dispose: () => unregisterProvider(gcliProviderRegistration?.id || 'gcli')
  });

  compareVIProviderRegistration.activate(context);
  gcliProviderRegistration.activate?.(context);
  setActiveProvider(compareVIProviderRegistration.id);

  const providerWatcher = onDidChangeActiveProvider(() => {
    try {
      viCompareProvider?.refresh?.();
    } catch { /* noop */ }
  });
  context.subscriptions.push(providerWatcher);
}

function deactivate() {
  try {
    compareVIProviderRegistration?.deactivate?.();
    gcliProviderRegistration?.deactivate?.();
  } finally {
    if (compareVIProviderRegistration) {
      unregisterProvider(compareVIProviderRegistration.id);
      compareVIProviderRegistration = undefined;
    }
    if (gcliProviderRegistration) {
      unregisterProvider(gcliProviderRegistration.id);
      gcliProviderRegistration = undefined;
    }
  }
}

module.exports = {
  activate,
  deactivate,
  __testing: {
    setSpawnOverride,
    resetSpawnOverride,
    runCommitCompare: (options) => runCommitCompareFlow(options || {}),
    getPanelState: () => compareVIProviderRegistration?.getState?.(),
    getStatusItem,
    setStatusBarResult,
    setStatusBarPending,
    listProviders,
    getProvider,
    setActiveProvider,
    getActiveProviderId
  }
};

// ----- Tree view implementation -----

class CompareViProfilesProvider {
  constructor() {
    this._emitter = new vscode.EventEmitter();
    this.onDidChangeTreeData = this._emitter.event;
    // Watch for profiles file changes
    const config = vscode.workspace.getConfiguration();
    const profilesPath = resolveProfilesPath(config);
    try {
      const watcher = vscode.workspace.createFileSystemWatcher(new vscode.RelativePattern(vscode.workspace.workspaceFolders?.[0] ?? vscode.workspace, profilesPath));
      watcher.onDidChange(() => this.refresh());
      watcher.onDidCreate(() => this.refresh());
      watcher.onDidDelete(() => this.refresh());
    } catch {}
  }

    function updateProviderStatus(activeId, providersList) {
      providerCache = Array.isArray(providersList) ? providersList : [];
      const fallbackId = providerCache[0]?.id;
      activeProviderState = activeId || fallbackId || 'comparevi';
      const provider = providerCache.find((p) => p.id === activeProviderState);
      const status = provider?.status || {};
      const disabled = !!provider?.disabled;
      const ok = !disabled && (typeof status.ok === 'boolean' ? status.ok : true);
      const name = provider ? (provider.displayName || provider.id) : 'No provider';
      let message = status.message || '';
      if (!message) {
        if (!provider) message = 'No providers registered.';
        else if (provider.id === 'comparevi') message = `${name} active.`;
        else message = `${name} active. Controls disabled until CompareVI is selected.`;
      }
      providerStatusEl.textContent = message;
      providerStatusEl.className = 'hint ' + (ok ? 'ok' : 'bad');
      providerDocsBtn.disabled = !(provider && provider.docsUrl);
      if (providerSelect.value !== activeProviderState) {
        providerSelect.value = activeProviderState;
      }
      return ok && activeProviderState === 'comparevi';
    }

    function populateProviders(list, activeId) {
      providerSelect.innerHTML = '';
      providerCache = Array.isArray(list) ? list : [];
      if (!providerCache.length) {
        const opt = document.createElement('option');
        opt.value = '';
        opt.textContent = 'No providers registered';
        providerSelect.appendChild(opt);
        providerSelect.disabled = true;
        providerDocsBtn.disabled = true;
        providerStatusEl.textContent = 'No providers registered. Configure providers to continue.';
        providerStatusEl.className = 'hint bad';
        activeProviderState = 'comparevi';
        return false;
      }
      providerSelect.disabled = false;
      providerDocsBtn.disabled = false;
      providerCache.forEach((provider) => {
        const opt = document.createElement('option');
        opt.value = provider.id;
        opt.textContent = provider.displayName || provider.id;
        if (provider.disabled) opt.textContent += ' (unavailable)';
        if (provider.id === activeId) opt.selected = true;
        providerSelect.appendChild(opt);
      });
      return updateProviderStatus(activeId, providerCache);
    }

  refresh() { this._emitter.fire(); }

  getTreeItem(element) { return element; }

  async getChildren(element) {
    if (element) return [];
    const config = vscode.workspace.getConfiguration();
    const profiles = loadProfiles(resolveProfilesPath(config));
    const items = [];
    for (const p of profiles) { items.push(this._toItem(p)); }
    return items;
  }

  _toItem(profile) {
    const item = new vscode.TreeItem(profile.name || 'unnamed');
    item.description = `${profile.year || '?'}-${profile.bits || '?'}`;
    item.tooltip = `Profile: ${profile.name || 'unnamed'}\nYear: ${profile.year || '?'}\nBits: ${profile.bits || '?'}\nOut: ${profile.outputDir || ''}`;
    item.contextValue = 'comparevi.profile';
    item.command = { command: 'comparevi.runProfileItem', title: 'Run', arguments: [item] };

    // Status icon from capture
    try {
      const expanded = expandProfile(profile);
      const capPath = path.join(expanded.outputDir || '', 'lvcompare-capture.json');
      if (capPath && fs.existsSync(capPath)) {
        const capInfo = summarizeCapture(capPath);
        if (capInfo && typeof capInfo.exitCode === 'number') {
          if (capInfo.exitCode === 0) item.iconPath = new vscode.ThemeIcon('check');
          else if (capInfo.exitCode === 1) item.iconPath = new vscode.ThemeIcon('diff');
          else item.iconPath = new vscode.ThemeIcon('warning');
        }
      } else {
        item.iconPath = new vscode.ThemeIcon('circle-outline');
      }
    } catch {
      item.iconPath = new vscode.ThemeIcon('circle-outline');
    }

    // Attach data for handlers
    item._profile = profile;
    return item;
  }

  async runProfileFromNode(node) {
    const profile = node?._profile;
    if (!profile) return;
    const config = vscode.workspace.getConfiguration();
    await runProfileWithProfile(profile, config, 'tree');
    this.refresh();
  }

  async openReportFromNode(node) {
    const profile = node?._profile; if (!profile) return;
    const expanded = expandProfile(profile);
    const report = path.join(expanded.outputDir || '', 'compare-report.html');
    if (report && fs.existsSync(report)) await vscode.env.openExternal(vscode.Uri.file(report));
    else vscode.window.showInformationMessage('Report not found for this profile.');
  }

  async openCaptureFromNode(node) {
    const profile = node?._profile; if (!profile) return;
    const expanded = expandProfile(profile);
    const capPath = path.join(expanded.outputDir || '', 'lvcompare-capture.json');
    if (capPath && fs.existsSync(capPath)) {
      const doc = await vscode.workspace.openTextDocument(vscode.Uri.file(capPath));
      await vscode.window.showTextDocument(doc);
    } else vscode.window.showInformationMessage('Capture JSON not found for this profile.');
  }

  async revealOutputFromNode(node) {
    const profile = node?._profile; if (!profile) return;
    const expanded = expandProfile(profile);
    const outDir = expanded.outputDir || '';
    if (outDir) await vscode.commands.executeCommand('revealFileInOS', vscode.Uri.file(outDir));
  }
}
    yearSelect.addEventListener('change', () => {
      vscode.postMessage({ type: 'updateLabVIEW', year: yearSelect.value, bits: bitsSelect.value });
    });
    bitsSelect.addEventListener('change', () => {
      vscode.postMessage({ type: 'updateLabVIEW', year: yearSelect.value, bits: bitsSelect.value });
    });
    copyCliBtn.addEventListener('click', () => {
      vscode.postMessage({ type: 'copyCli', variant: 'current' });
    });
    copyCliLastBtn.addEventListener('click', () => {
      vscode.postMessage({ type: 'copyCli', variant: 'last' });
    });
    openCliBtn.addEventListener('click', () => {
      vscode.postMessage({ type: 'openCli' });
    });

    function renderImages(list) {
      imagesEl.innerHTML = '';
      if (!Array.isArray(list) || list.length === 0) {
        imagesEl.textContent = '(no images)';
        return;
      }
      list.forEach((img) => {
        const wrap = document.createElement('div');
        wrap.className = 'image-item';
        if (img.thumbnail) {
          const imageEl = document.createElement('img');
          imageEl.src = img.thumbnail;
          imageEl.alt = img.name;
          imageEl.addEventListener('click', () => vscode.postMessage({ type: 'openImage', path: img.path }));
          wrap.appendChild(imageEl);
        } else {
          const btn = document.createElement('button');
          btn.type = 'button';
          btn.textContent = 'Open';
          btn.addEventListener('click', () => vscode.postMessage({ type: 'openImage', path: img.path }));
          wrap.appendChild(btn);
        }
        const caption = document.createElement('div');
        caption.textContent = img.name || 'image';
        wrap.appendChild(caption);
        imagesEl.appendChild(wrap);
      });
    }
