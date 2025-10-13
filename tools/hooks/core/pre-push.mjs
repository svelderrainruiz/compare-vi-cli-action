#!/usr/bin/env node
import path from 'node:path';
import { HookRunner, info } from './runner.mjs';

const runner = new HookRunner('pre-push');

const scriptPath = path.join('tools', 'hooks', 'scripts', 'pre-push.ps1');
info('[pre-push] Running core pre-push checks');
runner.runPwshStep('pre-push-checks', scriptPath);

runner.writeSummary();

if (runner.exitCode !== 0) {
  info('[pre-push] Hook failed; inspect tests/results/_hooks/pre-push.json for details.');
} else {
  info('[pre-push] OK');
}

process.exit(runner.exitCode);
