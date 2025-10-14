import * as path from "path";
import Mocha = require("mocha");
import glob = require("glob");

export function run(): Promise<void> {
    const mocha = new Mocha({
        ui: "tdd",
        color: true
    });

    const testsRoot = path.resolve(__dirname, "..");

    return new Promise((resolve, reject) => {
        glob("**/**.test.js", { cwd: testsRoot }, (err: Error | null, files: string[]) => {
            if (err) {
                return reject(err);
            }
            files.forEach(file => mocha.addFile(path.resolve(testsRoot, file)));

            try {
                mocha.run(failures => {
                    if (failures && failures > 0) {
                        reject(new Error(`${failures} tests failed.`));
                    } else {
                        resolve();
                    }
                });
            } catch (error) {
                reject(error);
            }
        });
    });
}
