const MockS3Server = require('./mock_s3_server.cjs');
const { spawn } = require('child_process');

// We use the fixed Node runner logic to test all edge cases
const runnerScript = `
const crypto = require('crypto');
const https = require('https');
const http = require('http');

const argv = process.argv.slice(1).filter(a => a !== '--' && a !== '[eval]' && !a.endsWith('node.exe') && !a.endsWith('node'));
const cleanArgs = argv[0] && (argv[0].startsWith('http://') || argv[0].startsWith('https://')) ? argv : argv.slice(1);
const endpoint = (cleanArgs[0] || '').replace(/\\/+$/, '');
const region = cleanArgs[1] || 'us-east-1';
const accessKey = cleanArgs[2] || '';
const secretKey = cleanArgs[3] || '';
const bucket = cleanArgs[4] || '';
const forcePathStyle = (cleanArgs[5] || '').toLowerCase() === 'true';

if (!endpoint || !accessKey || !secretKey || !bucket) {
    console.log("FAILED: Missing required S3 parameters in Node runner.");
    process.exit(1);
}

const testKey = 'afendor_test_' + Date.now() + '.txt';
const testPayload = Buffer.from('AFENDOR_S3_TEST_PAYLOAD_VALIDATED');

function hmacSha256(key, data) {
    return crypto.createHmac('sha256', key).update(data).digest();
}

function getSigningKey(secret, date, reg, service) {
    const kDate = hmacSha256('AWS4' + secret, date);
    const kRegion = hmacSha256(kDate, reg);
    const kService = hmacSha256(kRegion, service);
    return hmacSha256(kService, 'aws4_request');
}

function s3Request(method, keyPath, body, callback) {
    const now = new Date();
    const amzDate = now.toISOString().replace(/[:-]|\\.\\d{3}/g, '');
    const dateStamp = amzDate.substring(0, 8);
    
    let parsed;
    try {
        parsed = new URL(endpoint);
    } catch (e) {
        return callback(null, new Error('Invalid endpoint URL: ' + endpoint), Buffer.alloc(0));
    }

    let hostHeader = parsed.host;
    let path = parsed.pathname.replace(/\\/+$/, '');
    
    if (forcePathStyle || parsed.hostname === '127.0.0.1' || parsed.hostname === 'localhost' || parsed.port) {
        path += '/' + bucket + (keyPath ? '/' + keyPath : '');
    } else {
        hostHeader = bucket + '.' + parsed.host;
        path += (keyPath ? '/' + keyPath : '/');
    }
    if (!path.startsWith('/')) path = '/' + path;
    
    const payloadHash = crypto.createHash('sha256').update(body || '').digest('hex');
    const headers = {
        'host': hostHeader,
        'x-amz-date': amzDate,
        'x-amz-content-sha256': payloadHash
    };
    if (body && body.length > 0) {
        headers['content-length'] = body.length;
    }
    
    const signedHeaderKeys = Object.keys(headers).sort();
    const canonicalHeaders = signedHeaderKeys.map(k => k + ':' + headers[k] + '\\n').join('');
    const signedHeaders = signedHeaderKeys.join(';');
    
    const canonicalRequest = method + '\\n' + path + '\\n\\n' + canonicalHeaders + '\\n' + signedHeaders + '\\n' + payloadHash;
    const credentialScope = dateStamp + '/' + region + '/s3/aws4_request';
    const stringToSign = 'AWS4-HMAC-SHA256\\n' + amzDate + '\\n' + credentialScope + '\\n' + crypto.createHash('sha256').update(canonicalRequest).digest('hex');
    
    const signingKey = getSigningKey(secretKey, dateStamp, region, 's3');
    const signature = crypto.createHmac('sha256', signingKey).update(stringToSign).digest('hex');
    headers['Authorization'] = 'AWS4-HMAC-SHA256 Credential=' + accessKey + '/' + credentialScope + ', SignedHeaders=' + signedHeaders + ', Signature=' + signature;
    
    const client = parsed.protocol === 'https:' ? https : http;
    const req = client.request({
        protocol: parsed.protocol,
        hostname: parsed.hostname,
        port: parsed.port || (parsed.protocol === 'https:' ? 443 : 80),
        method: method,
        path: path,
        headers: headers,
        timeout: 5000
    }, (res) => {
        const chunks = [];
        res.on('data', d => chunks.push(d));
        res.on('end', () => callback(res, null, Buffer.concat(chunks)));
    });
    
    req.on('timeout', () => {
        req.destroy();
        callback(null, new Error('Request timed out connecting to ' + endpoint), Buffer.alloc(0));
    });
    req.on('error', (err) => callback(null, err, Buffer.alloc(0)));
    if (body) req.write(body);
    req.end();
}

s3Request('GET', '', null, (bucketRes, bucketErr) => {
    if (bucketErr) {
        console.log('FAILED: Cannot connect to S3 endpoint ' + endpoint + ': ' + bucketErr.message);
        process.exit(1);
    }
    if (bucketRes.statusCode === 404) {
        console.log('FAILED: Bucket ' + bucket + ' does not exist on S3 endpoint.');
        process.exit(1);
    }
    if (bucketRes.statusCode === 401 || bucketRes.statusCode === 403) {
        console.log('FAILED: Authentication failed (HTTP ' + bucketRes.statusCode + '). Verify AccessKey and SecretKey.');
        process.exit(1);
    }
    
    s3Request('PUT', testKey, testPayload, (putRes, putErr) => {
        if (putErr) {
            console.log('FAILED: PutObject network error: ' + putErr.message);
            process.exit(1);
        }
        if (putRes.statusCode >= 400) {
            console.log('FAILED: PutObject failed with HTTP ' + putRes.statusCode);
            process.exit(1);
        }
        
        s3Request('GET', testKey, null, (getRes, getErr, getBody) => {
            if (getErr) {
                console.log('FAILED: GetObject network error: ' + getErr.message);
                process.exit(1);
            }
            if (getRes.statusCode >= 400) {
                console.log('FAILED: GetObject failed with HTTP ' + getRes.statusCode);
                process.exit(1);
            }
            if (!getBody || !getBody.equals(testPayload)) {
                console.log('FAILED: GetObject content mismatch.');
                process.exit(1);
            }
            
            s3Request('DELETE', testKey, null, (delRes, delErr) => {
                if (delErr) {
                    console.log('FAILED: DeleteObject network error: ' + delErr.message);
                    process.exit(1);
                }
                if (delRes.statusCode >= 400) {
                    console.log('FAILED: DeleteObject failed with HTTP ' + delRes.statusCode);
                    process.exit(1);
                }
                console.log('SUCCESS: All S3 checks passed! (Connectivity, Auth, PutObject, GetObject, DeleteObject verified)');
                process.exit(0);
            });
        });
    });
});
`;

