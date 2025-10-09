#!/usr/bin/env node

import { ArgumentParser } from 'argparse';
import chokidar from 'chokidar';
import fs from 'fs';
import fsp from 'fs/promises';
import path from 'path';
import process from 'process';

const parser = new ArgumentParser({
  description: 'Stream Pester dispatcher output and summary updates.',
});

parser.add_argument('--results', {
  help: 'Root directory containing Pester results',
  default: 'tests/results',
});
parser.add_argument('--log', {
  help: 'Relative log file path under results',
  default: 'pester-dispatcher.log',
});
parser.add_argument('--summary', {
  help: 'Relative summary JSON file under results',
  default: 'pester-summary.json',
});
parser.add_argument('--tail', {
  help: 'Initial tail line count',
  type: 'int',
  default: 40,
});
parser.add_argument('--warn-seconds', {
  help: 'Idle seconds before warning',
  type: 'int',
  default: 90,
});
parser.add_argument('--hang-seconds', {
  help: 'Idle seconds before hang suspicion',
  type: 'int',
  default: 180,
});
parser.add_argument('--poll-ms', {
  help: 'Periodic poll to catch missed writes',
  type: 'int',
  default: 10000,
});
parser.add_argument('--exit-on-hang', {
  help: 'Exit with non-zero code when hang is suspected',
  action: 'store_true',
  default: false,
});
parser.add_argument('--no-progress-seconds', {
  help: 'Seconds without progress before warning/failure (0 to disable)',
  type: 'int',
  default: 0,
});
parser.add_argument('--progress-regex', {
  help: 'Regex that identifies progress log lines',
  default: '^(?:\\s*\\[[-+\\*]\\]|\\s*It\\s)'
});
parser.add_argument('--exit-on-no-progress', {
  help: 'Exit with non-zero code when no-progress threshold is exceeded',
  action: 'store_true',
  default: false,
});
parser.add_argument('--quiet', {
  help: 'Suppress informational messages',
  action: 'store_true',
  default: false,
});

const args = parser.parse_args();

const resultsDir = path.resolve(args.results);
const logPath = path.resolve(resultsDir, args.log);
const summaryPath = path.resolve(resultsDir, args.summary);
const tailLines = Math.max(0, args.tail);
const quiet = Boolean(args.quiet);
const warnSeconds = Math.max(1, Number(args['warn_seconds'] ?? args.warn_seconds ?? args['warn-seconds']));
const hangSeconds = Math.max(warnSeconds + 1, Number(args['hang_seconds'] ?? args.hang_seconds ?? args['hang-seconds']));
const pollMs = Math.max(250, Number(args['poll_ms'] ?? args.poll_ms ?? args['poll-ms']));
const exitOnHang = Boolean(args['exit_on_hang'] ?? args.exit_on_hang ?? args['exit-on-hang']);
const noProgressSecondsRaw = Number(args['no_progress_seconds'] ?? args.no_progress_seconds ?? args['no-progress-seconds']);
const noProgressSeconds = Number.isFinite(noProgressSecondsRaw) ? Math.max(0, noProgressSecondsRaw) : 0;
const progressPattern = args['progress_regex'] ?? args.progress_regex ?? args['progress-regex'] ?? '^(?:\s*\[[-+\*]\]|\s*It\s)';
const progressRegex = new RegExp(progressPattern, 'i');
const exitOnNoProgress = Boolean(args['exit_on_no_progress'] ?? args.exit_on_no_progress ?? args['exit-on-no-progress']);
const noProgressWarnSeconds = noProgressSeconds > 0 ? Math.max(1, Math.min(noProgressSeconds, Math.floor(noProgressSeconds / 2) || 1)) : 0;

let logPosition = 0;
let logProcessing = Promise.resolve();
let summaryTimer = null;
let lastActivityAt = Date.now();
let lastStatsSize = 0;
let lastStatsMtimeMs = 0;
let hangReported = false;
let shuttingDown = false;
let lastProgressAt = Date.now();
let lastProgressBytes = 0;
let busyReported = false;

function info(message) {
  if (!quiet) {
    console.log(message);
  }
}

function warn(message) {
  console.warn(message);
}

async function ensureDirectory(target) {
  try {
    await fsp.mkdir(target, { recursive: true });
  } catch (err) {
    if (err && err.code !== 'EEXIST') {
      throw err;
    }
  }
}

async function readFileTail(filePath, lines) {
  try {
    const raw = await fsp.readFile(filePath, 'utf8');
    const allLines = raw.split(/\r?\n/).filter(Boolean);
    const start = lines > 0 ? Math.max(0, allLines.length - lines) : allLines.length;
    const tail = allLines.slice(start);
    let progressDetected = false;
    for (const line of tail) {
      if (line && progressRegex.test(line)) {
        progressDetected = true;
      }
      console.log(line);
    }
    const stats = await fsp.stat(filePath);
    logPosition = stats.size;
    lastStatsSize = stats.size;
    lastStatsMtimeMs = stats.mtimeMs;
    lastActivityAt = Date.now();
    hangReported = false;
    if (progressDetected) {
      lastProgressAt = Date.now();
      lastProgressBytes = stats.size;
      busyReported = false;
    } else if (lastProgressBytes === 0) {
      lastProgressBytes = stats.size;
    }
  } catch (err) {
    if (err.code === 'ENOENT') {
      logPosition = 0;
    } else {
      warn(`[watch] Failed to read tail for ${filePath}: ${err.message}`);
    }
  }
}

