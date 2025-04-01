import { $, Glob } from "bun";
import path from "path"
import c from "chalk-template"
import { getExportedFunctions, type CppFunction } from './main/extractor';
import { processSource } from './main/processor';

const directories = [
    "libobs",
    //"libobs-d3d11",
    //"libobs-opengl",
    //"libobs-winrt",
    //"plugins"
].map(e => path.join(import.meta.dir, "..", e))

export async function checkoutDirectory(path: string) {
    console.log(`Checking out directory: ${path}`);
    await $`git checkout ${path}`
}

const exportedFunctions = new Map<string, CppFunction>()
for (const dir of directories) {
    console.log(`Checking out directory: ${dir}`);
    await checkoutDirectory(dir)

    if (process.argv[2] == "--checkout-only")
        continue

    const headerGlob = new Glob(path.join(dir, "**", "*.{h,hpp}"))
    console.log(c`{green Processing directory: ${dir}}`);

    for await (const filePath of headerGlob.scan()) {
        if (filePath.includes("frontend") || filePath.includes("\\util\\") || filePath.includes("/util/"))
            continue;

        const content = await Bun.file(filePath).text()
        const functions = await getExportedFunctions(content)
        functions.forEach(e => exportedFunctions.set(e.name, e))
    }
}

if (process.argv[2] == "--checkout-only")
    process.exit(0)

console.log(c`{green Found ${exportedFunctions.size} exported functions}`);
if (false) {
    const source = await Bun.file(path.join(import.meta.dir, "..", "libobs", "obs-data.c")).text()
    const returnVal = await processSource(source, exportedFunctions)
    await Bun.write("out.c", returnVal)

    console.log("Left over functions:", exportedFunctions.size);
    process.exit(0)
}

for (const dir of directories) {
    console.log(c`{green Processing directory: ${dir}}`);
    const sourceGlob = new Glob(path.join(dir, "**", "*.{cpp,cc,cxx,c}"))
    for await (const filePath of sourceGlob.scan()) {
        const content = await Bun.file(filePath).text()
        const returnVal = await processSource(content, exportedFunctions)

        await Bun.write(filePath, returnVal)
    }
}
console.log("Left over functions:", exportedFunctions.size);