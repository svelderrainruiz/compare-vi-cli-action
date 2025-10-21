#!/usr/bin/env node

import process from 'node:process';

const [, , versionArg] = process.argv;

console.log('Release finalizer is not yet implemented.');
if (versionArg) {
  console.log(`Requested version: ${versionArg}`);
}
console.log('Track progress in issue #270. Exiting.');

process.exit(1);
