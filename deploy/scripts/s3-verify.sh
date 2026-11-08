#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later
# ==============================================================================
# AFENDOR CHAT - GENERIC S3-COMPATIBLE STORAGE VERIFICATION UTILITY
# Tests: Endpoint connectivity, SigV4 Auth, Bucket access, PutObject, GetObject, DeleteObject
# Works with: AWS S3, Backblaze B2, Cloudflare R2, MinIO, Wasabi, DigitalOcean Spaces
# Location: /opt/afendorchat/deploy/scripts/s3-verify.sh
# ==============================================================================

set -euo pipefail

ENDPOINT=""
REGION="us-east-1"
ACCESS_KEY=""
SECRET_KEY=""
BUCKET=""
FORCE_PATH_STYLE="false"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

while [[ $# -gt 0 ]]; do
    case "$1" in
        --endpoint)
            ENDPOINT="$2"
            shift 2
            ;;
        --region)
            REGION="$2"
            shift 2
            ;;
        --access-key)
            ACCESS_KEY="$2"
            shift 2
            ;;
        --secret-key)
            SECRET_KEY="$2"
            shift 2
            ;;
        --bucket)
            BUCKET="$2"
            shift 2
            ;;
        --force-path-style)
            FORCE_PATH_STYLE="$2"
            shift 2
            ;;
        *)
            echo "Unknown argument: $1" >&2
            exit 1
            ;;
    esac
done

if [ -z "${ENDPOINT}" ] || [ -z "${ACCESS_KEY}" ] || [ -z "${SECRET_KEY}" ] || [ -z "${BUCKET}" ]; then
    echo -e "${RED}[ERROR] Missing mandatory S3 arguments. Required: --endpoint, --access-key, --secret-key, --bucket${NC}" >&2
    exit 1
fi

# Clean trailing slashes from endpoint
ENDPOINT="${ENDPOINT%/}"

echo -e "  Testing endpoint: ${CYAN}${ENDPOINT}${NC} (Bucket: ${BOLD}${BUCKET}${NC}, Region: ${REGION})"

