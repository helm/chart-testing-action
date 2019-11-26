const spawn = require('child_process').spawn
const path = require("path");

const main = async () => {
    await new Promise((resolve, reject) => {
        const proc = spawn('bash', ['-c', path.join(__dirname, 'main.sh')], {stdio: 'inherit'})
        proc.on('close', resolve)
        proc.on('error', reject)
    })
}

main().catch(err => {
    console.error(err)
    console.error(err.stack)
    process.exit(-1)
})
