// SPDX-License-Identifier: AGPL-3.0-or-later
import * as fs from 'node:fs';
import * as path from 'node:path';
import * as crypto from 'node:crypto';
import { execFileSync } from 'node:child_process';

const ROOT_DIR = path.resolve('.');
const VERSION = '1.0.0';
const RELEASE_DIR = path.join(ROOT_DIR, 'releases', 'afendor-chat', VERSION, 'windows');
const LEGACY_RELEASE_DIR = path.join(ROOT_DIR, 'releases', 'afendor-chat', '0.0.0', 'windows');
const UNPACKED_DIR = path.join(ROOT_DIR, 'afendor_desktop', 'dist-electron', 'win-unpacked');
const VENDOR_DIR = path.join(ROOT_DIR, '.velopack', 'extracted', 'vendor');

console.log(`Packaging AFENDOR CHAT desktop release v${VERSION} for Windows x64...`);
fs.mkdirSync(RELEASE_DIR, { recursive: true });
fs.mkdirSync(LEGACY_RELEASE_DIR, { recursive: true });

// 1. Standalone portable executable
const portableExeTarget = path.join(RELEASE_DIR, `Afendor-Chat-${VERSION}-win-x64.exe`);
const sourceExe = path.join(UNPACKED_DIR, 'Afendor Chat.exe');
console.log('1. Copying standalone portable executable...');
fs.copyFileSync(sourceExe, portableExeTarget);

// 2. Portable archive (.zip)
const portableZip = path.join(RELEASE_DIR, `Afendor-Chat-${VERSION}-win-x64-portable.zip`);
console.log('2. Creating portable ZIP archive...');
if (fs.existsSync(portableZip)) fs.rmSync(portableZip);
execFileSync('tar.exe', ['-a', '-c', '-f', portableZip, '*'], {
    cwd: UNPACKED_DIR,
    stdio: 'inherit'
});

// 3. Velopack Full Update Package (.nupkg)
const nupkgTarget = path.join(RELEASE_DIR, `Afendor-Chat-${VERSION}-win-x64-full.nupkg`);
console.log('3. Assembling Velopack full update package (.nupkg)...');
const stagingDir = path.join(ROOT_DIR, 'releases', '.nupkg-stage');
fs.rmSync(stagingDir, { recursive: true, force: true });
fs.mkdirSync(path.join(stagingDir, 'lib', 'app'), { recursive: true });
fs.mkdirSync(path.join(stagingDir, '_rels'), { recursive: true });

// Copy app contents into lib/app
fs.cpSync(UNPACKED_DIR, path.join(stagingDir, 'lib', 'app'), { recursive: true });

// Copy Velopack binaries into lib/app
fs.copyFileSync(path.join(VENDOR_DIR, 'stub.exe'), path.join(stagingDir, 'lib', 'app', 'Afendor Chat_ExecutionStub.exe'));
fs.copyFileSync(path.join(VENDOR_DIR, 'update.exe'), path.join(stagingDir, 'lib', 'app', 'Squirrel.exe'));

// Write nuspec
const nuspecContent = `<?xml version="1.0" encoding="utf-8"?>
<package xmlns="http://schemas.microsoft.com/packaging/2010/07/nuspec.xsd">
<metadata>
<id>afendor_desktop</id>
<title>Afendor Chat</title>
<description>Afendor Chat - Instant messaging and VoIP application</description>
<authors>Afendor Chat</authors>
<version>${VERSION}</version>
<channel>win</channel>
<mainExe>Afendor Chat.exe</mainExe>
<os>win</os>
<rid>win-x64</rid>
<shortcutLocations>StartMenu,Desktop</shortcutLocations>
<shortcutAumid>velopack.afendor_desktop</shortcutAumid>
<machineArchitecture>x64</machineArchitecture>
</metadata>
</package>`;
fs.writeFileSync(path.join(stagingDir, 'afendor_desktop.nuspec'), nuspecContent, 'utf8');
fs.writeFileSync(path.join(stagingDir, 'lib', 'app', 'sq.version'), nuspecContent, 'utf8');

