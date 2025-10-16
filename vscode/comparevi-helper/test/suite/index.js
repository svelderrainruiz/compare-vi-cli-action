const path = require('path');
const Mocha = require('mocha');
const glob = require('glob');

function run() {
  const mocha = new Mocha({ ui: 'bdd', timeout: 20000 });
  const testsRoot = path.resolve(__dirname, '.');

  return new Promise((resolve, reject) => {
    glob('**/*.test.js', { cwd: testsRoot }, (err, files) => {
      if (err) {
        return reject(err);
      }
      files.forEach((file) => mocha.addFile(path.resolve(testsRoot, file)));
      try {
        mocha.run((failures) => (failures ? reject(new Error(`${failures} tests failed`)) : resolve()));
      } catch (error) {
        reject(error);
      }
    });
  });
}

module.exports = {
  run
};
