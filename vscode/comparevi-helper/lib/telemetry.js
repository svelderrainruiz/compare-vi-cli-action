const fs = require('fs');
const path = require('path');
const vscode = require('vscode');

async function writeEvent(event, payload = {}) {
  try {
    const config = vscode.workspace.getConfiguration();
    const enabled = config.get('comparevi.telemetryEnabled');
    if (enabled === false) {
      return false;
    }
    const folders = vscode.workspace.workspaceFolders;
    if (!folders || !folders.length) {
      return false;
    }
    const workspace = folders[0].uri.fsPath;
    const dir = path.join(workspace, 'tests', 'results', 'telemetry');
    await fs.promises.mkdir(dir, { recursive: true });
    const file = path.join(dir, 'n-cli-companion.ndjson');
    const entry = {
      event,
      timestamp: new Date().toISOString(),
      ...payload
    };
    await fs.promises.appendFile(file, JSON.stringify(entry) + '\n', 'utf8');
    return true;
  } catch (error) {
    console.warn('[telemetry] failed to record event', error);
    return false;
  }
}

module.exports = {
  writeEvent
};
