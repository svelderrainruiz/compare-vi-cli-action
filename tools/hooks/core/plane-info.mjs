#!/usr/bin/env node
import { HookRunner, info, which } from './runner.mjs';

const runner = new HookRunner('plane-info');
const plane = runner.environment.plane;
const enforcement = runner.enforcement;
const githubActions = runner.environment.githubActions;
const pwsh = runner.resolvePwsh();
const bash = which('bash') || (process.platform === 'win32' ? 'C:/Program Files/Git/bin/bash.exe' : null);

info('plane: ' + plane);
info('enforcement: ' + enforcement);
info('githubActions: ' + githubActions);
info('node: ' + runner.environment.nodeVersion);
info('pwsh: ' + (pwsh || 'not found'));
info('bash: ' + (bash || 'not found'));

if (!pwsh && enforcement === 'fail') {
  console.error('[hooks] PowerShell not found but HOOKS_ENFORCE=fail');
  process.exit(2);
}

process.exit(0);
