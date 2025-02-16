<#
.SYNOPSIS
    Clones a source folder to a destination using robocopy and verifies that copied files are identical.

.DESCRIPTION
    This script:
      - Accepts source and destination folder paths.
      - Optionally accepts a project name to track verified files.
      - Creates the destination folder if it doesn’t exist. If it exists, it warns and prompts for confirmation (resume, verify only, or abort).
      - Uses robocopy (with /E and /COPYALL) to copy all files/subfolders while logging operations.
      - Verifies each file by comparing MD5 hashes of the source and destination.
      - When a project is specified, records each verified file’s name, size, and timestamp to skip unchanged files in subsequent runs.
      - Generates a report with the robocopy log location and verification results.

.PARAMETER Source
    The folder to be cloned.

.PARAMETER Destination
    The folder where files will be copied to.

.PARAMETER Project
    (Optional) A simple name used to create a project file (e.g., "MyProject" becomes `projects\MyProject.csv`) that tracks verified file details.
    When provided, the script will skip verifying files that have not changed since their last verification.

.EXAMPLE
    .\BulkCopy.ps1 -Source "C:\Path\To\Source" -Destination "D:\Path\To\Destination" -Project "MyProject"
    This creates a project file at 'projects\MyProject.csv'.

#>
param(
    [Parameter(Mandatory = $true)]
    [string]$Source,

    [Parameter(Mandatory = $true)]
    [string]$Destination,

    [Parameter(Mandatory = $false)]
    [string]$Project
)

# Check parameters and existence of source folder
if (-not (Test-Path -Path $Source)) {
    Write-Error "Source folder '$Source' does not exist. Exiting."
    exit 1
}

# If destination exists, warn and ask for confirmation (overwrite)
if (Test-Path $Destination) {
    Write-Warning "WARNING: Destination folder '$Destination' already exists. This may be a previous unsuccessful backup from '$Source'."
    $valid = $false
    do {
        Write-Host "Press R to Resume backup (robocopy & verify), V to Verify only, A to Abort:" -NoNewline
        $key = [Console]::ReadKey($true).KeyChar.ToString().ToLower()
        Write-Host $key
        switch ($key) {
            'r' {
                Write-Host "Resuming backup: running robocopy and then verification."
                $skipRobocopy = $false
                $valid = $true
            }
            'v' {
                Write-Host "Skipping robocopy; proceeding directly to file verification."
                $skipRobocopy = $true
                $valid = $true
            }
            'a' {
                Write-Host "Operation cancelled."
                exit 0
            }
            default {
                Write-Host "Invalid key. Please try again."
            }
        }
    } until ($valid)
}
else {
    # Create destination folder
    try {
        New-Item -Path $Destination -ItemType Directory -Force | Out-Null
        Write-Host "Created destination folder: $Destination"
    }
    catch {
        Write-Error "Failed to create destination folder: $Destination. Exiting."
        exit 1
    }
}

# Create logs folder if it doesn't exist
$logsFolder = Join-Path (Get-Location) "logs"
if (-not (Test-Path -LiteralPath $logsFolder)) {
    New-Item -Path $logsFolder -ItemType Directory -Force | Out-Null
}

# Create projects folder if a project is specified
if ($Project) {
    $projectsFolder = Join-Path (Get-Location) "projects"
    if (-not (Test-Path -LiteralPath $projectsFolder)) {
        New-Item -Path $projectsFolder -ItemType Directory -Force | Out-Null
    }
    # Derive the project file path automatically (e.g. projects\<ProjectName>.csv)
    $projectFile = Join-Path $projectsFolder ("$Project.csv")
}
else {
    $projectFile = $null
}

# Define log file paths
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$robocopyLog = Join-Path $logsFolder "$($timestamp)_robocopy.log"
$verificationLog = Join-Path $logsFolder "$($timestamp)_verification.log"
$reportFile = Join-Path $logsFolder "$($timestamp)_report.txt"