# Execute verification using pure Python3 stdlib (urllib + hashlib + hmac)
# Zero external package dependencies (no boto3 or pip required)
PYTHON_CODE=$(cat <<'EOF'
import sys, os, urllib.request, urllib.error, urllib.parse, hashlib, hmac, datetime, uuid

endpoint = sys.argv[1].rstrip('/')
region = sys.argv[2] or 'us-east-1'
access_key = sys.argv[3]
secret_key = sys.argv[4]
bucket = sys.argv[5]
force_path_style = sys.argv[6].lower() == 'true'

# Determine Host and URL path
# Path style: https://endpoint/bucket/key
# Virtual host: https://bucket.endpoint/key
parsed_ep = urllib.parse.urlparse(endpoint)
scheme = parsed_ep.scheme or 'https'
netloc = parsed_ep.netloc or endpoint.replace('https://', '').replace('http://', '')
base_path = parsed_ep.path.rstrip('/')

def sign(key, msg):
    return hmac.new(key, msg.encode('utf-8'), hashlib.sha256).digest()

def get_signature_key(key, date_stamp, region_name, service_name):
    k_date = sign(('AWS4' + key).encode('utf-8'), date_stamp)
    k_region = sign(k_date, region_name)
    k_service = sign(k_region, service_name)
    k_signing = sign(k_service, 'aws4_request')
    return k_signing

def make_s3_request(method, key_name='', body=b'', headers_extra=None):
    now = datetime.datetime.now(datetime.timezone.utc)
    amz_date = now.strftime('%Y%m%dT%H%M%SZ')
    date_stamp = now.strftime('%Y%m%d')

    if force_path_style:
        host_header = netloc
        if key_name:
            uri = f"{base_path}/{bucket}/{key_name}"
        else:
            uri = f"{base_path}/{bucket}"
        full_url = f"{scheme}://{netloc}{uri}"
    else:
        # Virtual hosted style: bucket.netloc
        # If netloc already has port or is ip, fallback to path style
        if ':' in netloc or netloc.replace('.', '').isdigit():
            host_header = netloc
            uri = f"{base_path}/{bucket}/{key_name}" if key_name else f"{base_path}/{bucket}"
            full_url = f"{scheme}://{netloc}{uri}"
        else:
            host_header = f"{bucket}.{netloc}"
            uri = f"{base_path}/{key_name}" if key_name else f"{base_path}/"
            full_url = f"{scheme}://{host_header}{uri}"

    payload_hash = hashlib.sha256(body).hexdigest()
    
    headers = {
        'host': host_header,
        'x-amz-date': amz_date,
        'x-amz-content-sha256': payload_hash,
    }
    if headers_extra:
        headers.update(headers_extra)

    # Canonical headers
    signed_header_keys = sorted(headers.keys())
    canonical_headers = "".join([f"{k}:{headers[k]}\n" for k in signed_header_keys])
    signed_headers_str = ";".join(signed_header_keys)

    canonical_request = f"{method}\n{uri}\n\n{canonical_headers}\n{signed_headers_str}\n{payload_hash}"
    algorithm = 'AWS4-HMAC-SHA256'
    credential_scope = f"{date_stamp}/{region}/s3/aws4_request"
    string_to_sign = f"{algorithm}\n{amz_date}\n{credential_scope}\n{hashlib.sha256(canonical_request.encode('utf-8')).hexdigest()}"

    signing_key = get_signature_key(secret_key, date_stamp, region, 's3')
    signature = hmac.new(signing_key, string_to_sign.encode('utf-8'), hashlib.sha256).hexdigest()

    auth_header = f"{algorithm} Credential={access_key}/{credential_scope}, SignedHeaders={signed_headers_str}, Signature={signature}"
    headers['Authorization'] = auth_header

    req = urllib.request.Request(full_url, data=body if method in ('PUT', 'POST') else None, headers=headers, method=method)
    return req

# TEST 1: Check bucket access (HEAD or GET on bucket)
try:
    req = make_s3_request('GET', '')
    with urllib.request.urlopen(req, timeout=10) as resp:
        if resp.status not in (200, 204):
            print(f"FAILED: Bucket check returned unexpected status {resp.status}")
            sys.exit(2)
except urllib.error.HTTPError as e:
    if e.code == 404:
        print(f"FAILED: Bucket '{bucket}' does not exist on this S3 endpoint.")
        sys.exit(3)
    elif e.code in (401, 403):
        print(f"FAILED: Authentication/Permission Denied (HTTP {e.code}). Verify your Access Key and Secret Key.")
        sys.exit(4)
    else:
        # Some providers allow PutObject even if ListBucket is forbidden
        pass
except urllib.error.URLError as e:
    print(f"FAILED: Cannot connect to S3 endpoint '{endpoint}': {e.reason}")
    sys.exit(1)
except Exception as e:
    print(f"FAILED: Endpoint error: {str(e)}")
    sys.exit(1)

# TEST 2: Upload Test Object (PutObject)
test_key = f"afendor_verify_test_{uuid.uuid4().hex[:8]}.txt"
test_content = b"AFENDOR_CHAT_S3_VERIFICATION_PAYLOAD_OK"
try:
    req = make_s3_request('PUT', test_key, body=test_content, headers_extra={'content-type': 'text/plain'})
    with urllib.request.urlopen(req, timeout=12) as resp:
        if resp.status not in (200, 201, 204):
            print(f"FAILED: PutObject returned HTTP {resp.status}")
            sys.exit(5)
except urllib.error.HTTPError as e:
    print(f"FAILED: Upload permission denied on bucket '{bucket}' (HTTP {e.code}): {e.reason}")
    sys.exit(5)
except Exception as e:
    print(f"FAILED: Upload failed: {str(e)}")
    sys.exit(5)

# TEST 3: Download & Content Verification (GetObject)
try:
    req = make_s3_request('GET', test_key)
    with urllib.request.urlopen(req, timeout=12) as resp:
        downloaded = resp.read()
        if downloaded != test_content:
            print(f"FAILED: Download content mismatch. Uploaded {len(test_content)} bytes, got {len(downloaded)} bytes.")
            sys.exit(6)
except Exception as e:
    print(f"FAILED: GetObject failed: {str(e)}")
    sys.exit(6)

# TEST 4: Cleanup Test Object (DeleteObject)
try:
    req = make_s3_request('DELETE', test_key)
    with urllib.request.urlopen(req, timeout=10) as resp:
        pass
except Exception as e:
    print(f"FAILED: DeleteObject failed (missing delete permissions on bucket): {str(e)}")
    sys.exit(7)

print("SUCCESS: All S3 checks passed! (Connectivity, Auth, PutObject, GetObject, DeleteObject verified)")
sys.exit(0)
EOF
)

