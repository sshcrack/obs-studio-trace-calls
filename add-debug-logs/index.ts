import { $, Glob } from "bun";
import c from "chalk-template";
import path from "path";
import { getExportedFunctions } from './main/extractor';
import { processSource } from './main/processor';

const directories = [
    "libobs",
].map(e => path.join(import.meta.dir, "..", e))

const excludeFiles = [
    "graphics"
]

export async function checkoutDirectory(path: string) {
    console.log(`Checking out directory: ${path}`);
    await $`git checkout ${path}`
}

const exportedFunctions = new Set<string>()
for (const dir of directories) {
    console.log(`Checking out directory: ${dir}`);
    await checkoutDirectory(dir)

    if (process.argv.includes("--checkout-only"))
        continue

    const headerGlob = new Glob(path.join(dir, "**", "*.{h,hpp}"))
    console.log(c`{green Processing directory: ${dir}}`);

    for await (const filePath of headerGlob.scan()) {
        if (filePath.includes("frontend") || filePath.includes("\\util\\") || filePath.includes("/util/"))
            continue;

        const content = await Bun.file(filePath).text()
        const functions = await getExportedFunctions(content)
        functions.forEach(e => exportedFunctions.add(e))
    }
}

if (process.argv.includes("--checkout-only"))
    process.exit(0)

console.log(c`{green Found ${exportedFunctions.size} exported functions}`);
await Bun.write("exported_functions.json", JSON.stringify(Array.from(exportedFunctions), null, 2))
if (false) {
    const source = await Bun.file(path.join(import.meta.dir, "..", "libobs", "obs-data.c")).text()
    const returnVal = await processSource(source, exportedFunctions)
    //await Bun.write("out.c", returnVal)

    console.log("Left over functions:", exportedFunctions.size);
    process.exit(0)
}

for (const dir of directories) {
    console.log(c`{green Processing directory: ${dir}}`);
    const sourceGlob = new Glob(path.join(dir, "**", "*.{cpp,cc,cxx,c}"))
    for await (const filePath of sourceGlob.scan()) {
        if (excludeFiles.some(e => filePath.includes(e)))
            continue

        const content = await Bun.file(filePath).text()
        const returnVal = await processSource(content, exportedFunctions)

        await Bun.write(filePath, returnVal)
    }
}
console.log("Left over functions:", exportedFunctions.size);
await Bun.write("leftover.txt", Array.from(exportedFunctions).join("\n"))