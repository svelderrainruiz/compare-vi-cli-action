const path = require('path');
const fs = require('fs');

function resolveLabVIEWPath(year, bits, env = process.env) {
  const pf64 = env['ProgramW6432'] || env['ProgramFiles'] || 'C:\\Program Files';
  const pf86 = env['ProgramFiles(x86)'] || pf64;
  const parent = bits === '32' ? pf86 : pf64;
  return path.join(parent, 'National Instruments', `LabVIEW ${year}`, 'LabVIEW.exe');
}

function buildPwshArgsFile(scriptPath, baseVi, headVi, labviewExePath, outDir, flags) {
  const args = ['-NoLogo', '-NoProfile', '-File', scriptPath,
    '-BaseVi', baseVi,
    '-HeadVi', headVi,
    '-LabVIEWExePath', labviewExePath,
    '-OutputDir', outDir,
    '-RenderReport'];
  if (Array.isArray(flags) && flags.length) { args.push('-Flags', ...flags); }
  return args;
}

function buildPwshCommandWrapper(scriptPath, baseVi, headVi, labviewExePath, outDir, flags, diffAsSuccess) {
  const singleQuote = (value) => `'${String(value).replace(/'/g, "''")}'`;
  const parts = [
    `& ${singleQuote(scriptPath)}`,
    '-BaseVi', singleQuote(baseVi),
    '-HeadVi', singleQuote(headVi),
    '-LabVIEWExePath', singleQuote(labviewExePath),
    '-OutputDir', singleQuote(outDir),
    '-RenderReport'
  ];
  if (Array.isArray(flags) && flags.length) {
    const literal = `@(${flags.map(singleQuote).join(',')})`;
    parts.push('-Flags', literal);
  }
  const command = parts.join(' ');
  const mapper = diffAsSuccess ? '; $c=$LASTEXITCODE; if ($c -eq 1) { exit 0 } else { exit $c }' : '';
  return ['-NoLogo', '-NoProfile', '-Command', `${command}${mapper}`];
}

function summarizeCapture(capPath) {
  try {
    if (!fs.existsSync(capPath)) return null;
    const cap = JSON.parse(fs.readFileSync(capPath, 'utf8'));
    const exitCode = typeof cap.exitCode === 'number' ? cap.exitCode : NaN;
    const seconds = typeof cap.seconds === 'number' ? cap.seconds : undefined;
    const command = cap.command || '';
    return { cap, capPath, exitCode, seconds, command };
  } catch {
    return null;
  }
}

function detectCliArtifacts(outDir, capInfo) {
  const artifacts = {};
  const candidate = (name) => {
    const resolved = path.join(outDir, name);
    return fs.existsSync(resolved) ? resolved : undefined;
  };
  artifacts.lvcliStdout = candidate('lvcli-stdout.txt');
  artifacts.lvcliStderr = candidate('lvcli-stderr.txt');
  artifacts.lvcompareStdout = candidate('lvcompare-stdout.txt');
  artifacts.lvcompareStderr = candidate('lvcompare-stderr.txt');

  let imagesDir;
  try {
    const exportDir = capInfo?.cap?.environment?.cli?.artifacts?.exportDir;
    if (exportDir && fs.existsSync(exportDir)) imagesDir = exportDir;
  } catch {}
  if (!imagesDir) {
    const fallback = path.join(outDir, 'cli-images');
    if (fs.existsSync(fallback)) imagesDir = fallback;
  }
  if (imagesDir) {
    const acceptable = ['.png', '.jpg', '.jpeg', '.gif', '.bmp'];
    const files = fs.readdirSync(imagesDir)
      .map((file) => path.join(imagesDir, file))
      .filter((full) => acceptable.includes(path.extname(full).toLowerCase()));
    artifacts.imagesDir = imagesDir;
    artifacts.imageFiles = files;
  }
  return artifacts;
}

module.exports = {
  resolveLabVIEWPath,
  buildPwshArgsFile,
  buildPwshCommandWrapper,
  summarizeCapture,
  detectCliArtifacts
};
