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

console.log('=== Checking Shell Script Syntax & Structural Balance ===');
let failed = 0;
let passed = 0;

for (const rel of scripts) {
    const full = path.join(ROOT, rel);
    if (!fs.existsSync(full)) {
        console.log(`[FAIL] Missing script: ${rel}`);
        failed++;
        continue;
    }

    const content = fs.readFileSync(full, 'utf8');
    const lines = content.split(/\r?\n/);

    if (!lines[0].startsWith('#!/usr/bin/env bash') && !lines[0].startsWith('#!/bin/bash')) {
        console.log(`[FAIL] ${rel}: Missing bash shebang on line 1`);
        failed++;
        continue;
    }

    let inHeredoc = false;
    let heredocDelim = '';
    let inMultilinePython = false;

    let openIf = 0;
    let closeFi = 0;
    let openCase = 0;
    let closeEsac = 0;
    let openBrace = 0;
    let closeBrace = 0;

    for (let i = 0; i < lines.length; i++) {
        const line = lines[i];
        const trimmed = line.trim();

        // Handle heredoc boundaries
        if (inHeredoc) {
            if (trimmed === heredocDelim) {
                inHeredoc = false;
                heredocDelim = '';
            }
            continue;
        }

        const heredocMatch = line.match(/<<\s*['"]?([A-Za-z0-9_-]+)['"]?/);
        if (heredocMatch && !line.includes('sed ') && !line.includes('grep ')) {
            inHeredoc = true;
            heredocDelim = heredocMatch[1];
            continue;
        }

        // Handle python3 -c " multi-line
        if (line.includes('python3 -c "') && !line.endsWith('"') && !line.endsWith('";')) {
            inMultilinePython = true;
            continue;
        }
        if (inMultilinePython) {
            if (trimmed.endsWith('"') || trimmed.endsWith('";') || trimmed.includes('" 2>/dev/null')) {
                inMultilinePython = false;
            }
            continue;
        }

        if (trimmed.startsWith('#')) continue;

        // Strip comments
        const noComment = line.replace(/#.*$/, '');

        // Check if / fi
        const ifMatch = noComment.match(/\bif\s+/g);
        if (ifMatch) openIf += ifMatch.length;
        const fiMatch = noComment.match(/\bfi\b/g);
        if (fiMatch) closeFi += fiMatch.length;

        // Check case / esac
        const caseMatch = noComment.match(/\bcase\s+.*in\b/g);
        if (caseMatch) openCase += caseMatch.length;
        const esacMatch = noComment.match(/\besac\b/g);
        if (esacMatch) closeEsac += esacMatch.length;

        // Check function / block braces { } and variable expansions ${ }
        // Exclude string literals
        const cleanLine = noComment.replace(/"[^"]*"/g, '').replace(/'[^']*'/g, '');
        for (let j = 0; j < cleanLine.length; j++) {
            const ch = cleanLine[j];
            if (ch === '{') openBrace++;
            if (ch === '}') closeBrace++;
        }
    }

    if (openBrace !== closeBrace) {
        console.log(`[FAIL] ${rel}: Unbalanced braces! ({: ${openBrace}, }: ${closeBrace})`);
        failed++;
    } else if (openIf !== closeFi) {
        console.log(`[FAIL] ${rel}: Unbalanced if/fi! (if: ${openIf}, fi: ${closeFi})`);
        failed++;
    } else if (openCase !== closeEsac) {
        console.log(`[FAIL] ${rel}: Unbalanced case/esac! (case: ${openCase}, esac: ${closeEsac})`);
        failed++;
    } else {
        console.log(`[PASS] ${rel} (${lines.length} lines, braces: ${openBrace}/${closeBrace}, if/fi: ${openIf}/${closeFi})`);
        passed++;
    }
}

console.log(`\nSyntax Audit: ${passed} passed, ${failed} failed out of ${scripts.length} scripts.`);
process.exit(failed > 0 ? 1 : 0);
