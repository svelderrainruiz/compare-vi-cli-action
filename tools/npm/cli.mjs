#!/usr/bin/env node
import { spawn } from 'node:child_process';
import { createSanitizedNpmEnv } from './sanitize-env.mjs';
import { createNpmLaunchSpec } from './spawn.mjs';

function printUsage() {
  console.error('Usage: cli.mjs <npm-command> [args...]');
  console.error('Example: cli.mjs install');
}

const npmArgs = process.argv.slice(2);
if (npmArgs.length === 0) {
  printUsage();
  process.exitCode = 1;
  process.exit();
}

const env = createSanitizedNpmEnv();
const launchSpec = createNpmLaunchSpec(npmArgs, env);

const child = spawn(launchSpec.command, launchSpec.args, {
  env,
  stdio: 'inherit',
});

child.on('exit', (code, signal) => {
  if (signal) {
    process.kill(process.pid, signal);
    return;
  }
  process.exit(code ?? 0);
});

child.on('error', (error) => {
  console.error(`Failed to launch npm: ${error.message}`);
  process.exit(1);
});
