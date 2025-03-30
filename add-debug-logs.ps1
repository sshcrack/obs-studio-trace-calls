param(
    [string]$baseDir = $PSScriptRoot,
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

# Function to ensure syslog_defs.h is included in the file
function Ensure-UtilBaseDefsIncluded($sourceFile) {
    $content = Get-Content $sourceFile -Raw
    $modified = $false
    
    # Check if syslog_defs.h is already included
    if (-not ($content -match '#include\s+<util/base\.h>|#include\s+"[^"]*/util/base\.h"')) {
        # Find the last include statement
        $lastIncludeIndex = $content.LastIndexOf("#include")
        if ($lastIncludeIndex -ge 0) {
            # Find the end of the line containing the last include
            $endOfLineIndex = $content.IndexOf("`n", $lastIncludeIndex)
            if ($endOfLineIndex -ge 0) {
                # Insert the new include after the last one
                $content = $content.Insert($endOfLineIndex + 1, "#include <util/base.h>`n")
                $modified = $true
                # Write-Host "Added util/base.h include to $sourceFile"
            }
        }
        else {
            # If no includes found, add at the top after any comments or preprocessor directives
            $headerEndIndex = 0
            $lines = $content -split "`n"
            for ($i = 0; $i -lt $lines.Length; $i++) {
                $line = $lines[$i].Trim()
                if (-not $line.StartsWith("/*") -and 
                    -not $line.StartsWith("*") -and 
                    -not $line.StartsWith("//") -and 
                    -not $line.StartsWith("#pragma") -and 
                    -not $line.StartsWith("#define") -and 
                    -not $line.StartsWith("#ifndef") -and 
                    -not $line.StartsWith("#endif") -and 
                    -not [string]::IsNullOrWhiteSpace($line)) {
                    $headerEndIndex = $content.IndexOf($lines[$i])
                    break
                }
            }
            
            $content = $content.Insert($headerEndIndex, "#include <util/base.h>`n`n")
            $modified = $true
            # Write-Host "Added util/base.h include to the top of $sourceFile"
        }
    }
    
    return @{
        Content  = $content
        Modified = $modified
    }
}

# Function to add debug logs to source files
function Add-DebugLogs($sourceFile, $exportedFunctions) {
    $result = Ensure-UtilBaseDefsIncluded $sourceFile
    $content = $result.Content
    $modified = $result.Modified

    $usesDefinedBlog = $content.Contains("#define blog(")
    if($sourceFile.Contains("\util\") -or $sourceFile.Contains("/util/")) {
        Write-Host "Skipping $sourceFile (util directory)" -ForegroundColor Yellow
        return $content
    }

    foreach ($function in $exportedFunctions) {
        # Match the function definition in the source file
        # This looks for the function name followed by opening parenthesis and parameters
        $functionRegex = [regex]"(^|\s+)$function\s*\([^)]*\)\s*\{(?!\s*blog\s*\(\s*LOG_DEBUG)"
        $debugLogLine = "`n`tblog(LOG_DEBUG, `"Function $function called`");"

        if ($usesDefinedBlog) {
            $debugLogLine = "`n`tblog(LOG_DEBUG, `"Function %s called`", `"$function`");"
        }
        
        $match = $functionRegex.Match($content)
        if ($match.Success) {
            # Find the opening brace and insert the debug log after it
            $braceIndex = $content.IndexOf('{', $match.Index)
            if ($braceIndex -gt 0) {
                $content = $content.Insert($braceIndex + 1, $debugLogLine)
                $modified = $true
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
    # Write-Host "Processing: $sourceFile with header $headerFile"
    
    # Get exported functions from the header file
    $exportedFunctions = Get-ExportedFunctions $headerFile
    
    if ($exportedFunctions.Count -eq 0) {
        return
    }
    
    # Add debug logs to the source file
    $modified = Add-DebugLogs $sourceFile $exportedFunctions
    
    if ($dryRun) {
        if ($modified) {
            Write-Host "Would modify $sourceFile (dry run)" -ForegroundColor Yellow
        }
        else {
            Write-Host "No changes needed for $sourceFile" -ForegroundColor Green
        }
    }
    else {
        if ($modified) {
            # Write-Host "Modified $sourceFile" -ForegroundColor Yellow
        }
        else {
            # Write-Host "No changes needed for $sourceFile" -ForegroundColor Green
        }
    }
}

function Reset-Directories {
    foreach ($dir in $directories) {
        git checkout $dir
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
}
else {
    Write-Host "Mode: Live Run (files will be modified)" -ForegroundColor Magenta
}

# Start processing
Reset-Directories
Process-Directories

Write-Host "Processing complete!" -ForegroundColor Green
