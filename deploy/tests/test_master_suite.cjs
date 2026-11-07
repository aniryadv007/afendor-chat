// AFENDOR CHAT: Master Production Verification Test Suite Runner
const { spawn } = require('child_process');
const path = require('path');

const tests = [
    { name: 'Bash Lexer & Syntax Audit', script: 'test_bash_lexer.cjs' },
    { name: 'POSIX LF Line Ending Validation', script: 'test_line_endings.cjs' },
    { name: 'S3 Verify Utility (deploy/scripts/s3-verify.sh)', script: 'test_s3_verify.cjs' },
    { name: 'S3 Comprehensive AWS SigV4 Compatibility', script: 'test_s3_suite.cjs' },
    { name: 'Storage Selection & 3-Attempt Fallback', script: 'test_storage_fallback.cjs' }
];

function runTest(testObj) {
    return new Promise((resolve) => {
        const fullPath = path.join(__dirname, testObj.script);
        const start = Date.now();
        const proc = spawn(process.execPath, [fullPath]);
        let stdout = '';
        let stderr = '';
        proc.stdout.on('data', d => stdout += d.toString());
        proc.stderr.on('data', d => stderr += d.toString());
        proc.on('close', (code) => {
            const duration = Date.now() - start;
            resolve({
                name: testObj.name,
                script: testObj.script,
                code,
                duration,
                stdout: stdout.trim(),
                stderr: stderr.trim()
            });
        });
    });
}

async function runAll() {
    console.log("================================================================");
    console.log("       AFENDOR CHAT - PRODUCTION VERIFICATION MASTER SUITE      ");
    console.log("================================================================\n");

    let totalPassed = 0;
    let totalFailed = 0;
    const results = [];

    for (const t of tests) {
        process.stdout.write(`Executing: ${t.name}... `);
        const res = await runTest(t);
        results.push(res);
        if (res.code === 0) {
            console.log(`[PASS] (${res.duration}ms)`);
            totalPassed++;
        } else {
            console.log(`[FAIL] (Exit: ${res.code})`);
            console.log(`  Error Output:\n${res.stderr || res.stdout}\n`);
            totalFailed++;
        }
    }

    console.log("\n================================================================");
    console.log(`SUMMARY: ${totalPassed} suites passed, ${totalFailed} suites failed.`);
    console.log("================================================================\n");

    process.exit(totalFailed > 0 ? 1 : 0);
}

runAll();

