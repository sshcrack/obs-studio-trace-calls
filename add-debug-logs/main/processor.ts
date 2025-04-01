import { LOG_INCLUDE, LOG_LEVEL, LOGGING_FUNCTION } from './constants'
import { getFormatFromType, type CppFunction, type CppParameter } from './extractor'
export function reparseParameters(parameters: CppParameter[], lines: string[]) {
    // Join lines and clean up whitespace
    const fullStr = lines.join(" ").split("\r").join("").replace(/\s+/g, " ");
    const beginParams = fullStr.indexOf("(");
    const endParams = fullStr.lastIndexOf(")");

    if (beginParams === -1 || endParams === -1) {
        return parameters;
    }

    const paramsStr = fullStr.substring(beginParams + 1, endParams).trim();

    // Clear list of parameters
    parameters.splice(0, parameters.length);

    // Split by commas that aren't inside brackets/parentheses
    let parenLevel = 0;
    let bracketLevel = 0;
    let segments: string[] = [];
    let currentSegment = '';

    for (let i = 0; i < paramsStr.length; i++) {
        const char = paramsStr[i];
        if (char === '(') parenLevel++;
        else if (char === ')') parenLevel--;
        else if (char === '[') bracketLevel++;
        else if (char === ']') bracketLevel--;

        if (char === ',' && parenLevel === 0 && bracketLevel === 0) {
            segments.push(currentSegment.trim());
            currentSegment = '';
        } else {
            currentSegment += char;
        }
    }

    if (currentSegment.trim()) {
        segments.push(currentSegment.trim());
    }

    // Process each parameter segment
    for (const segment of segments) {
        parseParameter(segment, parameters);
    }

    return parameters;
}
function parseParameter(paramStr: string, parameters: CppParameter[]) {
    // Handle array parameters with size indicators like "const float color[4]"
    let match = paramStr.match(/^((?:const\s+)?[a-zA-Z0-9_]+(?:[:_][a-zA-Z0-9_]+)*)\s+(\**)\s*([a-zA-Z0-9_]+)(?:\[(\d+)\])?$/);

    if (match) {
        const type = match[1];
        const pointers = match[2] || '';
        const name = match[3];
        const arraySize = match[4] ? `[${match[4]}]` : '';

        parameters.push({
            name: name,
            type: `${type} ${pointers}${arraySize}`,
            isPointer: pointers.length > 0 || arraySize.length > 0
        });
        return;
    }

    // Pattern for arrays without size like: uint8_t *output[]
    match = paramStr.match(/^((?:const\s+)?[a-zA-Z0-9_]+(?:[:_][a-zA-Z0-9_]+)*)\s+(\**)\s*([a-zA-Z0-9_]+)(\[\])$/);

    if (match) {
        const type = match[1];
        const pointers = match[2] || '';
        const name = match[3];

        parameters.push({
            name: name,
            type: `${type} ${pointers}[]`,
            isPointer: true // Arrays are essentially pointers
        });
        return;
    }

    // Handle more complex cases: const uint8_t *const input[]
    match = paramStr.match(/^((?:const\s+)?[a-zA-Z0-9_]+(?:[:_][a-zA-Z0-9_]+)*)\s+(\*(?:\s*const\s+)?\**)\s*([a-zA-Z0-9_]+)(?:\[(\d*)\])?$/);

    if (match) {
        const type = match[1];
        const pointers = match[2];
        const name = match[3];
        const arraySize = match[4] ? `[${match[4]}]` : '';

        parameters.push({
            name: name,
            type: `${type} ${pointers}${arraySize}`,
            isPointer: true
        });
        return;
    }

    // Pattern for function pointer parameters - "void (*callback)(void *)"
    match = paramStr.match(/^((?:const\s+)?[a-zA-Z0-9_]+(?:[:_][a-zA-Z0-9_]+)*)\s+\(\*([a-zA-Z0-9_]+)\)\s*\([^)]*\)$/);

    if (match) {
        const returnType = match[1];
        const name = match[2];

        parameters.push({
            name: name,
            type: `${returnType} (*)(...)`,
            isPointer: true
        });
        return;
    }

    // If we get here, we couldn't parse the parameter with our standard patterns
    // Try a simple fallback approach
    if (paramStr.trim()) {
        // Split the parameter into words
        const parts = paramStr.trim().split(/\s+/);

        // Find potential name - last part without []
        const name = parts.pop()?.replace(/\[\d*\]$/, '') || 'unnamed';

        // Rest is type
        const type = parts.join(' ');

        parameters.push({
            name: name,
            type: type,
            isPointer: paramStr.includes('*') || paramStr.includes('[')
        });
    }
}

export async function processSource(sourceContent: string, functions: Map<string, CppFunction>) {
    const sourceLines = sourceContent.split("\n")
    const functionsFound = new Set<CppFunction>()

    let bracesCount = 0
    const funcArray = Array.from(functions.values())

    for (let i = 0; i < sourceLines.length; i++) {
        const line = sourceLines[i].trim()
        const prevCount = bracesCount
        bracesCount += line.split("{").length - 1
        bracesCount -= line.split("}").length - 1

        const hasNewFunc = prevCount === 0 && bracesCount === 1
        if (!hasNewFunc)
            continue

        let funcBegin = i;
        // Finding beginning of function
        while (funcBegin > 0 && !sourceLines[funcBegin].includes("(") && !sourceLines[funcBegin].includes("struct ")) {
            funcBegin--;
        }

        const thatLine = sourceLines[funcBegin].trim()

        const func = funcArray.find(f => thatLine.includes(f.name))
        if (!func)
            continue

        reparseParameters(func.params, sourceLines.slice(funcBegin, i + 1))

        functionsFound.add(func)

        const params = func.params.map(p => {
            const format = getFormatFromType(p.type)
            if (format)
                return {
                    formatter: format,
                    name: p.name
                }

            if (p.isPointer)
                return {
                    formatter: "%p",
                    name: p.name,
                }

            return p.name
        })

        // With stuff like %s, %d
        let formatString = params.map(e => typeof e === "object" ? `${e.name}: ${e.formatter}` : `${e}: no formatter for this`).join(", ")
        // With actual variable names
        let argumentStr = params.map(e => typeof e === "object" && `${e.name}`).filter(e => e !== null).join(", ")

        sourceLines[i] = sourceLines[i] + `${LOGGING_FUNCTION}(${LOG_LEVEL}, "${func.name} called with params: ${formatString}"${params.length !== 0 ? "," + argumentStr : ""});`
    }

    for (const func of functionsFound) {
        functions.delete(func.name)
    }

    let afterIncludes = 0
    for (let i = 0; i < sourceLines.length; i++) {
        const line = sourceLines[i].trim()
        if (line.startsWith("#include"))
            afterIncludes = i
    }

    sourceLines[afterIncludes] = `#include ${LOG_INCLUDE}\n` + sourceLines[afterIncludes]

    return sourceLines.join("\n")
}