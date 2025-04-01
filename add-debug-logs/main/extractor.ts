import { EXPORTED_FUNCTION_REGEX, FULL_FUNCTION_REGEX } from './constants';

export type CppParameter = {
    name: string
    type: string,
    isPointer: boolean
}

export type CppFunction = {
    name: string
    params: CppParameter[]
}

export async function getExportedFunctions(headerContent: string): Promise<string[]> {
    const exportedFunctions = [];
    let match: RegExpExecArray | null;

    while ((match = EXPORTED_FUNCTION_REGEX.exec(headerContent)) !== null) {
        const functionName = match[3].replaceAll("*", "").trim();

        // Find the full function declaration by searching for the function name
        const functionRegex = FULL_FUNCTION_REGEX(functionName);
        const functionMatch = functionRegex.exec(headerContent);

        if (functionMatch) {
            exportedFunctions.push(functionName);
        }
    }

    return exportedFunctions;
}

function escapeRegex(str: string) {
    return str.replace(/[/\-\\^$*+?.()|[\]{}]/g, '\\$&');
}

/**
 * Gets the line number of a function declaration in the source file.
 * @param sourceContent The content of the source file
 * @param functionName The name of the function to find
 * @returns The line number where the function is declared, or -1 if not found
 */
export function getFunctionLineNumber(sourceContent: string, functionName: string): number {
    // Look for function definition pattern
    const functionRegex = new RegExp(String.raw`(${escapeRegex(functionName)}\s*\(.*\)\s*\{)`, '');
    const match = functionRegex.exec(sourceContent);

    if (!match) {
        return -1;
    }

    // Count line breaks before the match position
    const contentUpToMatch = sourceContent.substring(0, match.index);
    const lineBreaks = contentUpToMatch.match(/\n/g);

    // Line numbers are 1-based
    return lineBreaks ? lineBreaks.length + 1 : 1;
}

export function getFormatFromType(type: string): string | null {
    const parts = type.split(" ")

    const map = {
        "char": "%s",
        "int": "%d",
        "float": "%f",
        "double": "%lf",
        "bool": "%d",
        "long long": "%lld",
        "long": "%ld",
    }

    const anyMatch = Object.keys(map).find(e => parts.some(x => x.includes(e)))
    if (anyMatch) {
        return map[anyMatch as keyof typeof map]
    }

    return null
}