async function readLogDelta(filePath) {
  try {
    const fh = await fsp.open(filePath, 'r');
    try {
      const stats = await fh.stat();
      if (stats.size < logPosition) {
        logPosition = 0;
      }
      const length = stats.size - logPosition;
      if (length <= 0) {
        // no new bytes; update stats baselines
        lastStatsSize = stats.size;
        lastStatsMtimeMs = stats.mtimeMs;
        return;
      }
      const buffer = Buffer.alloc(length);
      await fh.read(buffer, 0, length, logPosition);
      logPosition = stats.size;
      lastStatsSize = stats.size;
      lastStatsMtimeMs = stats.mtimeMs;
      const text = buffer.toString('utf8');
      let progressDetected = false;
      for (const line of text.split(/\r?\n/)) {
        if (line.trim().length > 0) {
          if (progressRegex.test(line)) {
            progressDetected = true;
          }
          console.log(`[log] ${line}`);
        }
      }
      // Count any appended bytes as activity even if lines were blank/partial
      lastActivityAt = Date.now();
      if (progressDetected) {
        lastProgressAt = Date.now();
        lastProgressBytes = stats.size;
        busyReported = false;
      } else if (lastProgressBytes === 0) {
        lastProgressBytes = stats.size;
      }
      hangReported = false;
    } finally {
      await fh.close();
    }
  } catch (err) {
    if (err.code === 'ENOENT') {
      warn('[watch] Log file missing; waiting for recreation.');
      logPosition = 0;
    } else {
      warn(`[watch] Failed to read log delta: ${err.message}`);
    }
  }
}

function enqueueLogRead(fn) {
  logProcessing = logProcessing.then(fn, fn);
}

async function emitSummary(filePath) {
  try {
    const content = await fsp.readFile(filePath, 'utf8');
    if (!content.trim()) {
      return;
    }
    const data = JSON.parse(content);
    const result = data.result ?? data.Result ?? null;
    const totals = data.totals ?? data.Totals ?? {};
    const tests = totals.tests ?? totals.Tests ?? null;
    const passed = totals.passed ?? totals.Passed ?? null;
    const failed = totals.failed ?? totals.Failed ?? null;
    const skipped = totals.skipped ?? totals.Skipped ?? null;
    const duration = data.durationSeconds ?? data.DurationSeconds ?? data.duration ?? null;
    const parts = ['[summary]'];
    if (result !== null && result !== undefined) {
      parts.push(`Result=${result}`);
    }
    if (tests !== null && tests !== undefined) {
      parts.push(`Tests=${tests}`);
    }
    if (passed !== null && passed !== undefined) {
      parts.push(`Passed=${passed}`);
    }
    if (failed !== null && failed !== undefined) {
      parts.push(`Failed=${failed}`);
    }
    if (skipped !== null && skipped !== undefined) {
      parts.push(`Skipped=${skipped}`);
    }
    if (duration !== null && duration !== undefined) {
      parts.push(`Duration=${duration}`);
    }
    console.log(parts.join(' '));
    lastProgressAt = Date.now();
    lastProgressBytes = logPosition;
    busyReported = false;
    hangReported = false;
  } catch (err) {
    if (err.code === 'ENOENT') {
      return;
    }
    warn(`[summary] Failed to parse summary: ${err.message}`);
  }
}

