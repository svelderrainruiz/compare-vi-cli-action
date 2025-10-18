const path = require('path');
const fs = require('fs');
const { spawnSync } = require('child_process');

let gitRunnerOverride;

function setGitRunnerOverride(fn) {
  gitRunnerOverride = fn;
}

function resetGitRunnerOverride() {
  gitRunnerOverride = undefined;
}

function runGit(repoRoot, args, options = {}) {
  if (gitRunnerOverride) {
    return gitRunnerOverride(repoRoot, args, options);
  }

  const result = spawnSync('git', args, {
    cwd: repoRoot,
    encoding: 'utf8',
    stdio: ['ignore', 'pipe', 'pipe'],
    ...options
  });

  if (result.status !== 0) {
    const message = result.stderr ? result.stderr.trim() : `git ${args.join(' ')} failed`;
    const error = new Error(message);
    error.code = result.status;
    throw error;
  }

  return result.stdout;
}

function getCommitInfo(repoRoot, ref) {
  const format = '%H%n%h%n%ad%n%s';
  const stdout = runGit(repoRoot, ['show', '-s', `--format=${format}`, '--date=iso-strict', ref]);
  const [hash = '', shortHash = '', date = '', subject = ''] = stdout.trim().split('\n');
  return { ref, hash, shortHash, date, subject };
}

function listVisAtCommit(repoRoot, ref) {
  const stdout = runGit(repoRoot, ['ls-tree', '--full-tree', '-r', '--name-only', ref]);
  return stdout
    .split('\n')
    .map((line) => line.trim())
    .filter((line) => line.toLowerCase().endsWith('.vi'))
    .filter(Boolean);
}

function extractFileAtCommit(repoRoot, ref, filePath, destinationPath) {
  const dir = path.dirname(destinationPath);
  fs.mkdirSync(dir, { recursive: true });
  const gitPath = `${ref}:${filePath}`;
  const stdout = runGit(repoRoot, ['show', gitPath], { encoding: 'buffer' });
  fs.writeFileSync(destinationPath, stdout);
  return destinationPath;
}

module.exports = {
  runGit,
  setGitRunnerOverride,
  resetGitRunnerOverride,
  getCommitInfo,
  listVisAtCommit,
  extractFileAtCommit
};
