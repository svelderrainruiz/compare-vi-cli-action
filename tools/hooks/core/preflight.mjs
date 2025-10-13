#!/usr/bin/env node
import { HookRunner, info, which } from './runner.mjs';

const runner = new HookRunner('preflight');
const pwsh = runner.resolvePwsh();
const bash = which('bash') || (process.platform === 'win32' ? 'C:/Program Files/Git/bin/bash.exe' : null);

info('[preflight] plane: ' + runner.environment.plane);
info('[preflight] enforcement: ' + runner.enforcement);
info('[preflight] node: ' + runner.environment.nodeVersion);
info('[preflight] pwsh: ' + (pwsh || 'not found'));
info('[preflight] bash: ' + (bash || 'not found'));

if (!pwsh) {
  const message = '[preflight] PowerShell not detected. Set HOOKS_PWSH or install PowerShell 7.';
  if (runner.enforcement === 'fail') {
    console.error(message);
    process.exit(2);
  } else {
    info(message + ' (treated as warning)');
  }
}

if (!bash && process.platform === 'win32') {
  info('[preflight] Git Bash not detected. Install Git for Windows to enable shell-plane hooks.');
}

info('[preflight] Completed.');
process.exit(0);