const contentTypes = `<?xml version="1.0" encoding="utf-8"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml" />
  <Default Extension="nuspec" ContentType="application/octet" />
  <Default Extension="ico" ContentType="application/octet" />
  <Default Extension="pak" ContentType="application/octet" />
  <Default Extension="dll" ContentType="application/octet" />
  <Default Extension="exe" ContentType="application/octet" />
  <Default Extension="dat" ContentType="application/octet" />
  <Default Extension="txt" ContentType="application/octet" />
  <Default Extension="html" ContentType="application/octet" />
  <Default Extension="bin" ContentType="application/octet" />
  <Default Extension="version" ContentType="application/octet" />
  <Default Extension="json" ContentType="application/octet" />
  <Default Extension="asar" ContentType="application/octet" />
  <Default Extension="png" ContentType="application/octet" />
  <Default Extension="xml" ContentType="application/octet" />
  <Default Extension="js" ContentType="application/octet" />
  <Default Extension="woff2" ContentType="application/octet" />
  <Default Extension="css" ContentType="application/octet" />
  <Default Extension="mp3" ContentType="application/octet" />
  <Default Extension="avif" ContentType="application/octet" />
  <Default Extension="wasm" ContentType="application/octet" />
  <Default Extension="webp" ContentType="application/octet" />
  <Default Extension="svg" ContentType="application/octet" />
  <Default Extension="mjs" ContentType="application/octet" />
  <Default Extension="ogg" ContentType="application/octet" />
  <Default Extension="node" ContentType="application/octet" />
</Types>`;
fs.writeFileSync(path.join(stagingDir, '[Content_Types].xml'), contentTypes, 'utf8');

const relsContent = `<?xml version="1.0" encoding="utf-8"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Type="http://schemas.microsoft.com/packaging/2010/07/manifest" Target="/afendor_desktop.nuspec" Id="R1" />
</Relationships>`;
fs.writeFileSync(path.join(stagingDir, '_rels', '.rels'), relsContent, 'utf8');

