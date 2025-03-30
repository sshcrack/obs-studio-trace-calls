import type { BunFile, Glob } from 'bun'
import path from "path"
import { getExportedFunctions, getFunctionLineNumber, type CppFunction } from './extractor'
import { EXCLUDE_DIRECTORIES, LOG_LEVEL, LOGGING_FUNCTION } from './constants'

export async function processFile(sourceFile: BunFile, headerFile: BunFile, additionalExports: CppFunction[] = []) {
    const headerContent = await headerFile.text()
    const sourceContent = await sourceFile.text()

    const exportedFunctions = await getExportedFunctions(headerContent)
    if (exportedFunctions.length === 0) {
        return
    }

    const sourceLines = sourceContent.split("\n")
    for (const func of [...exportedFunctions, ...additionalExports]) {
        const lineNumber = getFunctionLineNumber(sourceLines.join("\n"), func.name)
        if (lineNumber === -1) {
            //if (!sourceFile.name?.includes("obs.c") && !additionalExports.includes(func))
//                console.log("Function not found in source file", sourceFile.name, ":", func.name)

            continue
        }



        let insertPos = lineNumber + 1
        if(!sourceLines[lineNumber].includes("{") && sourceLines[insertPos].includes("{"))
            insertPos = lineNumber + 2


        sourceLines.splice(insertPos, 0, `${LOGGING_FUNCTION}(${LOG_LEVEL}, "${func.name} called");`)
    }

    await Bun.write(sourceFile, sourceLines.join("\n"))
}

// Finds the corresponding header and source files for a given file path
export async function findCorrespondingFiles(filePath: string, additionalExports: CppFunction[] = []) {
    const withoutExt = path.basename(filePath, path.extname(filePath))
    const parentDir = path.dirname(filePath);

    let headerFile = Bun.file(path.join(parentDir, withoutExt + ".h"))
    if (!await headerFile.exists()) {
        headerFile = Bun.file(path.join(parentDir, withoutExt + ".hpp"))
    }

    if (!await headerFile.exists()) {
        return
    }

    let sourceFile = Bun.file(filePath)
    processFile(sourceFile, headerFile, additionalExports)
}

export async function processGlob(glob: Glob, additionalExports: CppFunction[] = []) {
    for await (const filePath of glob.scan({
        onlyFiles: true
    })) {
        if (EXCLUDE_DIRECTORIES.some(dir => filePath.includes(dir)))
            continue

        findCorrespondingFiles(filePath, additionalExports)
    }
}