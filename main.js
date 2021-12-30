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
