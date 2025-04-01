import { LOG_LEVEL, LOGGING_FUNCTION } from './constants'
import { getFormatFromType, type CppFunction } from './extractor'

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

        sourceLines[i] = sourceLines[i] + `${LOGGING_FUNCTION}(${LOG_LEVEL}, "${func.name} called with params: ${formatString}", ${argumentStr});`
    }

    for (const func of functionsFound) {
        functions.delete(func.name)
    }

    return sourceLines.join("\n")
}