const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '../..');
const dirs = ['deploy/bin', 'deploy/scripts', 'deploy/compose', 'deploy/nginx', 'config/env'];
let crlfCount = 0;
let checked = 0;

function checkFile(filePath) {
    checked++;
    const buf = fs.readFileSync(filePath);
    let hasCR = false;
    for (let i = 0; i < buf.length; i++) {
        if (buf[i] === 0x0D) { // Carriage Return \r
            hasCR = true;
            break;
        }
    }
    if (hasCR) {
        crlfCount++;
        // Normalize to LF
        const content = buf.toString('utf8').replace(/\r\n/g, '\n');
        fs.writeFileSync(filePath, content, 'utf8');
        console.log(`[FIXED CRLF->LF] ${path.relative(ROOT, filePath)}`);
    }
}

function walk(dir) {
    const full = path.join(ROOT, dir);
    if (!fs.existsSync(full)) return;
    const entries = fs.readdirSync(full, { withFileTypes: true });
    for (const e of entries) {
        const p = path.join(full, e.name);
        if (e.isDirectory()) walk(path.relative(ROOT, p));
        else if (e.isFile()) checkFile(p);
    }
}

dirs.forEach(walk);
checkFile(path.join(ROOT, 'deploy/install.sh'));

console.log(`\nLine Endings Audit: Checked ${checked} files, ${crlfCount} had CRLF and were normalized to LF.`);
process.exit(0);