function runRunner(args) {
    return new Promise((resolve) => {
        const proc = spawn(process.execPath, ['-e', runnerScript, '--', ...args]);
        let out = '';
        proc.stdout.on('data', d => out += d.toString());
        proc.stderr.on('data', d => out += d.toString());
        proc.on('close', (code) => resolve({ code, output: out.trim() }));
    });
}

async function runFullSuite() {
    console.log("=== AFENDOR CHAT: S3 Comprehensive Compatibility Test Suite ===");
    let passed = 0;
    let failed = 0;

    const record = (name, ok, msg) => {
        if (ok) {
            console.log(`[PASS] ${name}`);
            passed++;
        } else {
            console.log(`[FAIL] ${name} -> ${msg}`);
            failed++;
        }
    };

    // 1. Connection Refused / Invalid Port
    const resRefused = await runRunner(['http://127.0.0.1:54321', 'us-east-1', 'KEY', 'SEC', 'bkt', 'true']);
    record("Connection Refused / Port Closed", resRefused.code !== 0 && resRefused.output.includes("Cannot connect to S3 endpoint"), resRefused.output);

    // 2. Invalid URL / Malformed endpoint
    const resBadUrl = await runRunner(['htp//invalid-url', 'us-east-1', 'KEY', 'SEC', 'bkt', 'true']);
    record("Malformed Endpoint URL", resBadUrl.code !== 0 && resBadUrl.output.includes("Invalid endpoint URL"), resBadUrl.output);

    // 3. DNS Failure
    const resDnsFail = await runRunner(['http://non-existent-subdomain-123456789.invalid', 'us-east-1', 'KEY', 'SEC', 'bkt', 'true']);
    record("DNS Failure / Unresolvable Host", resDnsFail.code !== 0 && resDnsFail.output.includes("Cannot connect to S3 endpoint"), resDnsFail.output);

    // 4. Missing required parameters
    const resMissing = await runRunner(['', 'us-east-1', '', '', '', 'true']);
    record("Missing Mandatory Credentials Gating", resMissing.code !== 0 && resMissing.output.includes("Missing required S3 parameters"), resMissing.output);

    // 5. Live Server: Path Style vs Virtual Host Style
    const srv = new MockS3Server({ port: 9301, buckets: ['my-bucket'] });
    await srv.start();
    try {
        const resPath = await runRunner(['http://127.0.0.1:9301', 'us-west-2', 'TESTACCESSKEY', 'TESTSECRETKEY1234567890', 'my-bucket', 'true']);
        record("Path-Style Addressing", resPath.code === 0 && resPath.output.includes("SUCCESS:"), resPath.output);

        const resVhost = await runRunner(['http://127.0.0.1:9301', 'us-west-2', 'TESTACCESSKEY', 'TESTSECRETKEY1234567890', 'my-bucket', 'false']);
        record("Virtual-Host-Style Fallback for IP/Port", resVhost.code === 0 && resVhost.output.includes("SUCCESS:"), resVhost.output);
    } finally {
        await srv.stop();
    }

    // 6. Access Denied on PutObject
    const srvPutFail = new MockS3Server({ port: 9302, buckets: ['my-bucket'], simulateError: 'put_forbidden' });
    await srvPutFail.start();
    try {
        const res = await runRunner(['http://127.0.0.1:9302', 'us-east-1', 'TESTACCESSKEY', 'TESTSECRETKEY1234567890', 'my-bucket', 'true']);
        record("PutObject Permission Denied (HTTP 403)", res.code !== 0 && res.output.includes("PutObject failed with HTTP 403"), res.output);
    } finally {
        await srvPutFail.stop();
    }

    // 7. Access Denied on DeleteObject
    const srvDelFail = new MockS3Server({ port: 9303, buckets: ['my-bucket'], simulateError: 'delete_forbidden' });
    await srvDelFail.start();
    try {
        const res = await runRunner(['http://127.0.0.1:9303', 'us-east-1', 'TESTACCESSKEY', 'TESTSECRETKEY1234567890', 'my-bucket', 'true']);
        record("DeleteObject Permission Denied (HTTP 403)", res.code !== 0 && res.output.includes("DeleteObject failed with HTTP 403"), res.output);
    } finally {
        await srvDelFail.stop();
    }

    console.log(`\nS3 Suite Summary: ${passed} passed, ${failed} failed out of ${passed + failed} tests.`);
    process.exit(failed > 0 ? 1 : 0);
}

runFullSuite();