async function watch() {
  await ensureDirectory(path.dirname(logPath));
  await ensureDirectory(path.dirname(summaryPath));

  info(`[watch] Results directory: ${resultsDir}`);
  info(`[watch] Log: ${logPath}`);
  info(`[watch] Summary: ${summaryPath}`);

  if (fs.existsSync(logPath)) {
    info(`[watch] Initial tail (${tailLines} lines)`);
    await readFileTail(logPath, tailLines);
  } else {
    info('[watch] Waiting for log file to appear...');
  }

  const watcherOptions = {
    persistent: true,
    ignoreInitial: false,
    awaitWriteFinish: {
      stabilityThreshold: 150,
      pollInterval: 100,
    },
  };

  const logWatcher = chokidar.watch(logPath, watcherOptions);

  logWatcher
    .on('add', () => {
      info('[watch] Log file created.');
      enqueueLogRead(async () => {
        await readFileTail(logPath, tailLines);
      });
    })
    .on('change', () => {
      enqueueLogRead(async () => {
        await readLogDelta(logPath);
      });
    })
    .on('unlink', () => {
      warn('[watch] Log file deleted; resetting position.');
      logPosition = 0;
      lastStatsSize = 0;
      lastStatsMtimeMs = 0;
      lastProgressBytes = 0;
      lastProgressAt = Date.now();
      busyReported = false;
    })
    .on('error', (error) => {
      warn(`[watch] Log watcher error: ${error.message ?? error}`);
    });

  const summaryWatcher = chokidar.watch(summaryPath, watcherOptions);

  summaryWatcher
    .on('add', () => {
      info('[watch] Summary file created.');
      emitSummary(summaryPath);
      lastActivityAt = Date.now();
      lastProgressAt = Date.now();
      lastProgressBytes = logPosition;
      busyReported = false;
    })
    .on('change', () => {
      if (summaryTimer) {
        clearTimeout(summaryTimer);
      }
      summaryTimer = setTimeout(() => {
        emitSummary(summaryPath);
        lastActivityAt = Date.now();
        lastProgressAt = Date.now();
        lastProgressBytes = logPosition;
        busyReported = false;
      }, 150);
    })
    .on('unlink', () => {
      info('[watch] Summary file removed.');
      if (summaryTimer) {
        clearTimeout(summaryTimer);
        summaryTimer = null;
      }
    })
    .on('error', (error) => {
      warn(`[watch] Summary watcher error: ${error.message ?? error}`);
    });

  // Periodic poll to detect missed writes and idle/hang suspicion
  const pollTimer = setInterval(async () => {
    try {
      // Check for missed writes
      const exists = fs.existsSync(logPath);
      if (exists) {
        const stats = await fsp.stat(logPath);
        if (stats.size > logPosition) {
          enqueueLogRead(async () => {
            await readLogDelta(logPath);
          });
        } else {
          // Update baselines
          lastStatsSize = stats.size;
          lastStatsMtimeMs = stats.mtimeMs;
        }
      }
    } catch (e) {
      // ignore
    }
    // Idle/hang detection
    const idleMs = Date.now() - lastActivityAt;
    const idleSec = Math.floor(idleMs / 1000);
    if (idleSec >= hangSeconds) {
      if (!hangReported) {
        warn(`[hang-suspect] idle ~${idleSec}s (no new log bytes or summary). live-bytes=${lastStatsSize} consumed-bytes=${logPosition}`);
        hangReported = true;
      }
      if (exitOnHang && !shuttingDown) {
        shuttingDown = true;
        clearInterval(pollTimer);
        Promise.all([logWatcher.close(), summaryWatcher.close()])
          .catch((err) => {
            warn(`[watch] Error while closing watchers: ${err.message ?? err}`);
          })
          .finally(() => {
            process.exit(2);
          });
      }
    } else if (idleSec >= warnSeconds) {
      info(`[hang-watch] idle ~${idleSec}s (monitoring). live-bytes=${lastStatsSize} consumed-bytes=${logPosition}`);
    }

    // Busy (no-progress) detection
    if (noProgressSeconds > 0) {
      const now = Date.now();
      const noProgMs = now - lastProgressAt;
      const noProgSec = Math.floor(noProgMs / 1000);
      const bytesSinceProgress = Math.max(0, logPosition - lastProgressBytes);
      const bytesChanging = bytesSinceProgress > 0;
      if (noProgSec >= noProgressSeconds) {
        if (!busyReported) {
          warn(`[busy-suspect] no-progress ~${noProgSec}s (bytes-changing=${bytesChanging})`);
          busyReported = true;
        }
        if (exitOnNoProgress && !shuttingDown) {
          shuttingDown = true;
          clearInterval(pollTimer);
          Promise.all([logWatcher.close(), summaryWatcher.close()])
            .catch((err) => {
              warn(`[watch] Error while closing watchers: ${err.message ?? err}`);
            })
            .finally(() => {
              process.exit(3);
            });
        }
      } else if (noProgressWarnSeconds > 0 && noProgSec >= noProgressWarnSeconds) {
        info(`[busy-watch] no-progress ~${noProgSec}s (bytes-changing=${bytesChanging})`);
      } else if (noProgSec === 0) {
        busyReported = false;
      }
    }
  }, pollMs);

  async function closeWatchers() {
    if (shuttingDown) { return }
    shuttingDown = true;
    clearInterval(pollTimer);
    try {
      await Promise.all([logWatcher.close(), summaryWatcher.close()]);
    } catch (err) {
      warn(`[watch] Error while closing watchers: ${err.message ?? err}`);
    }
  }

  function shutdown(signal) {
    info(`[watch] Received ${signal}; shutting down watchers.`);
    closeWatchers()
      .catch(() => {})
      .finally(() => process.exit(0));
  }

  process.on('SIGINT', () => shutdown('SIGINT'));
  process.on('SIGTERM', () => shutdown('SIGTERM'));
}

watch().catch((error) => {
  warn(`[watch] Fatal error: ${error.message ?? error}`);
  process.exit(1);
});
