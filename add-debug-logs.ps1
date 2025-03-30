param(
    [string]$baseDir = "e:\Rust\obs-studio",
    [switch]$dryRun = $false
)

# Directories to process
$directories = @(
    "libobs",
    "libobs-d3d11",
    "libobs-opengl",
    "libobs-winrt",
    "plugins"
)

# Function to extract exported function names from header files
function Get-ExportedFunctions($headerFile) {
    $content = Get-Content $headerFile -Raw
    $exportedFunctions = @()
    
    # Regular expression to match EXPORT function declarations
    # This captures the function name after "EXPORT" and before the opening parenthesis
    $regex = [regex]'EXPORT\s+(?:[a-zA-Z0-9_*]+\s+)+([a-zA-Z0-9_]+)\s*\('
    
    $matches = $regex.Matches($content)
    foreach ($match in $matches) {
        $functionName = $match.Groups[1].Value
        $exportedFunctions += $functionName
    }
    
    return $exportedFunctions
}

# Function to add debug logs to source files
function Add-DebugLogs($sourceFile, $exportedFunctions) {
    $content = Get-Content $sourceFile -Raw
    $modified = $false
    
    foreach ($function in $exportedFunctions) {
        # Match the function definition in the source file
        # This looks for the function name followed by opening parenthesis and parameters
        $functionRegex = [regex]"(^|\s+)$function\s*\([^)]*\)\s*(?:\{|;)"
        $debugLogLine = "blog(LOG_DEBUG, `"Function $function called`");"
        
        $match = $functionRegex.Match($content)
        if ($match.Success) {
            # Check if the debug log is already there to avoid duplicates
            $nextLine = $content.Substring($match.Index + $match.Length, [Math]::Min(100, $content.Length - $match.Index - $match.Length))
            if (-not $nextLine.Contains($debugLogLine)) {
                # Find the opening brace and insert the debug log after it
                $braceIndex = $content.IndexOf('{', $match.Index)
                if ($braceIndex -gt 0) {
                    $content = $content.Insert($braceIndex + 1, "`n`t$debugLogLine`n")
                    $modified = $true
                    Write-Host "Added debug log for function $function in $sourceFile"
                }
            }
        }
    }
    
    if ($modified -and -not $dryRun) {
        $content | Set-Content $sourceFile -NoNewline
        return $true
    }
    
    return $modified
}

# Function to process a pair of header and source files
function Process-FilePair($headerFile, $sourceFile) {
    Write-Host "Processing: $sourceFile with header $headerFile"
    
    # Get exported functions from the header file
    $exportedFunctions = Get-ExportedFunctions $headerFile
    
    if ($exportedFunctions.Count -eq 0) {
        Write-Host "No exported functions found in $headerFile"
        return
    }
    
    # Add debug logs to the source file
    $modified = Add-DebugLogs $sourceFile $exportedFunctions
    
    if ($dryRun) {
        if ($modified) {
            Write-Host "Would modify $sourceFile (dry run)" -ForegroundColor Yellow
        } else {
            Write-Host "No changes needed for $sourceFile" -ForegroundColor Green
        }
    } else {
        if ($modified) {
            Write-Host "Modified $sourceFile" -ForegroundColor Yellow
        } else {
            Write-Host "No changes needed for $sourceFile" -ForegroundColor Green
        }
    }
}

# Main processing function
function Process-Directories {
    foreach ($dir in $directories) {
        $fullPath = Join-Path $baseDir $dir
        Write-Host "Processing directory: $fullPath" -ForegroundColor Cyan
        
        if (-not (Test-Path $fullPath)) {
            Write-Host "Directory not found: $fullPath" -ForegroundColor Red
            continue
        }
        
        # Get all source files
        $sourceFiles = Get-ChildItem -Path $fullPath -Recurse -Include @("*.c", "*.cpp")
        
        foreach ($sourceFile in $sourceFiles) {
            # Try to find corresponding header file
            $baseName = [System.IO.Path]::GetFileNameWithoutExtension($sourceFile.Name)
            $headerFile = $null
            
            # Check for .h file with same name
            $potentialHeader = Join-Path $sourceFile.DirectoryName "$baseName.h"
            if (Test-Path $potentialHeader) {
                $headerFile = $potentialHeader
            }
            
            # Check for .hpp file with same name
            if ($null -eq $headerFile) {
                $potentialHeader = Join-Path $sourceFile.DirectoryName "$baseName.hpp"
                if (Test-Path $potentialHeader) {
                    $headerFile = $potentialHeader
                }
            }
            
            # If header file found, process the pair
            if ($null -ne $headerFile) {
                Process-FilePair $headerFile $sourceFile.FullName
            }
        }
    }
}

# Print script info
Write-Host "Debug Log Insertion Script" -ForegroundColor Magenta
Write-Host "Base Directory: $baseDir" -ForegroundColor Magenta
if ($dryRun) {
    Write-Host "Mode: Dry Run (no changes will be made)" -ForegroundColor Magenta
} else {
    Write-Host "Mode: Live Run (files will be modified)" -ForegroundColor Magenta
}

# Start processing
Process-Directories

Write-Host "Processing complete!" -ForegroundColor Green