# Run robocopy with logging and console output
$robocopyArgs = @(
    "`"$Source`"",
    "`"$Destination`"",
    "/E",           # Copy all subdirectories including empty ones.
    "/COPYALL",     # Copy all file info.
    "/R:25",        # Retry 25 times on failure.
    "/W:5",         # Wait 5 seconds between retries.
    "/TEE",         # Output to console and log file.
    "/LOG:`"$robocopyLog`""  # Log file.
)

$robocopyCmd = "robocopy " + ($robocopyArgs -join " ")

if (-not $skipRobocopy) {
    Write-Host "Starting file copy with robocopy..."
    Write-Host "Executing: $robocopyCmd"
    # Run robocopy.
    try {
        Invoke-Expression $robocopyCmd
    }
    catch {
        Write-Error "Robocopy failed. Exiting."
        exit 1
    }
    # Detect failure based on exit code.
    if ($LASTEXITCODE -ge 8) {
        Write-Error "Robocopy encountered an error. Exit code: $LASTEXITCODE"
        exit 1
    }
    Write-Host "Robocopy completed. Log file: $robocopyLog"
}
else {
    Write-Host "Robocopy step skipped."
}

# Perform file verification
Write-Host "Starting file verification..."

# Get all files in the source folder
Write-Host "Getting source files..."
$sourceFiles = Get-ChildItem -Path $Source -Recurse -File
Write-Host "Source files found: $($sourceFiles.Count)"

# Re-add initialization of the error array if missing.
$errors = @()

# Ensure source path ends with a backslash for correct relative path calculation.
$sourceBase = $Source.TrimEnd("\") + "\"

# Load project records if a project file is specified
if ($projectFile) {
    if (Test-Path -LiteralPath $projectFile) {
        $verifiedRecords = Import-Csv -Path $projectFile
    } else {
        $verifiedRecords = @()
    }
}
else {
    $verifiedRecords = @()
}

# Begin file verification loop
$total = $sourceFiles.Count
for ($i = 0; $i -lt $total; $i++) {
    $file = $sourceFiles[$i]
    $counter = $i + 1
    Write-Progress -Activity "Verifying Files" `
                   -Status "Processing file $counter of $total" `
                   -PercentComplete (($counter / $total) * 100)

    Write-Host -ForegroundColor Gray "Verifying file: $($file.FullName)"
    
    # Get relative path
    $relativePath = $file.FullName.Substring($sourceBase.Length)
    $destFile = Join-Path $Destination $relativePath

    # If project file is specified, check if file is already verified
    if ($projectFile) {
        $record = $verifiedRecords | Where-Object { $_.RelativePath -eq $relativePath }
        if ($record) {
            if (($file.Length -eq [int64]$record.Size) -and ($file.LastWriteTime.ToString("s") -eq $record.LastWriteTime)) {
                Write-Host -ForegroundColor Cyan "Skipping already verified file: $relativePath"
                Write-Host
                continue
            }
        }
    }

    if (-not (Test-Path -LiteralPath $destFile)) {
        $msg = "Missing file: $relativePath"
        $errors += $msg
        Add-Content -Path $verificationLog -Value $msg
        Write-Host -ForegroundColor Red "[ERROR] $msg"
    }
    else {
        $srcHash = (Get-FileHash -Path $file.FullName -Algorithm MD5).Hash
        $destHash = (Get-FileHash -Path $destFile -Algorithm MD5).Hash
        if ($srcHash -ne $destHash) {
            $msg = "Hash mismatch: $destFile"
            $errors += $msg
            Add-Content -Path $verificationLog -Value $msg
            Write-Host -ForegroundColor Red "[ERROR] $msg"
        }
        else {
            Write-Host -ForegroundColor Green "[SUCCESS] Verified $relativePath"
            # Immediately update the project file with verified details.
            if ($projectFile) {
                $verifiedRecords = $verifiedRecords | Where-Object { $_.RelativePath -ne $relativePath }
                $verifiedRecords += [PSCustomObject]@{
                    RelativePath  = $relativePath
                    Size          = $file.Length
                    LastWriteTime = $file.LastWriteTime.ToString("s")
                    Hash          = $srcHash
                }
                $verifiedRecords | Export-Csv -Path $projectFile -NoTypeInformation
            }
        }
    }
    Write-Host
}

# Clear the progress bar after loop completion.
Write-Progress -Activity "Verifying Files" -Completed

# Create final report
Write-Host "Generating report..."
if ($errors.Count -eq 0) {
    $report = "[SUCCESS] All files copied and verified successfully."
    Write-Host -ForegroundColor Green $report
} else {
    $report = "[ERROR] Errors found during file verification:`n" + ($errors -join "`n")
    Write-Host -ForegroundColor Red $report
}
Set-Content -Path $reportFile -Value $report

# Output report location
Write-Host "Report generated at: $reportFile"
