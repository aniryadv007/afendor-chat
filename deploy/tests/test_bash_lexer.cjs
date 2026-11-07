const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '../..');
const scripts = [
    'deploy/bin/afendorctl',
    'deploy/install.sh',
    'deploy/scripts/backup.sh',
    'deploy/scripts/dns-verify.sh',
    'deploy/scripts/doctor.sh',
    'deploy/scripts/healthcheck.sh',
    'deploy/scripts/nginx-manage.sh',
    'deploy/scripts/restore.sh',
    'deploy/scripts/rollback.sh',
    'deploy/scripts/s3-verify.sh',
    'deploy/scripts/ssl-manage.sh',
    'deploy/scripts/status.sh',
    'deploy/scripts/update.sh'
];

function tokenizeBash(content) {
    let i = 0;
    const len = content.length;
    let state = 'NORMAL'; // NORMAL, SQUOTE, DQUOTE, HEREDOC, COMMENT
    let heredocMarker = '';
    let tokens = [];
    let curWord = '';

    while (i < len) {
        const ch = content[i];
        const next = i + 1 < len ? content[i + 1] : '';

        if (state === 'NORMAL') {
            if (ch === '\\') {
                i += 2; // skip escape
                continue;
            }
            if (ch === '#' && (i === 0 || /\s/.test(content[i - 1]))) {
                state = 'COMMENT';
                i++;
                continue;
            }
            if (ch === '\'') {
                state = 'SQUOTE';
                i++;
                continue;
            }
            if (ch === '"') {
                state = 'DQUOTE';
                i++;
                continue;
            }
            if (ch === '<' && next === '<') {
                // Check heredoc: <<EOF or <<'EOF'
                let rest = content.slice(i);
                let match = rest.match(/^<<-?\s*['"]?([A-Za-z0-9_-]+)['"]?/);
                if (match) {
                    heredocMarker = match[1];
                    // Skip to newline
                    let nl = content.indexOf('\n', i);
                    if (nl !== -1) {
                        i = nl + 1;
                        state = 'HEREDOC';
                        continue;
                    }
                }
            }
            if (/\s/.test(ch)) {
                if (curWord) {
                    tokens.push(curWord);
                    curWord = '';
                }
            } else if (['{', '}', '(', ')', ';'].includes(ch)) {
                if (curWord) {
                    tokens.push(curWord);
                    curWord = '';
                }
                tokens.push(ch);
            } else {
                curWord += ch;
            }
            i++;
        } else if (state === 'COMMENT') {
            if (ch === '\n') {
                state = 'NORMAL';
            }
            i++;
        } else if (state === 'SQUOTE') {
            if (ch === '\'') {
                state = 'NORMAL';
            }
            i++;
        } else if (state === 'DQUOTE') {
            if (ch === '\\') {
                i += 2; // skip escape inside double quote
                continue;
            }
            if (ch === '"') {
                state = 'NORMAL';
            }
            i++;
        } else if (state === 'HEREDOC') {
            if (ch === '\n') {
                let rest = content.slice(i + 1);
                let nl = rest.indexOf('\n');
                let line = nl === -1 ? rest : rest.slice(0, nl);
                if (line.trim() === heredocMarker) {
                    state = 'NORMAL';
                    i = i + 1 + (nl === -1 ? rest.length : nl + 1);
                    continue;
                }
            }
            i++;
        }
    }
    if (curWord) tokens.push(curWord);
    return tokens;
}

console.log('=== Executing Real Bash State-Machine Lexer on All Scripts ===');
let failed = 0;
let passed = 0;

for (const rel of scripts) {
    const full = path.join(ROOT, rel);
    if (!fs.existsSync(full)) {
        console.log(`[FAIL] File missing: ${rel}`);
        failed++;
        continue;
    }
    const content = fs.readFileSync(full, 'utf8');
    const tokens = tokenizeBash(content);

    let ifCount = 0;
    let fiCount = 0;
    let caseCount = 0;
    let esacCount = 0;
    let braceCount = 0;

    for (const t of tokens) {
        if (t === 'if') ifCount++;
        if (t === 'fi') fiCount++;
        if (t === 'case') caseCount++;
        if (t === 'esac') esacCount++;
        if (t === '{') braceCount++;
        if (t === '}') braceCount--;
    }

    if (ifCount !== fiCount) {
        console.log(`[FAIL] ${rel}: Unbalanced if/fi! (if: ${ifCount}, fi: ${fiCount})`);
        failed++;
    } else if (caseCount !== esacCount) {
        console.log(`[FAIL] ${rel}: Unbalanced case/esac! (case: ${caseCount}, esac: ${esacCount})`);
        failed++;
    } else if (braceCount !== 0) {
        console.log(`[FAIL] ${rel}: Unbalanced braces! (remainder: ${braceCount})`);
        failed++;
    } else {
        console.log(`[PASS] ${rel} -> Lexically balanced (if/fi: ${ifCount}/${fiCount}, case/esac: ${caseCount}/${esacCount})`);
        passed++;
    }
}

console.log(`\nLexer Audit: ${passed} passed, ${failed} failed out of ${scripts.length} scripts.`);
process.exit(failed > 0 ? 1 : 0);
