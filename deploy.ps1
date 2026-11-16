# PowerShell script to package and deploy the mod with forward slashes for cross-platform compatibility

param(
    [switch]$NoBump,
    # Deploy to your local (non-Steam) Factorio install. When omitted, deploys to Steam (AppData\Factorio\mods).
    [switch]$Local,
    # Path to the local Factorio install. Saved to the FACTORIO_LOCAL_INSTALL user env var for reuse across mods.
    [string]$LocalInstallPath,
    # Start Factorio after deployment
    [switch]$Start
)

# Name of the user environment variable that stores the local Factorio install path
$localInstallEnvVar = "FACTORIO_LOCAL_INSTALL"

# Get current directory as mod folder
$modPath = $PSScriptRoot
$infoJsonPath = Join-Path -Path $modPath -ChildPath "info.json"
$factorioModsPath = Join-Path -Path $env:APPDATA -ChildPath "Factorio\mods"


# Load .NET assemblies for zip creation. ZipFile lives in System.IO.Compression.FileSystem, but
# ZipArchiveMode lives in System.IO.Compression; Windows PowerShell 5.1 doesn't load the latter
# implicitly (PowerShell 7 does), so load both.
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

# Write text as UTF-8 *without* a byte-order mark. Windows PowerShell 5.1's
# `Set-Content -Encoding UTF8` prepends a BOM, which Factorio's JSON loader can reject.
function Write-Utf8NoBom {
    param([string]$Path, [string]$Text)
    [System.IO.File]::WriteAllText($Path, $Text, (New-Object System.Text.UTF8Encoding $false))
}

# Prompt the user to select (or type) a folder, returning $null if they cancel
function Get-FolderFromPrompt {
    param([string]$Description = "Select a folder")

    # Try a graphical folder picker first
    try {
        Add-Type -AssemblyName System.Windows.Forms
        $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
        $dialog.Description = $Description
        $dialog.ShowNewFolderButton = $false
        if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            return $dialog.SelectedPath
        }
        # Dialog shown but cancelled; fall through to text entry as a fallback
    } catch {
        Write-Host "Could not open a folder picker ($_); falling back to manual entry."
    }

    $entered = Read-Host "$Description (enter full path, or leave blank to cancel)"
    if ([string]::IsNullOrWhiteSpace($entered)) {
        return $null
    }
    return $entered.Trim('"')
}

# Resolve the local Factorio install path from param -> env var -> prompt, saving it for next time
function Resolve-LocalInstallPath {
    param([string]$Provided)

    $path = $Provided
    if (-not $path) {
        $path = [Environment]::GetEnvironmentVariable($localInstallEnvVar, "User")
    }
    if (-not $path) {
        Write-Host "No local Factorio install saved in `$env:$localInstallEnvVar."
        $path = Get-FolderFromPrompt -Description "Select your local Factorio install folder"
    }

    if (-not $path) {
        Write-Error "No local install path provided; cannot deploy locally."
        exit 1
    }
    if (-not (Test-Path -Path $path -PathType Container)) {
        Write-Error "Local install path '$path' does not exist or is not a folder."
        exit 1
    }

    # Persist for future runs (user scope) and the current session
    [Environment]::SetEnvironmentVariable($localInstallEnvVar, $path, "User")
    Set-Item -Path "Env:$localInstallEnvVar" -Value $path
    Write-Host "Using local Factorio install: $path (saved to `$env:$localInstallEnvVar)"

    return $path
}

function Increment-PatchVersion {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Version
    )

    if ($Version -notmatch '^([0-9]+)\.([0-9]+)\.([0-9]+)$') {
        throw "Version '$Version' is not in major.minor.patch format."
    }

    $major = [int]$Matches[1]
    $minor = [int]$Matches[2]
    $patch = [int]$Matches[3]

    return "$major.$minor.$($patch + 1)"
}

