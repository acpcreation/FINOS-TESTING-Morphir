// imports
import * as fs from "fs";
import * as util from "util"
import * as path from "path"


// process constants
const writeFile = util.promisify(fs.writeFile)
const rmdir = util.promisify(fs.rmSync)
const execa = require("execa")

// cadl model related paths
const projectDir = path.join("tests-integration","cadl", "model")
const generatedCadl = path.join(projectDir, "dist")
const morphirIR = path.join(projectDir,"morphir-ir.json")

// cli stuffs
const cli = require("../../../../cli/cli.js")
const makeCmdOpts = { typesOnly: false, output: projectDir }
const genCmdOpts = { target: "Cadl", copy_deps: true}

// test
describe("Validating Generated Cadl", () => {
    test("Compiling Cadl", async () => {
        const opts = {recursive: true, force: true}

        // run make cmd
        const IR = await cli.make(projectDir, makeCmdOpts)

        // write IR
        await writeFile(morphirIR,JSON.stringify(IR))

        // run gen cmd
        await cli.gen(morphirIR, generatedCadl, genCmdOpts)


        // compile generated Cadl to look for errors
        const args = ['compile', path.join(generatedCadl,"TestModel.cadl")]
        const {stdout} = await execa('cadl', args)
        
        expect(stdout).toContain("Compilation completed successfully")
    })
})

