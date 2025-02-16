# BulkCopy

**BulkCopy.ps1** is a PowerShell script that clones a source folder to a destination using robocopy and then verifies that all files were copied correctly by comparing their MD5 hashes.

This version supports a new `–Project` parameter. When provided, the script automatically creates a project file (in the projects folder) with the given project name and records each verified file’s name, size, and timestamp. On subsequent runs, if a file’s properties remain unchanged, its verification is skipped.

## Features

- **Copy Files/Subfolders:** Uses robocopy with `/E` and `/COPYALL` to copy all files and subdirectories.
- **Logging:** Creates separate log files for robocopy operations and file verification.
- **Verification:** Compares MD5 hashes of source and destination files to ensure integrity.
- **Interactive Options:** Prompts the user to resume copying, verify only, or abort if destination already exists.
- **Reporting:** Generates a final report showing success or listing any errors.
- **Projects:** Optionally tracks a project by recording each verified file’s name, size, and timestamp. When the `–Project` parameter is provided, a project file is created in the `projects` folder (named `<ProjectName>.csv`). On subsequent runs, if a file's size and last write time match the recorded values, the file is assumed unchanged and its verification is skipped.

### Why MD5?

MD5 was chosen because it is a fast, built-in hash algorithm that efficiently checks whether two files are identical. While it is not suitable for cryptographic security, its speed and widespread availability make it ideal for verifying file integrity after copying.

## Parameters

- **Source**: The folder to be cloned.
- **Destination**: The folder where files will be copied to.
- **Project** (optional): A simple name used to generate a project file (e.g., "MyProject" becomes `projects\MyProject.csv`) that records verified file details. When provided, the script will skip verifying files that have not changed since their last verification.

## Usage

Run the script from PowerShell with the required parameters:

```powershell
.\BulkCopy.ps1 -Source "C:\Path\To\Source" -Destination "D:\Path\To\Destination" -Project "MyProject"
```

If the destination folder exists, you will be prompted to:

- Press **R** to resume backup (perform robocopy and verification).
- Press **V** to verify only.
- Press **A** to abort the operation.

## Logs and Reports

- The logs and final report are saved in the `logs` folder, located next to the script.
- Log file names include a timestamp for easy reference.

## Requirements

- PowerShell 7.5

## Disclosure

This script was heavily created with the assistance of GitHub Copilot. It was thoroughly reviewed by me and tested on my own system before being published.

## License

This script is published on GitHub under the MIT license.