# Work out where we're deploying to (resolved up front so any prompt happens before packaging)
if ($Local) {
    $localInstallPath = Resolve-LocalInstallPath -Provided $LocalInstallPath
    $localModsPath = Join-Path -Path $localInstallPath -ChildPath "mods"
    $deployTarget = [PSCustomObject]@{ Name = "Local install"; Path = $localModsPath }
} else {
    $deployTarget = [PSCustomObject]@{ Name = "Steam (AppData)"; Path = $factorioModsPath }
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
    $info = Get-Content -Path $infoJsonPath -Raw | ConvertFrom-Json
    $version = $info.version
    $modName = $info.name
    if (-not $version) {
        Write-Error "Version field not found in info.json."
        exit 1
    }

    if (-not $NoBump) {
        $version = Increment-PatchVersion -Version $version
        $info.version = $version
        Write-Utf8NoBom -Path $infoJsonPath -Text ($info | ConvertTo-Json -Depth 100)
        Write-Host "Bumped version to: $version"
    } else {
        Write-Host "Skipping version bump because -NoBump was specified."
    }
} catch {
    Write-Error "Failed to parse or update info.json: $_"
    exit 1
}
$tempDir = Join-Path -Path $PSScriptRoot -ChildPath "temp_$modName"
# Define zip file name and path
$zipName = "${modName}_${version}.zip"
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
    New-Item -Path (Join-Path -Path $tempDir -ChildPath $modName) -ItemType Directory -Force | Out-Null
    # Copy all files to the subdirectory, excluding the temp directory and zip files
    Get-ChildItem -Path $modPath -Exclude "temp_*", "*.zip", ".github",".idea",".vscode","*.ps1" | Copy-Item -Destination (Join-Path -Path $tempDir -ChildPath $modName) -Recurse -Force
    Write-Host "Created temporary directory structure: $tempDir\$modName"
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
    $files = Get-ChildItem -Path (Join-Path -Path $tempDir -ChildPath $modName) -Recurse -File
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

# Copy the zip to the selected deployment target, overwriting if it exists
try {
    if (-not (Test-Path -Path $deployTarget.Path)) {
        New-Item -Path $deployTarget.Path -ItemType Directory -Force | Out-Null
        Write-Host "Created mods directory: $($deployTarget.Path)"
    }
    $destinationZipPath = Join-Path -Path $deployTarget.Path -ChildPath $zipName
    Copy-Item -Path $zipPath -Destination $destinationZipPath -Force
    Write-Host "Deployed to $($deployTarget.Name): $destinationZipPath"
} catch {
    Write-Error "Failed to deploy to $($deployTarget.Name) ($($deployTarget.Path)): $_"
    exit 1
}

# Enable this mod in Factorio's mod-list.json so it's active on the next launch.
# The mod name comes from info.json, so this always targets the mod being deployed.
try {
    $modListPath = Join-Path -Path $deployTarget.Path -ChildPath "mod-list.json"
    if (Test-Path -Path $modListPath) {
        $modList = Get-Content -Path $modListPath -Raw | ConvertFrom-Json
    } else {
        # No mod-list.json yet; start one with the base game enabled.
        $modList = [PSCustomObject]@{ mods = @([PSCustomObject]@{ name = "base"; enabled = $true }) }
        Write-Host "No mod-list.json found; creating a new one at $modListPath"
    }

    # Normalise to an array so we can search and append regardless of how JSON deserialised it.
    $mods = @($modList.mods)
    $existing = $mods | Where-Object { $_.name -eq $modName } | Select-Object -First 1
    if ($existing) {
        # Mutating in place is enough because $modList.mods holds the same object reference.
        $existing.enabled = $true
        Write-Host "Enabled existing mod-list.json entry for '$modName'."
    } else {
        $mods += [PSCustomObject]@{ name = $modName; enabled = $true }
        $modList.mods = $mods
        Write-Host "Added '$modName' to mod-list.json (enabled)."
    }

    Write-Utf8NoBom -Path $modListPath -Text ($modList | ConvertTo-Json -Depth 100)
    Write-Host "Updated mod-list.json: $modListPath"
} catch {
    Write-Warning "Failed to update mod-list.json (mod still deployed): $_"
}

Write-Host "Mod packaging and deployment completed successfully!"

if($Start) {
    if ($Local) {
        # Local (non-Steam) install: launch the exe directly, detached from this console.
        $binDir = Join-Path -Path $deployTarget.Path -ChildPath "..\bin\x64"
        $factorioExe = Join-Path -Path $binDir -ChildPath "factorio.exe"
        if (-not (Test-Path -Path $factorioExe)) {
            Write-Warning "factorio.exe not found at '$factorioExe'; skipping launch."
        } else {
            Write-Host "Starting Factorio (local install)..."
            # Hand off to the shell's 'start' so Factorio runs in its own window, fully
            # detached from this console (Factorio attaches to the parent console for
            # its log output, which otherwise ties up the terminal until it exits).
            $binDirResolved = (Resolve-Path -Path $binDir).Path
            Start-Process -FilePath "cmd.exe" -WindowStyle Hidden `
                -ArgumentList "/c", "start", "`"Factorio`"", "/D", "`"$binDirResolved`"", "factorio.exe", "--disable-audio"
        }
    } else {
        # Steam install: launch via the steam:// protocol so it works regardless of
        # where Steam put the game. Steam handles running the exe in its own window.
        Write-Host "Starting Factorio via Steam..."
        Start-Process "steam://run/427520"
    }
}