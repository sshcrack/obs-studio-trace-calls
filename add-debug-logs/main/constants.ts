export const EXPORTED_FUNCTION_REGEX = /EXPORT\s+(?:[a-zA-Z0-9_*]+\s+)+([a-zA-Z0-9_]+)\s*\(/g;
export const FULL_FUNCTION_REGEX = (functionName: string) => new RegExp(`EXPORT\\s+(?:[a-zA-Z0-9_*]+\\s+)+${functionName}\\s*\\(([^)]*)\\)`, "s")

export const LOGGING_FUNCTION = "blog"
export const LOG_LEVEL = "LOG_DEBUG"
export const LOG_INCLUDE = "<util/base.h>"


export const EXCLUDE_DIRECTORIES = [
    "/util/"
]