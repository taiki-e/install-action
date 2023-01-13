// This is a script that just calls the bash script that does the main
// processing of the action. It works like a composite action that calls
// a single bash script.
//
// This was originally a trick adopted to make bash script-based actions work
// without docker before composite actions were supported. However, due to
// various problems with composite actions, this trick is still needed:
// - https://github.com/actions/runner/issues/665
// - https://github.com/actions/runner/issues/1947
// - https://github.com/actions/runner/issues/2185

const { execFileSync } = require('child_process');

function main() {
    try {
        execFileSync(
            'bash',
            ['--noprofile', '--norc', `${__dirname}/main.sh`],
            { stdio: 'inherit' }
        );
    } catch (e) {
        console.log(`::error::${e.message}`);
        process.exit(1);
    }
}

main();
