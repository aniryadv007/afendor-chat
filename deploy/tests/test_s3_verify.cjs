const MockS3Server = require('./mock_s3_server.cjs');
const { spawn } = require('child_process');
const fs = require('fs');
const path = require('path');

// Extract the NODE_CODE from deploy/scripts/s3-verify.sh
const s3VerifyContent = fs.readFileSync(path.join(__dirname, '../scripts/s3-verify.sh'), 'utf8');
const nodeCodeMatch = s3VerifyContent.match(/NODE_CODE=\$\(cat <<'EOF'\s*([\s\S]*?)\s*EOF\s*\)/);

if (!nodeCodeMatch) {
    console.error("FAILED to extract NODE_CODE from deploy/scripts/s3-verify.sh");
    process.exit(1);
}
const nodeCode = nodeCodeMatch[1];

function runNodeVerification(args) {
    return new Promise((resolve) => {
        const proc = spawn(process.execPath, ['-e', nodeCode, ...args]);
        let stdout = '';
        let stderr = '';
        proc.stdout.on('data', d => stdout += d.toString());
        proc.stderr.on('data', d => stderr += d.toString());
        proc.on('close', (code) => {
            resolve({ code, stdout, stderr, output: stdout + stderr });
        });
    });
}

async function runTests() {
    console.log("=== Testing S3 Verification Logic Against Mock S3 ===");
    let passed = 0;
    let failed = 0;

    // Test 1: Successful Put, Get, Delete
    const server1 = new MockS3Server({ port: 9101, buckets: ['afendor-test'] });
    await server1.start();
    try {
        const res = await runNodeVerification([
            'http://127.0.0.1:9101', 'us-east-1', 'TESTACCESSKEY', 'TESTSECRETKEY1234567890', 'afendor-test', 'true'
        ]);
        if (res.code === 0 && res.output.includes("SUCCESS:")) {
            console.log("[PASS] Test 1: S3 Put/Get/Delete happy path succeeded");
            passed++;
        } else {
            console.log("[FAIL] Test 1: Expected success, got code=" + res.code + " output=" + res.output);
            failed++;
        }
    } finally {
        await server1.stop();
    }

    // Test 2: Invalid Access Key
    const server2 = new MockS3Server({ port: 9102, buckets: ['afendor-test'] });
    await server2.start();
    try {
        const res = await runNodeVerification([
            'http://127.0.0.1:9102', 'us-east-1', 'WRONGKEY', 'TESTSECRETKEY1234567890', 'afendor-test', 'true'
        ]);
        if (res.code !== 0 && res.output.includes("FAILED:")) {
            console.log("[PASS] Test 2: Invalid credentials correctly rejected");
            passed++;
        } else {
            console.log("[FAIL] Test 2: Invalid credentials should fail! Got code=" + res.code);
            failed++;
        }
    } finally {
        await server2.stop();
    }

    // Test 3: Non-existent bucket
    const server3 = new MockS3Server({ port: 9103, buckets: ['real-bucket'] });
    await server3.start();
    try {
        const res = await runNodeVerification([
            'http://127.0.0.1:9103', 'us-east-1', 'TESTACCESSKEY', 'TESTSECRETKEY1234567890', 'nonexistent-bucket', 'true'
        ]);
        if (res.code !== 0 && res.output.includes("FAILED:")) {
            console.log("[PASS] Test 3: Non-existent bucket correctly rejected");
            passed++;
        } else {
            console.log("[FAIL] Test 3: Non-existent bucket should fail! Got code=" + res.code);
            failed++;
        }
    } finally {
        await server3.stop();
    }

    // Test 4: Delete Forbidden
    const server4 = new MockS3Server({ port: 9104, buckets: ['afendor-test'], simulateError: 'delete_forbidden' });
    await server4.start();
    try {
        const res = await runNodeVerification([
            'http://127.0.0.1:9104', 'us-east-1', 'TESTACCESSKEY', 'TESTSECRETKEY1234567890', 'afendor-test', 'true'
        ]);
        // If DeleteObject fails, it MUST NOT report success!
        if (res.code !== 0 && !res.output.includes("SUCCESS:")) {
            console.log("[PASS] Test 4: DeleteObject failure correctly detected");
            passed++;
        } else {
            console.log("[FAIL] Test 4: DeleteObject failure was falsely reported as SUCCESS! Output=" + res.output);
            failed++;
        }
    } finally {
        await server4.stop();
    }

    // Test 5: Corrupted Read Content
    const server5 = new MockS3Server({ port: 9105, buckets: ['afendor-test'], simulateError: 'corrupted_read' });
    await server5.start();
    try {
        const res = await runNodeVerification([
            'http://127.0.0.1:9105', 'us-east-1', 'TESTACCESSKEY', 'TESTSECRETKEY1234567890', 'afendor-test', 'true'
        ]);
        if (res.code !== 0 && !res.output.includes("SUCCESS:")) {
            console.log("[PASS] Test 5: Corrupted GetObject content detected");
            passed++;
        } else {
            console.log("[FAIL] Test 5: Corrupted GetObject content was falsely reported as SUCCESS! Output=" + res.output);
            failed++;
        }
    } finally {
        await server5.stop();
    }

    console.log(`\nResults: ${passed} passed, ${failed} failed.`);
    process.exit(failed > 0 ? 1 : 0);
}

runTests();

