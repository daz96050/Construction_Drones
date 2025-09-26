# PowerShell script to package and deploy the mod with forward slashes for cross-platform compatibility

# Get current directory as mod folder
$modPath = $PSScriptRoot
$modFolderName = "Construction_Drones_Forked"
$infoJsonPath = Join-Path -Path $modPath -ChildPath "info.json"
$factorioModsPath = Join-Path -Path $env:APPDATA -ChildPath "Factorio\mods"
$tempDir = Join-Path -Path $PSScriptRoot -ChildPath "temp_$modFolderName"

# Load .NET assembly for zip creation
Add-Type -AssemblyName System.IO.Compression.FileSystem

# Function to validate and create the Factorio mods directory
function Ensure-ModsDirectory {
    if (-not (Test-Path -Path $factorioModsPath)) {
        New-Item -Path $factorioModsPath -ItemType Directory -Force | Out-Null
        Write-Host "Created Factorio mods directory: $factorioModsPath"
    }
}

# Check if mod folder exists
if (-not (Test-Path -Path $modPath)) {
    Write-Error "Mod folder '$modPath' not found."
    exit 1
}

# Read info.json to get version
if (-not (Test-Path -Path $infoJsonPath)) {
    Write-Error "info.json not found at '$infoJsonPath'."
    exit 1
}

try {
    $infoJson = Get-Content -Path $infoJsonPath -Raw | ConvertFrom-Json
    $version = $infoJson.version
    if (-not $version) {
        Write-Error "Version field not found in info.json."
        exit 1
    }
} catch {
    Write-Error "Failed to parse info.json: $_"
    exit 1
}

# Define zip file name and path
$zipName = "${modFolderName}_${version}.zip"
$zipPath = Join-Path -Path $PSScriptRoot -ChildPath $zipName

# Create temporary subdirectory for zip structure
if (Test-Path -Path $tempDir) {
    try {
        Remove-Item -Path $tempDir -Recurse -Force
        Write-Host "Removed existing temporary directory: $tempDir"
    } catch {
        Write-Error "Failed to remove existing temporary directory: $_"
        exit 1
    }
}

try {
    New-Item -Path $tempDir -ItemType Directory -Force | Out-Null
    New-Item -Path (Join-Path -Path $tempDir -ChildPath $modFolderName) -ItemType Directory -Force | Out-Null
    # Copy all files to the subdirectory, excluding the temp directory and zip files
    Get-ChildItem -Path $modPath -Exclude "temp_*", "*.zip" | Copy-Item -Destination (Join-Path -Path $tempDir -ChildPath $modFolderName) -Recurse -Force
    Write-Host "Created temporary directory structure: $tempDir\$modFolderName"
} catch {
    Write-Error "Failed to create temporary directory structure: $_"
    exit 1
}

# Remove existing zip file if it exists
if (Test-Path -Path $zipPath) {
    try {
        Remove-Item -Path $zipPath -Force
        Write-Host "Removed existing zip file: $zipPath"
    } catch {
        Write-Error "Failed to remove existing zip file: $_"
        exit 1
    }
}

# Create zip archive with forward slashes using System.IO.Compression.ZipFile
try {
    $zip = [System.IO.Compression.ZipFile]::Open($zipPath, [System.IO.Compression.ZipArchiveMode]::Create)
    $files = Get-ChildItem -Path (Join-Path -Path $tempDir -ChildPath $modFolderName) -Recurse -File
    foreach ($file in $files) {
        $relativePath = $file.FullName.Substring($tempDir.Length + 1).Replace('\', '/')
        $entry = $zip.CreateEntry($relativePath)
        $entryStream = $entry.Open()
        $fileStream = $file.OpenRead()
        $fileStream.CopyTo($entryStream)
        $fileStream.Close()
        $entryStream.Close()
    }
    $zip.Dispose()
    Write-Host "Created zip archive with forward slashes: $zipPath"
} catch {
    Write-Error "Failed to create zip archive: $_"
    exit 1
}

# Clean up temporary directory
try {
    Remove-Item -Path $tempDir -Recurse -Force
    Write-Host "Removed temporary directory: $tempDir"
} catch {
    Write-Error "Failed to clean up temporary directory: $_"
    exit 1
}

# Ensure Factorio mods directory exists
Ensure-ModsDirectory

# Copy zip to Factorio mods directory, overwriting if exists
$destinationZipPath = Join-Path -Path $factorioModsPath -ChildPath $zipName
try {
    Copy-Item -Path $zipPath -Destination $destinationZipPath -Force
    Write-Host "Copied mod to: $destinationZipPath"
} catch {
    Write-Error "Failed to copy mod to Factorio mods directory: $_"
    exit 1
}

Write-Host "Mod packaging and deployment completed successfully!"

# start "D:\SteamLibrary\steamapps\common\Factorio\bin\x64\factorio.exe" <# -ArgumentList "--disable-audio","--load-game Error-Thing","--disable-migration-window" #>