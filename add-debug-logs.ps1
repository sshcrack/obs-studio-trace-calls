param(
    [string]$baseDir = $PSScriptRoot,
    [switch]$dryRun = $false,
    [switch]$resetOnly = $false
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

# Function to extract function arguments from a function definition
function Get-FunctionArguments($content, $matchIndex, $function) {
    # Find the opening parenthesis after the function name
    $openParenIndex = $content.IndexOf('(', $matchIndex)
    if ($openParenIndex -lt 0) { return $null }
    
    # Find the matching closing parenthesis
    $closeParenIndex = -1
    $depth = 0
    for ($i = $openParenIndex; $i -lt $content.Length; $i++) {
        if ($content[$i] -eq '(') { $depth++ }
        if ($content[$i] -eq ')') { 
            $depth--
            if ($depth -eq 0) {
                $closeParenIndex = $i
                break
            }
        }
    }
    
    if ($closeParenIndex -lt 0) { return $null }
    
    # Extract the arguments string
    $argsString = $content.Substring($openParenIndex + 1, $closeParenIndex - $openParenIndex - 1).Trim()
    
    # Parse the arguments
    $args = @()
    if (-not [string]::IsNullOrWhiteSpace($argsString) -and $argsString -ne "void") {
        $inComment = $false
        $currentArg = ""
        $depth = 0
        
        for ($i = 0; $i -lt $argsString.Length; $i++) {
            $char = $argsString[$i]
            
            # Handle comments
            if ($i -lt $argsString.Length - 1 -and $argsString[$i] -eq '/' -and $argsString[$i + 1] -eq '*') {
                $inComment = $true
                $i++
                continue
            }
            if ($inComment -and $i -lt $argsString.Length - 1 -and $argsString[$i] -eq '*' -and $argsString[$i + 1] -eq '/') {
                $inComment = $false
                $i++
                continue
            }
            if ($inComment) { continue }
            
            # Track parentheses/brackets depth for complex types
            if ($char -eq '(' -or $char -eq '[' -or $char -eq '{') { $depth++ }
            if ($char -eq ')' -or $char -eq ']' -or $char -eq '}') { $depth-- }
            
            # Split arguments by comma, but only at the top level
            if ($char -eq ',' -and $depth -eq 0) {
                if (-not [string]::IsNullOrWhiteSpace($currentArg)) {
                    $args += $currentArg.Trim()
                }
                $currentArg = ""
            }
            else {
                $currentArg += $char
            }
        }
        
        if (-not [string]::IsNullOrWhiteSpace($currentArg)) {
            $args += $currentArg.Trim()
        }
    }
    
    # Extract variable names and types
    $argInfo = @()
    foreach ($arg in $args) {
        $cleanArg = $arg -replace '/\*.*?\*/', '' # Remove C-style comments
        $cleanArg = $cleanArg -replace '//.*$', '' # Remove C++-style comments
        $words = $cleanArg -split '\s+'
        
        if ($words.Count -lt 1) { continue }
        
        # The last word is typically the variable name
        $varName = $words[-1]
        
        # Handle pointers and arrays in the variable name
        if ($varName -match '^[\*\[\]]+$' -and $words.Count -ge 2) {
            # If the last word is just pointers/brackets, use the previous word with the pointers
            $varName = $words[-2] + $varName
        }
        
        # Remove any array brackets from the name
        $varName = $varName -replace '\[[^\]]*\]', ''
        
        # Remove any pointer asterisks from the name
        $varName = $varName -replace '^\*+', ''
        
        if ([string]::IsNullOrWhiteSpace($varName)) { continue }
        
        # Determine type by looking at all words except the last one (which is the variable name)
        $typeWords = @()
        for ($i = 0; $i -lt ($words.Count - 1); $i++) {
            if (-not [string]::IsNullOrWhiteSpace($words[$i])) {
                $typeWords += $words[$i]
            }
        }
        
        # Join the type words to get the full type
        $type = $typeWords -join ' '
        
        # Check for pointers in the type
        $isPointer = $arg -match '\*' -or $type -match '\*'
        
        # Create an object with both variable name and type information
        $argInfo += [PSCustomObject]@{
            Name = $varName
            Type = $type
            IsPointer = $isPointer
            FormatSpecifier = Get-FormatSpecifier $type $isPointer
        }
    }
    
    return $argInfo
}

# Function to determine the appropriate format specifier based on type
function Get-FormatSpecifier($type, $isPointer) {
    if ($isPointer) {
        return "%p" # Use pointer format for any pointer type
    }
    
    $numericTypes = @(
        'int', 'long', 'short', 'char', 'signed', 'unsigned',
        'int8_t', 'uint8_t', 'int16_t', 'uint16_t', 'int32_t', 'uint32_t', 'int64_t', 'uint64_t',
        'size_t', 'ssize_t', 'ptrdiff_t', 'intptr_t', 'uintptr_t'
    )
    
    $floatTypes = @('float', 'double')
    
    # Check for basic numeric types
    foreach ($numType in $numericTypes) {
        if ($type -match "\b$numType\b") {
            # Determine if unsigned
            if ($type -match "\bunsigned\b" -or $type -match "\buint") {
                return "%u"
            } else {
                return "%d"
            }
        }
    }
    
    # Check for 64-bit types
    if ($type -match "\blong long\b" -or $type -match "\bint64\b") {
        if ($type -match "\bunsigned\b" -or $type -match "\buint\b") {
            return "%llu"
        } else {
            return "%lld"
        }
    }
    
    # Check for floating point types
    foreach ($floatType in $floatTypes) {
        if ($type -match "\b$floatType\b") {
            return "%f"
        }
    }
    
    # Default to string representation for other types
    return "%s"
}

# Function to add debug logs to source files
function Add-DebugLogs($sourceFile, $exportedFunctions) {
    $result = Ensure-UtilBaseDefsIncluded $sourceFile
    $content = $result.Content
    $modified = $result.Modified

    $usesDefinedBlog = $content.Contains("#define blog(")
    if ($sourceFile.Contains("\util\") -or $sourceFile.Contains("/util/")) {
        Write-Host "Skipping $sourceFile (util directory)" -ForegroundColor Yellow
        return $content
    }

    foreach ($function in $exportedFunctions) {
        # Match the function definition in the source file
        $functionRegex = [regex]"(^|\s+)$function\s*\([^{]*?\)\s*\{(?!\s*blog\s*\(\s*LOG_DEBUG)"
        
        $match = $functionRegex.Match($content)
        if ($match.Success) {
            # Extract function arguments
            $arguments = Get-FunctionArguments $content $match.Index $function
            
            # Prepare the debug log message
            $debugLogLine = "`n`tblog(LOG_DEBUG, `"Function $function called"
            
            # Add arguments to the debug message if available
            if ($arguments -and $arguments.Count -gt 0) {
                $argString = " with args: "
                $argValues = @()
                
                foreach ($arg in $arguments) {
                    $argName = $arg.Name
                    $formatSpecifier = $arg.FormatSpecifier
                    
                    if ($arg.IsPointer -and $formatSpecifier -eq "%p") {
                        $argString += "$argName=(ptr)$formatSpecifier, "
                    }
                    elseif ($formatSpecifier -eq "%s") {
                        $argString += "$argName=`\`"$formatSpecifier`\`", "
                    }
                    else {
                        $argString += "$argName=$formatSpecifier, "
                    }
                    
                    $argValues += $arg.Name
                }
                
                # Remove trailing comma and space
                $argString = $argString.TrimEnd(', ')
                $debugLogLine += $argString + "`""
                
                # Add the argument values as format parameters
                if ($argValues.Count -gt 0) {
                    $formatArgs = ""
                    foreach ($arg in $argValues) {
                        $formatArgs += ", $arg"
                    }
                    $debugLogLine += $formatArgs
                }
            }
            else {
                $debugLogLine += "`""
            }
            
            $debugLogLine += ");"
            
            # For custom blog definitions that use formatting
            if ($usesDefinedBlog) {
                $debugLogLine = "`n`tblog(LOG_DEBUG, `"Function %s called"
                
                if ($arguments -and $arguments.Count -gt 0) {
                    $argString = " with args: "
                    $formatSpecifiers = @()
                    
                    foreach ($arg in $arguments) {
                        $argName = $arg.Name
                        $formatSpecifier = $arg.FormatSpecifier
                        
                        if ($arg.IsPointer -and $formatSpecifier -eq "%p") {
                            $argString += "$argName=(ptr)$formatSpecifier, "
                        }
                        elseif ($formatSpecifier -eq "%s") {
                            $argString += "$argName=`\`"$formatSpecifier`\`", "
                        }
                        else {
                            $argString += "$argName=$formatSpecifier, "
                        }
                        
                        $formatSpecifiers += $arg.Name
                    }
                    
                    # Remove trailing comma and space
                    $argString = $argString.TrimEnd(', ')
                    $debugLogLine += $argString + "`""
                    
                    # Add the function name and all arguments to the format args
                    $formatArgs = ", `"$function`""
                    foreach ($arg in $formatSpecifiers) {
                        $formatArgs += ", $arg"
                    }
                    $debugLogLine += $formatArgs
                }
                else {
                    # Just the function name if no args
                    $debugLogLine += "`", `"$function`""
                }
                
                $debugLogLine += ");"
            }

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
if (-not $resetOnly) {
    Process-Directories
    Write-Host "Processing complete!" -ForegroundColor Green
}
else {
    Write-Host "Resetting directories only." -ForegroundColor Green
}