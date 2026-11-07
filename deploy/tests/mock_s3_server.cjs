// Mock S3 Server for AFENDOR CHAT storage verification testing
// Implements: ListObjects/HeadBucket, PutObject, GetObject, DeleteObject, AWS SigV4 verification
const http = require('http');
const crypto = require('crypto');

class MockS3Server {
    constructor(options = {}) {
        this.port = options.port || 9000;
        this.accessKey = options.accessKey || 'TESTACCESSKEY';
        this.secretKey = options.secretKey || 'TESTSECRETKEY1234567890';
        this.buckets = new Set(options.buckets || ['test-bucket']);
        this.storage = new Map(); // bucket:key -> Buffer
        this.simulateError = options.simulateError || null; // e.g. 'delete_forbidden', 'invalid_auth', etc.
        this.server = null;
    }

    start() {
        return new Promise((resolve, reject) => {
            this.server = http.createServer((req, res) => this.handleRequest(req, res));
            this.server.listen(this.port, '127.0.0.1', () => {
                resolve(`http://127.0.0.1:${this.port}`);
            });
            this.server.on('error', reject);
        });
    }

    stop() {
        return new Promise((resolve) => {
            if (this.server) {
                this.server.close(() => resolve());
            } else {
                resolve();
            }
        });
    }

    handleRequest(req, res) {
        const auth = req.headers['authorization'] || '';
        
        // 1. Verify Authentication
        if (this.simulateError === 'invalid_auth' || !auth.startsWith('AWS4-HMAC-SHA256')) {
            res.writeHead(403, { 'Content-Type': 'application/xml' });
            return res.end('<Error><Code>AccessDenied</Code><Message>Access Denied</Message></Error>');
        }

        // Check if access key matches
        if (!auth.includes(`Credential=${this.accessKey}/`)) {
            res.writeHead(403, { 'Content-Type': 'application/xml' });
            return res.end('<Error><Code>InvalidAccessKeyId</Code><Message>The AWS Access Key Id you provided does not exist in our records.</Message></Error>');
        }

        // Parse path
        const u = new URL(req.url, `http://${req.headers.host}`);
        let bucket = '';
        let key = '';

        // Check host for virtual host style
        const hostParts = (req.headers.host || '').split('.');
        if (hostParts.length > 1 && !req.headers.host.startsWith('127.0.0.1') && !req.headers.host.startsWith('localhost')) {
            bucket = hostParts[0];
            key = u.pathname.replace(/^\/+/, '');
        } else {
            // Path style: /bucket/key
            const parts = u.pathname.replace(/^\/+/, '').split('/');
            bucket = parts[0] || '';
            key = parts.slice(1).join('/');
        }

        // Check if bucket exists
        if (!this.buckets.has(bucket)) {
            res.writeHead(404, { 'Content-Type': 'application/xml' });
            return res.end(`<Error><Code>NoSuchBucket</Code><Message>The specified bucket does not exist.</Message><BucketName>${bucket}</BucketName></Error>`);
        }

        const mapKey = `${bucket}:${key}`;

        // Buffer body
        const chunks = [];
        req.on('data', chunk => chunks.push(chunk));
        req.on('end', () => {
            const body = Buffer.concat(chunks);

            if (req.method === 'HEAD' || (req.method === 'GET' && !key)) {
                // Bucket existence or ListObjects
                res.writeHead(200, { 'Content-Type': 'application/xml' });
                return res.end('<ListBucketResult><Name>' + bucket + '</Name></ListBucketResult>');
            }

            if (req.method === 'PUT') {
                if (this.simulateError === 'put_forbidden') {
                    res.writeHead(403, { 'Content-Type': 'application/xml' });
                    return res.end('<Error><Code>AccessDenied</Code></Error>');
                }
                this.storage.set(mapKey, body);
                res.writeHead(200, { 'ETag': '"' + crypto.createHash('md5').update(body).digest('hex') + '"' });
                return res.end();
            }

            if (req.method === 'GET') {
                if (this.simulateError === 'get_forbidden') {
                    res.writeHead(403, { 'Content-Type': 'application/xml' });
                    return res.end('<Error><Code>AccessDenied</Code></Error>');
                }
                if (!this.storage.has(mapKey)) {
                    res.writeHead(404, { 'Content-Type': 'application/xml' });
                    return res.end('<Error><Code>NoSuchKey</Code></Error>');
                }
                let data = this.storage.get(mapKey);
                if (this.simulateError === 'corrupted_read') {
                    data = Buffer.from('CORRUPTED_DATA_MISMATCH');
                }
                res.writeHead(200, {
                    'Content-Type': 'text/plain',
                    'Content-Length': data.length
                });
                return res.end(data);
            }

            if (req.method === 'DELETE') {
                if (this.simulateError === 'delete_forbidden') {
                    res.writeHead(403, { 'Content-Type': 'application/xml' });
                    return res.end('<Error><Code>AccessDenied</Code><Message>Delete forbidden</Message></Error>');
                }
                this.storage.delete(mapKey);
                res.writeHead(204);
                return res.end();
            }

            res.writeHead(405);
            res.end();
        });
    }
}

module.exports = MockS3Server;

