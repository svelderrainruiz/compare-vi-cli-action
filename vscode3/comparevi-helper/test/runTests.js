const path = require('path');
const { runTests } = require('@vscode/test-electron');

async function main() {
  try {
    const extensionDevelopmentPath = path.resolve(__dirname, '..');
    const extensionTestsPath = path.resolve(__dirname, './suite/index');
    console.log('Running VS Code tests with:', {
      extensionDevelopmentPath,
      extensionTestsPath
    });

    const { downloadAndUnzipVSCode } = require('@vscode/test-electron/out/download');
    const { resolveCliArgsFromVSCodeExecutablePath } = require('@vscode/test-electron/out/util');
    const executable = await downloadAndUnzipVSCode({ reuseMachineInstall: true });
    const [cli, ...cliArgs] = resolveCliArgsFromVSCodeExecutablePath(executable);

    await runTests({
      vscodeExecutablePath: cli,
      extensionDevelopmentPath,
      extensionTestsPath,
      launchArgs: cliArgs,
      reuseMachineInstall: true
    });
    console.log('VS Code extension tests completed successfully.');
  } catch (err) {
    console.error('Failed to run extension tests');
    console.error(err);
    process.exit(1);
  }
}

main();
