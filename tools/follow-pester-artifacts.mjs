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

let logPosition = 0;
let logProcessing = Promise.resolve();
let summaryTimer = null;
let lastActivityAt = Date.now();
let lastStatsSize = 0;
let lastStatsMtimeMs = 0;

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
    for (const line of tail) {
      console.log(line);
    }
    const stats = await fsp.stat(filePath);
    logPosition = stats.size;
    lastStatsSize = stats.size;
    lastStatsMtimeMs = stats.mtimeMs;
    lastActivityAt = Date.now();
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
      for (const line of text.split(/\r?\n/)) {
        if (line.trim().length > 0) {
          console.log(`[log] ${line}`);
        }
      }
      // Count any appended bytes as activity even if lines were blank/partial
      lastActivityAt = Date.now();
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
    })
    .on('change', () => {
      if (summaryTimer) {
        clearTimeout(summaryTimer);
      }
      summaryTimer = setTimeout(() => {
        emitSummary(summaryPath);
        lastActivityAt = Date.now();
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
      warn(`[hang-suspect] idle ~${idleSec}s (no new log bytes or summary). live-bytes=${lastStatsSize} consumed-bytes=${logPosition}`);
    } else if (idleSec >= warnSeconds) {
      info(`[hang-watch] idle ~${idleSec}s (monitoring). live-bytes=${lastStatsSize} consumed-bytes=${logPosition}`);
    }
  }, pollMs);

  function shutdown(signal) {
    info(`[watch] Received ${signal}; shutting down watchers.`);
    Promise.all([logWatcher.close(), summaryWatcher.close()])
      .catch((err) => {
        warn(`[watch] Error while closing watchers: ${err.message ?? err}`);
      })
      .finally(() => {
        try { clearInterval(pollTimer); } catch {}
        process.exit(0);
      });
  }

  process.on('SIGINT', () => shutdown('SIGINT'));
  process.on('SIGTERM', () => shutdown('SIGTERM'));
}

watch().catch((error) => {
  warn(`[watch] Fatal error: ${error.message ?? error}`);
  process.exit(1);
});