// Build nupkg using .NET ZipArchive to guarantee OPC-compliant entry order & POSIX '/' paths
console.log('Compressing .nupkg package with OPC compliance...');
const psNupkgScript = `
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$outZip = "${nupkgTarget.replace(/\\/g, '/')}"
if (Test-Path $outZip) { Remove-Item $outZip }

$zip = [System.IO.Compression.ZipFile]::Open($outZip, [System.IO.Compression.ZipArchiveMode]::Create)

function Add-FileEntry($archive, $filePath, $entryPath) {
    $entry = $archive.CreateEntry($entryPath, [System.IO.Compression.CompressionLevel]::Optimal)
    $stream = $entry.Open()
    $fs = [System.IO.File]::OpenRead($filePath)
    $fs.CopyTo($stream)
    $fs.Close()
    $stream.Close()
}

# 1. [Content_Types].xml (Must be first for OPC readers)
Add-FileEntry $zip "${path.join(stagingDir, '[Content_Types].xml').replace(/\\/g, '/')}" "[Content_Types].xml"

# 2. afendor_desktop.nuspec
Add-FileEntry $zip "${path.join(stagingDir, 'afendor_desktop.nuspec').replace(/\\/g, '/')}" "afendor_desktop.nuspec"

# 3. _rels/.rels
Add-FileEntry $zip "${path.join(stagingDir, '_rels', '.rels').replace(/\\/g, '/')}" "_rels/.rels"

# 4. lib/app/sq.version
Add-FileEntry $zip "${path.join(stagingDir, 'lib', 'app', 'sq.version').replace(/\\/g, '/')}" "lib/app/sq.version"

# 5. Add all other files under lib/app recursively
$stageDir = "${stagingDir.replace(/\\/g, '/')}"
$files = Get-ChildItem -Path "$stageDir/lib/app" -Recurse -File
foreach ($file in $files) {
    $relPath = $file.FullName.Substring($stageDir.Length + 1).Replace('\\', '/')
    if ($relPath -ne "lib/app/sq.version") {
        Add-FileEntry $zip $file.FullName $relPath
    }
}

$zip.Dispose()
`;
const nupkgPs1 = path.join(ROOT_DIR, 'scratch', 'build_release_nupkg.ps1');
fs.writeFileSync(nupkgPs1, psNupkgScript, 'utf8');
execFileSync('powershell.exe', ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', nupkgPs1]);
fs.rmSync(stagingDir, { recursive: true, force: true });
console.log(`Nupkg created (${(fs.statSync(nupkgTarget).size / 1024 / 1024).toFixed(2)} MB).`);

// Also create legacy alias
const legacyNupkg = path.join(RELEASE_DIR, `afendor_desktop-${VERSION}-full.nupkg`);
fs.copyFileSync(nupkgTarget, legacyNupkg);

// 4. Setup installer executable (with embedded Velopack bundle)
console.log('4. Creating Setup.exe and versioned installer with embedded Velopack bundle...');
const vendorSetup = path.join(VENDOR_DIR, 'setup.exe');
const setupExe = path.join(RELEASE_DIR, 'Setup.exe');
const versionedSetup = path.join(RELEASE_DIR, `Afendor-Chat-${VERSION}-win-x64-Setup.exe`);

const sig = Buffer.from([
  0x94, 0xf0, 0xb1, 0x7b, 0x68, 0x93, 0xe0, 0x29,
  0x37, 0xeb, 0x34, 0xef, 0x53, 0xaa, 0xe7, 0xd4,
  0x2b, 0x54, 0xf5, 0x70, 0x7e, 0xf5, 0xd6, 0xf5,
  0x78, 0x54, 0x98, 0x3e, 0x5e, 0x94, 0xed, 0x7d
]);

const setupBuf = fs.readFileSync(vendorSetup);
const sigIdx = setupBuf.indexOf(sig);
if (sigIdx === -1) {
    throw new Error('SquirrelBundleSignature not found in vendor/setup.exe');
}

const bundleOffset = BigInt(setupBuf.length);
const nupkgBuf = fs.readFileSync(nupkgTarget);
const bundleLength = BigInt(nupkgBuf.length);

const headerBuf = Buffer.from(setupBuf);
headerBuf.writeBigUInt64LE(bundleOffset, sigIdx - 16);
headerBuf.writeBigUInt64LE(bundleLength, sigIdx - 8);

const out = fs.openSync(setupExe, 'w');
fs.writeSync(out, headerBuf);
fs.writeSync(out, nupkgBuf);
fs.closeSync(out);

fs.copyFileSync(setupExe, versionedSetup);
console.log(`Setup.exe created with embedded bundle (${(fs.statSync(setupExe).size / 1024 / 1024).toFixed(2)} MB).`);

// 5. Calculate Hashes and Generate Manifests (releases.win.json & RELEASES)
console.log('5. Calculating hashes and writing manifests...');
function getHashes(filePath) {
    const data = fs.readFileSync(filePath);
    return {
        size: data.length,
        sha1: crypto.createHash('sha1').update(data).digest('hex'),
        sha256: crypto.createHash('sha256').update(data).digest('hex')
    };
}

const nupkgInfo = getHashes(nupkgTarget);
const releasesWinJson = {
    Assets: [
        {
            PackageId: 'afendor_desktop',
            Version: VERSION,
            Type: 'Full',
            FileName: path.basename(nupkgTarget),
            SHA1: nupkgInfo.sha1,
            SHA256: nupkgInfo.sha256,
            Size: nupkgInfo.size
        }
    ]
};
fs.writeFileSync(path.join(RELEASE_DIR, 'releases.win.json'), JSON.stringify(releasesWinJson, null, 2) + '\n', 'utf8');

const releasesLegacy = `${nupkgInfo.sha1} ${path.basename(nupkgTarget)} ${nupkgInfo.size}\n`;
fs.writeFileSync(path.join(RELEASE_DIR, 'RELEASES'), releasesLegacy, 'utf8');

// 6. SHA256SUMS for all files in release directory
console.log('6. Generating SHA256SUMS manifest...');
const files = fs.readdirSync(RELEASE_DIR).filter(f => f !== 'SHA256SUMS').sort();
let sha256Lines = [];
for (const file of files) {
    const fullPath = path.join(RELEASE_DIR, file);
    const hash = crypto.createHash('sha256').update(fs.readFileSync(fullPath)).digest('hex');
    sha256Lines.push(`${hash}  ${file}`);
}
fs.writeFileSync(path.join(RELEASE_DIR, 'SHA256SUMS'), sha256Lines.join('\n') + '\n', 'utf8');

// Also populate legacy 0.0.0 directory with copies/symlinks so legacy feeds keep working
for (const f of fs.readdirSync(RELEASE_DIR)) {
    fs.copyFileSync(path.join(RELEASE_DIR, f), path.join(LEGACY_RELEASE_DIR, f));
}

console.log('\n=== RELEASE ARTIFACTS ASSEMBLED SUCCESSFULLY ===');
for (const file of fs.readdirSync(RELEASE_DIR)) {
    const stat = fs.statSync(path.join(RELEASE_DIR, file));
    console.log(`- ${file} (${stat.size} bytes)`);
}
