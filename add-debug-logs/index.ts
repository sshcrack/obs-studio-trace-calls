import { $, Glob } from "bun";
import path from "path"
import c from "chalk-template"
import { processGlob } from './main/processor';
import { getExportedFunctions } from './main/extractor';

const directories = [
    "libobs",
    "libobs-d3d11",
    "libobs-opengl",
    "libobs-winrt",
    "plugins"
].map(e => path.join(import.meta.dir, "..", e))

export async function checkoutDirectory(path: string) {
    console.log(`Checking out directory: ${path}`);
    await $`git checkout ${path}`
}

const obsMainFile = path.join(import.meta.dir, "..", "libobs", "obs.h")
const mainExports = await getExportedFunctions(await Bun.file(obsMainFile).text());

for (const dir of directories) {
    console.log(`Checking out directory: ${dir}`);
    await checkoutDirectory(dir)

    if(process.argv[2] == "--checkout")
        continue

    const glob = new Glob(path.join(dir, "**", "*.{cpp,c}"))
    console.log(c`{green Processing directory: ${dir}}`);
    await processGlob(glob, mainExports)
}