# Run verification via python3 or fallback to Node.js
if command -v python3 &>/dev/null; then
    OUTPUT=$(python3 -c "${PYTHON_CODE}" "${ENDPOINT}" "${REGION}" "${ACCESS_KEY}" "${SECRET_KEY}" "${BUCKET}" "${FORCE_PATH_STYLE}" 2>&1 || true)
    if echo "${OUTPUT}" | grep -q "SUCCESS:"; then
        echo -e "  [${GREEN}PASS${NC}] ${OUTPUT}"
        exit 0
    else
        echo -e "  [${RED}FAIL${NC}] ${OUTPUT}"
        exit 1
    fi
else
    # Node.js fallback runner using pure Node standard library
    NODE_CODE=$(cat <<'EOF'
const crypto = require('crypto');
const https = require('https');
const http = require('http');

const argv = process.argv.slice(1).filter(a => a !== '--' && a !== '[eval]' && !a.endsWith('node.exe') && !a.endsWith('node'));
const cleanArgs = argv[0] && (argv[0].startsWith('http://') || argv[0].startsWith('https://')) ? argv : argv.slice(1);
const endpoint = (cleanArgs[0] || '').replace(/\/+$/, '');
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
    const amzDate = now.toISOString().replace(/[:-]|\.\d{3}/g, '');
    const dateStamp = amzDate.substring(0, 8);
    
    let parsed;
    try {
        parsed = new URL(endpoint);
    } catch (e) {
        return callback(null, new Error('Invalid endpoint URL: ' + endpoint), Buffer.alloc(0));
    }

    let hostHeader = parsed.host;
    let path = parsed.pathname.replace(/\/+$/, '');
    
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
    const canonicalHeaders = signedHeaderKeys.map(k => k + ':' + headers[k] + '\n').join('');
    const signedHeaders = signedHeaderKeys.join(';');
    
    const canonicalRequest = method + '\n' + path + '\n\n' + canonicalHeaders + '\n' + signedHeaders + '\n' + payloadHash;
    const credentialScope = dateStamp + '/' + region + '/s3/aws4_request';
    const stringToSign = 'AWS4-HMAC-SHA256\n' + amzDate + '\n' + credentialScope + '\n' + crypto.createHash('sha256').update(canonicalRequest).digest('hex');
    
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
        timeout: 10000
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
            console.log('FAILED: PutObject failed with HTTP ' + putRes.statusCode + '. Check bucket write permissions.');
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
                console.log('FAILED: GetObject content mismatch. Uploaded ' + testPayload.length + ' bytes, read ' + (getBody ? getBody.length : 0) + ' bytes.');
                process.exit(1);
            }
            
            s3Request('DELETE', testKey, null, (delRes, delErr) => {
                if (delErr) {
                    console.log('FAILED: DeleteObject network error: ' + delErr.message);
                    process.exit(1);
                }
                if (delRes.statusCode >= 400) {
                    console.log('FAILED: DeleteObject failed with HTTP ' + delRes.statusCode + '. Check bucket delete permissions.');
                    process.exit(1);
                }
                console.log('SUCCESS: All S3 checks passed! (Connectivity, Auth, PutObject, GetObject, DeleteObject verified)');
                process.exit(0);
            });
        });
    });
});
EOF
)
    OUTPUT=$(node -e "${NODE_CODE}" -- "${ENDPOINT}" "${REGION}" "${ACCESS_KEY}" "${SECRET_KEY}" "${BUCKET}" "${FORCE_PATH_STYLE}" 2>&1 || true)
    if echo "${OUTPUT}" | grep -q "SUCCESS:"; then
        echo -e "  [${GREEN}PASS${NC}] ${OUTPUT}"
        exit 0
    else
        echo -e "  [${RED}FAIL${NC}] ${OUTPUT}"
        exit 1
    fi
fi

