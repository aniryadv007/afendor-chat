$ErrorActionPreference = "Stop"

$version = "0.0.0"
$releaseDir = "releases\afendor-chat\$version\windows"
$unpackedDir = "afendor_desktop\dist-electron\win-unpacked"
$vendorDir = ".velopack\extracted\vendor"
$stageDir = "releases\.nupkg-stage"

Write-Host "Assembling AFENDOR CHAT Release for Windows x64 (v$version)..."
New-Item -ItemType Directory -Force -Path $releaseDir | Out-Null
Remove-Item "$releaseDir\temp-nupkg.zip" -Force -ErrorAction SilentlyContinue

# 1. Portable executable
Write-Host "1. Copying standalone portable executable..."
Copy-Item "$unpackedDir\Afendor Chat.exe" "$releaseDir\Afendor-Chat-$version-win-x64.exe" -Force

# 2. Portable zip
if (-not (Test-Path "$releaseDir\Afendor-Chat-$version-win-x64-portable.zip")) {
    Write-Host "2. Creating portable ZIP..."
    Compress-Archive -Path "$unpackedDir\*" -DestinationPath "$releaseDir\Afendor-Chat-$version-win-x64-portable.zip" -Force
} else {
    Write-Host "2. Portable ZIP already present."
}

# 3. Assemble .nupkg staging
Write-Host "3. Assembling Velopack full package staging..."
Remove-Item -Recurse -Force $stageDir -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path "$stageDir\lib\net45", "$stageDir\_rels" | Out-Null
Copy-Item -Recurse "$unpackedDir\*" "$stageDir\lib\net45\"

# Write nuspec
$nuspec = @"
<?xml version="1.0" encoding="utf-8"?>
<package xmlns="http://schemas.microsoft.com/packaging/2010/07/nuspec.xsd">
  <metadata>
    <id>afendor_desktop</id>
    <version>$version</version>
    <title>Afendor Chat</title>
    <authors>Afendor Chat</authors>
    <owners>Afendor Chat</owners>
    <requireLicenseAcceptance>false</requireLicenseAcceptance>
    <description>Afendor Chat - Instant messaging and VoIP application</description>
    <copyright>Copyright (c) 2026 Afendor Chat</copyright>
  </metadata>
</package>
"@
Set-Content -Path "$stageDir\afendor_desktop.nuspec" -Value $nuspec -Encoding UTF8

$contentTypes = @"
<?xml version="1.0" encoding="utf-8"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml" />
  <Default Extension="nuspec" ContentType="application/octet" />
  <Default Extension="exe" ContentType="application/octet" />
  <Default Extension="dll" ContentType="application/octet" />
  <Default Extension="pak" ContentType="application/octet" />
  <Default Extension="dat" ContentType="application/octet" />
  <Default Extension="bin" ContentType="application/octet" />
  <Default Extension="json" ContentType="application/json" />
</Types>
"@
Set-Content -Path "$stageDir\[Content_Types].xml" -Value $contentTypes -Encoding UTF8

$rels = @"
<?xml version="1.0" encoding="utf-8"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Type="http://schemas.microsoft.com/packaging/2010/07/manifest" Target="/afendor_desktop.nuspec" Id="R0" />
</Relationships>
"@
Set-Content -Path "$stageDir\_rels\.rels" -Value $rels -Encoding UTF8

# Compress to .zip and rename to .nupkg
$tempZip = "$releaseDir\nupkg-build.zip"
Remove-Item -Force $tempZip -ErrorAction SilentlyContinue
Write-Host "Compressing .nupkg package..."
Compress-Archive -Path "$stageDir\*" -DestinationPath $tempZip -Force
Move-Item -Path $tempZip -Destination "$releaseDir\Afendor-Chat-$version-win-x64-full.nupkg" -Force
Copy-Item "$releaseDir\Afendor-Chat-$version-win-x64-full.nupkg" "$releaseDir\afendor_desktop-$version-full.nupkg" -Force
Remove-Item -Recurse -Force $stageDir

# 4. Setup installer
Write-Host "4. Staging setup installer..."
Copy-Item "$vendorDir\setup.exe" "$releaseDir\Setup.exe" -Force
Copy-Item "$vendorDir\setup.exe" "$releaseDir\Afendor-Chat-$version-win-x64-Setup.exe" -Force

# 5. Manifests (releases.win.json & RELEASES)
Write-Host "5. Generating releases.win.json and RELEASES..."
$nupkgPath = "$releaseDir\Afendor-Chat-$version-win-x64-full.nupkg"
$nupkgBytes = [System.IO.File]::ReadAllBytes((Resolve-Path $nupkgPath))
$sha1 = [System.BitConverter]::ToString([System.Security.Cryptography.SHA1]::Create().ComputeHash($nupkgBytes)).Replace("-", "").ToLower()
$sha256 = [System.BitConverter]::ToString([System.Security.Cryptography.SHA256]::Create().ComputeHash($nupkgBytes)).Replace("-", "").ToLower()
$size = $nupkgBytes.Length
$nupkgFileName = [System.IO.Path]::GetFileName($nupkgPath)

$releasesJson = @"
{
  "Assets": [
    {
      "PackageId": "afendor_desktop",
      "Version": "$version",
      "Type": "Full",
      "FileName": "$nupkgFileName",
      "SHA1": "$sha1",
      "SHA256": "$sha256",
      "Size": $size
    }
  ]
}
"@
Set-Content -Path "$releaseDir\releases.win.json" -Value $releasesJson -Encoding UTF8
Set-Content -Path "$releaseDir\RELEASES" -Value "$sha1 $nupkgFileName $size`n" -Encoding UTF8 -NoNewline

# 6. Generate SHA256SUMS for all files
Write-Host "6. Generating SHA256SUMS manifest..."
Remove-Item -Force "$releaseDir\SHA256SUMS" -ErrorAction SilentlyContinue
$sha256Algo = [System.Security.Cryptography.SHA256]::Create()
$checksumLines = @()
Get-ChildItem -Path $releaseDir -File | Sort-Object Name | ForEach-Object {
    $bytes = [System.IO.File]::ReadAllBytes($_.FullName)
    $hash = [System.BitConverter]::ToString($sha256Algo.ComputeHash($bytes)).Replace("-", "").ToLower()
    $checksumLines += "$hash  $($_.Name)"
}
Set-Content -Path "$releaseDir\SHA256SUMS" -Value ($checksumLines -join "`n" + "`n") -Encoding UTF8 -NoNewline

Write-Host "`nRelease assembly complete! Artifacts:"
Get-ChildItem -Path $releaseDir | Format-Table Name, Length, LastWriteTime

