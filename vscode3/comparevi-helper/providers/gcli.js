const fs = require('fs');
const vscode = require('vscode');

const DEFAULT_GCLI_PATH = process.platform === 'win32'
  ? 'C\\\\Program Files\\\\G-CLI\\\\bin\\\\g-cli.exe'
  : '/usr/local/bin/g-cli';

function resolveConfiguredPath() {
  const config = vscode.workspace.getConfiguration();
  const configured = config.get('comparevi.providers.gcli.path');
  const value = typeof configured === 'string' && configured.trim().length
    ? configured.trim()
    : DEFAULT_GCLI_PATH;
  return value;
}

function gcliExists(fsPath) {
  try { return fs.existsSync(fsPath); } catch { return false; }
}

function getStatus() {
  const gcliPath = resolveConfiguredPath();
  const exists = gcliExists(gcliPath);
  return {
    id: 'gcli',
    ok: exists,
    message: exists
      ? `g-cli detected at ${gcliPath}`
      : `g-cli executable not found at ${gcliPath}`
  };
}

function createStubProvider() {
  let disposable;
  return {
    id: 'gcli',
    displayName: 'G CLI (stub)',
    docsUrl: 'https://github.com/LabVIEW-Community-CI-CD/compare-vi-cli-action',
    activate(context) {
      disposable = vscode.workspace.onDidChangeConfiguration((event) => {
        if (event.affectsConfiguration('comparevi.providers.gcli.path')) {
          context.subscriptions.forEach((item) => {
            if (item && typeof item._onGcliStatusChanged === 'function') {
              try { item._onGcliStatusChanged(getStatus()); } catch { /* noop */ }
            }
          });
        }
      });
      context.subscriptions.push(disposable);
    },
    deactivate() {
      try { disposable?.dispose(); } catch { /* noop */ }
      disposable = undefined;
    },
    getStatus,
    isAvailable() {
      return getStatus().ok;
    },
    getState() {
      const status = getStatus();
      return {
        providerId: 'gcli',
        status
      };
    }
  };
}

module.exports = createStubProvider;
