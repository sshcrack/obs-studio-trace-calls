import { EXPORTED_FUNCTION_REGEX, FULL_FUNCTION_REGEX } from './constants';

export type CppFunction = {
    name: string
    params: {
        name: string
        type: string,
        isPointer: boolean
    }[]
}

export async function getExportedFunctions(headerContent: string): Promise<CppFunction[]> {
    const exportedFunctions: CppFunction[] = [];
    let match: RegExpExecArray | null;

    while ((match = EXPORTED_FUNCTION_REGEX.exec(headerContent)) !== null) {
        const functionName = match[1];

        // Find the full function declaration by searching for the function name
        const functionRegex = FULL_FUNCTION_REGEX(functionName);
        const functionMatch = functionRegex.exec(headerContent);

        if (functionMatch) {
            const paramsString = functionMatch[1];

            const params = paramsString.split(',')
                .filter(param => param.trim() !== '')
                .map(param => {
                    const paramTrimmed = param.trim();
                    // Check if parameter is a pointer
                    const isPointer = paramTrimmed.includes('*');

                    // Split by spaces or tabs
                    const parts = paramTrimmed.split(/\s+/);

                    // Last part could be the parameter name, possibly with * for pointers
                    let name = parts[parts.length - 1].replace(/[*]/g, '');
                    // Everything else is the type
                    let type = parts.slice(0, parts.length - 1).join(' ');

                    // Handle case where pointer is attached to type instead of name
                    if (type.includes('*')) {
                        type = type.replace(/[*]/g, '').trim();
                    }

                    return { name, type, isPointer };
                });

            exportedFunctions.push({
                name: functionName,
                params
            });
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
    const functionRegex = new RegExp(`(^|\\s+)${functionName}\\s*\\([^{]*?\\)\\s*\\{(?!\\s*blog\\s*\\(\\s*LOG_DEBUG)`, 'gm');
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