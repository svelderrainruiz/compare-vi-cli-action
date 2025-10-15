const fs = require('fs');
const os = require('os');
const path = require('path');

const {
  resolveLabVIEWPath,
  buildPwshArgsFile,
  buildPwshCommandWrapper,
  summarizeCapture,
  detectCliArtifacts
} = require('../../lib/core');

describe('core helpers', () => {
  describe('resolveLabVIEWPath', () => {
    it('prefers ProgramW6432 for 64-bit', () => {
      const env = { ProgramW6432: 'C:/PF64', ProgramFiles: 'C:/PF', ['ProgramFiles(x86)']: 'C:/PF86' };
      expect(resolveLabVIEWPath('2025', '64', env)).toBe(path.join('C:/PF64', 'National Instruments', 'LabVIEW 2025', 'LabVIEW.exe'));
    });

    it('uses ProgramFiles(x86) for 32-bit', () => {
      const env = { ProgramFiles: 'C:/PF', ['ProgramFiles(x86)']: 'C:/PF86' };
      expect(resolveLabVIEWPath('2022', '32', env)).toBe(path.join('C:/PF86', 'National Instruments', 'LabVIEW 2022', 'LabVIEW.exe'));
    });
  });

  describe('buildPwshArgsFile', () => {
    it('includes flags as additional parameters', () => {
      const args = buildPwshArgsFile('script.ps1', 'base.vi', 'head.vi', 'lv.exe', 'out', ['-a', '-b']);
      expect(args).toEqual([
        '-NoLogo', '-NoProfile', '-File', 'script.ps1',
        '-BaseVi', 'base.vi',
        '-HeadVi', 'head.vi',
        '-LabVIEWExePath', 'lv.exe',
        '-OutputDir', 'out',
        '-RenderReport',
        '-Flags', '-a', '-b'
      ]);
    });
  });

  describe('buildPwshCommandWrapper', () => {
    it('emits array literal for flags and maps diff exit code', () => {
      const result = buildPwshCommandWrapper('script.ps1', 'base', 'head', 'lv.exe', 'out', ['-foo','-bar'], true);
      expect(result[0]).toBe('-NoLogo');
      expect(result[1]).toBe('-NoProfile');
      expect(result[2]).toBe('-Command');
      const command = result[3];
      expect(command).toContain("-Flags @('-foo','-bar')");
      expect(command).toContain('if ($c -eq 1) { exit 0 }');
    });

    it('omits flags segment when none supplied', () => {
      const result = buildPwshCommandWrapper('script.ps1', 'base', 'head', 'lv.exe', 'out', undefined, false);
      expect(result[3]).not.toContain('-Flags');
    });
  });

  describe('summarizeCapture', () => {
    it('returns null when file missing', () => {
      expect(summarizeCapture(path.join(os.tmpdir(), 'non-existent.json'))).toBeNull();
    });

    it('parses capture json', () => {
      const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'comparevi-core-'));
      const file = path.join(dir, 'capture.json');
      fs.writeFileSync(file, JSON.stringify({ exitCode: 1, seconds: 2.5, command: 'pwsh foo' }));
      const summary = summarizeCapture(file);
      expect(summary.exitCode).toBe(1);
      expect(summary.seconds).toBe(2.5);
      expect(summary.command).toBe('pwsh foo');
    });
  });

  describe('detectCliArtifacts', () => {
    it('discovers known outputs and image files', () => {
      const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'comparevi-artifacts-'));
      const stdoutPath = path.join(dir, 'lvcli-stdout.txt');
      const stderrPath = path.join(dir, 'lvcompare-stderr.txt');
      fs.writeFileSync(stdoutPath, 'stdout');
      fs.writeFileSync(stderrPath, 'stderr');
      const imagesDir = path.join(dir, 'cli-images');
      fs.mkdirSync(imagesDir);
      const imageFile = path.join(imagesDir, 'cli-image-01.png');
      fs.writeFileSync(imageFile, 'png');

      const artifacts = detectCliArtifacts(dir, { cap: { environment: { cli: { artifacts: { exportDir: imagesDir } } } } });
      expect(artifacts.lvcliStdout).toBe(stdoutPath);
      expect(artifacts.lvcompareStderr).toBe(stderrPath);
      expect(artifacts.imagesDir).toBe(imagesDir);
      expect(artifacts.imageFiles).toEqual([imageFile]);
    });
  });
});
