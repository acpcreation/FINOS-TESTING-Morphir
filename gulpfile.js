const { series, parallel, src, dest } = require('gulp');
const os = require('os')
const path = require('path')
const util = require('util')
const fs = require('fs')
const tmp = require('tmp')
const git = require('isomorphic-git')
const http = require('isomorphic-git/http/node')
const del = require('del')
const elmMake = require('node-elm-compiler').compile
const execa = require('execa');
const shell = require('shelljs')
const mocha = require('gulp-mocha');
const ts = require('gulp-typescript');
const tsProject = ts.createProject('./cli2/tsconfig.json')
const readFile = util.promisify(fs.readFile)

const config = {
    morphirJvmVersion: '0.10.0',
    morphirJvmCloneDir: tmp.dirSync()
}

const stdio = 'inherit';

async function clean() {
    del(['tests-integration/reference-model/Dockerfile'])
    return del(['dist'])
}

async function cloneMorphirJVM() {
    return await git.clone({
        fs,
        http,
        dir: config.morphirJvmCloneDir.name,
        url: 'https://github.com/finos/morphir-jvm',
        ref: `tags/v${config.morphirJvmVersion}`,
        singleBranch: true
    })
}

function copyMorphirJVMAssets() {
    const sdkFiles = path.join(config.morphirJvmCloneDir.name, 'morphir/sdk/core/src*/**')
    return src([sdkFiles]).pipe(dest('redistributable/Scala/sdk'))
}

async function cleanupMorphirJVM() {
    return del(config.morphirJvmCloneDir.name + '/**', { force: true });
}

function checkElmDocs() {
    return elmMake([], { docs: "docs.json" })
}

function make(rootDir, source, target) {
    return elmMake([source], { cwd: path.join(process.cwd(), rootDir), output: target }) // // nosemgrep : path-join-resolve-traversal
}

function makeCLI() {
    return make('cli', 'src/Morphir/Elm/CLI.elm', 'Morphir.Elm.CLI.js')
}

function makeCLI2() {
    return make('cli2', 'src/Morphir/Elm/CLI.elm', 'Morphir.Elm.CLI.js')
}

function makeDevCLI() {
    return make('cli', 'src/Morphir/Elm/DevCLI.elm', 'Morphir.Elm.DevCLI.js')
}

function makeDevServer() {
    return make('cli', 'src/Morphir/Web/DevelopApp.elm', 'web/index.js')
}

function makeDevServerAPI() {
    return make('cli', 'src/Morphir/Web/DevelopApp.elm', 'web/insightapp.js')
}

function makeInsightAPI() {
    return make('cli', 'src/Morphir/Web/Insight.elm', 'web/insight.js')
}

function makeTryMorphir() {
    return make('cli', 'src/Morphir/Web/TryMorphir.elm', 'web/try-morphir.html')
}

const buildCLI2 =
    parallel(
        compileCli2Ts,
        makeCLI2
    )

const build =
    series(
        checkElmDocs,
        makeCLI,
        makeDevCLI,
        buildCLI2,
        makeDevServer,
        makeDevServerAPI,
        makeInsightAPI,
        makeTryMorphir
    )


function morphirElmMake(projectDir, outputPath, options = {}) {
    args = ['./cli/morphir-elm.js', 'make', '-p', projectDir, '-o', outputPath]
    if (options.typesOnly) {
        args.push('--types-only')
    }
    console.log("Running: " + args.join(' '));
    return execa('node', args, { stdio })
}

function morphirElmMakeRunOldCli(projectDir, outputPath, options = {}) {
    args = ['./cli/morphir-elm.js', 'make', '-f', '-p', projectDir, '-o', outputPath]
    if (options.typesOnly) {
        args.push('--types-only')
    }
    console.log("Running: " + args.join(' '));
    return execa('node', args, { stdio })
}

function morphirElmMake2(projectDir, outputPath, options = {}) {
    args = ['./cli2/lib/morphir.js', 'make', '-p', projectDir, '-o', outputPath]
    if (options.typesOnly) {
        args.push('--types-only')
    }
    console.log("Running: " + args.join(' '));
    return execa('node', args, { stdio })
}

function morphirElmGen(inputPath, outputDir, target, customConfig) {
    args = ['./cli/morphir-elm.js', 'gen', '-i', inputPath, '-o', outputDir, '-t', target]

    if(customConfig)
        args = [ ...args, "--custom-config", customConfig]

    console.log("Running: " + args.join(' '));
    return execa('node', args, { stdio })
}

function morphirDockerize(projectDir, options = {}) {
    let command = 'dockerize'
    let funcLocation = './cli2/lib/morphir-dockerize.js'
    let projectDirFlag = '-p'
    let overwriteDockerfileFlag = '-f'
    let projectDirArgs = [ projectDirFlag, projectDir ]
    args = [
        funcLocation, 
        command, 
        projectDirArgs.join(' '), 
        overwriteDockerfileFlag
    ]
    console.log("Running: "+ args.join);
    return execa('node', args, {stdio})
}


async function testUnit(cb) {
    await execa('elm-test');
}

async function compileCli2Ts() {
    src('./cli2/*.ts').pipe(tsProject()).pipe(dest('./cli2/lib/'))
}

function testIntegrationClean() {
    return del([
        'tests-integration/generated',
        'tests-integration/reference-model/morphir-ir.json'
    ])
}


async function testIntegrationMake(cb) {

    await morphirElmMake(
        './tests-integration/reference-model',
        './tests-integration/generated/refModel/morphir-ir.json')

    await morphirElmMakeRunOldCli(
        './tests-integration/reference-model',
        './tests-integration/generated/refModel/morphir-ir.json')
}

async function testIntegrationDockerize() {
    await morphirDockerize(
        './tests-integration/reference-model',
    )
}

async function testIntegrationMorphirTest(cb) {
    src('./tests-integration/generated/refModel/morphir-ir.json')
        .pipe(dest('./tests-integration/reference-model/'))
    await execa(
        'node',
        ['./cli/morphir-elm.js', 'test', '-p', './tests-integration/reference-model'],
        { stdio },
    )
}

async function testIntegrationGenScala(cb) {
    await morphirElmGen(
        './tests-integration/generated/refModel/morphir-ir.json',
        './tests-integration/generated/refModel/src/scala/',
        'Scala')
}

async function testIntegrationBuildScala(cb) {
    // try {
    //     await execa(
    //         'mill', ['__.compile'],
    //         { stdio, cwd: 'tests-integration' },
    //     )
    // } catch (err) {
    //     if (err.code == 'ENOENT') {
    console.log("Skipping testIntegrationBuildScala as `mill` build tool isn't available.");
    //     } else {
    //         throw err;
    //     }
    // }
}

async function testIntegrationMakeSpark(cb) {
    await morphirElmMakeRunOldCli(
        './tests-integration/spark/model',
        './tests-integration/generated/sparkModel/morphir-ir.json')
}

async function testIntegrationGenSpark(cb) {
    await morphirElmGen(
        './tests-integration/generated/sparkModel/morphir-ir.json',
        './tests-integration/generated/sparkModel/src/spark/',
        'Spark',
        './tests-integration/spark/model/spark.config.json')
}

async function testIntegrationBuildSpark(cb) {
     try {
         await execa(
             'mill', ['__.compile'],
             { stdio, cwd: 'tests-integration' },
         )
     } catch (err) {
         if (err.code == 'ENOENT') {
    console.log("Skipping testIntegrationBuildSpark as `mill` build tool isn't available.");
         } else {
             throw err;
         }
     }
}

async function testIntegrationTestSpark(cb) {
     try {
         await execa(
             'mill', ['spark.test'],
             { stdio, cwd: 'tests-integration' },
         )
     } catch (err) {
         if (err.code == 'ENOENT') {
    console.log("Skipping testIntegrationTestSpark as `mill` build tool isn't available.");
         } else {
             throw err;
         }
     }
}

// Generate TypeScript API for reference model.
async function testIntegrationGenTypeScript(cb) {
    await morphirElmGen(
        './tests-integration/generated/refModel/morphir-ir.json',
        './tests-integration/generated/refModel/src/typescript/',
        'TypeScript')
}

// Compile generated Typescript API and run integration tests.
function testIntegrationTestTypeScript(cb) {
    return src('tests-integration/typescript/TypesTest-refModel.ts')
        .pipe(mocha({ require: 'ts-node/register' }));
        
}


async function testCreateCSV(cb) {
    if (!shell.which('bash')){
        console.log("Automatically creating CSV files is not available on this platform");
    } else {
        code_no = shell.exec('bash ./create_csv_files.sh', {cwd : './tests-integration/spark/elm-tests/tests'}).code
        if (code_no != 0){
            console.log('ERROR: CSV files cannot be created')
            return false;
        }
    }
}

testIntegrationSpark = series(
    testIntegrationMakeSpark,
    testIntegrationGenSpark,
    testIntegrationBuildSpark,
    testIntegrationTestSpark,
)

const testIntegration = series(
    testIntegrationClean,
    testIntegrationMake,
    testCreateCSV,
    parallel(
        testIntegrationMorphirTest,
	testIntegrationSpark,
        series(
            testIntegrationGenScala,
            testIntegrationBuildScala,
        ),
        series(
            testIntegrationGenTypeScript,
            testIntegrationTestTypeScript,
        ),
    ),
    testIntegrationDockerize
)


async function testMorphirIRMake(cb) {
    await morphirElmMake('.', 'tests-integration/generated/morphirIR/morphir-ir.json',
        { typesOnly: true })
}

// Generate TypeScript API for Morphir.IR itself.
async function testMorphirIRGenTypeScript(cb) {
    await morphirElmGen(
        './tests-integration/generated/morphirIR/morphir-ir.json',
        './tests-integration/generated/morphirIR/src/typescript/',
        'TypeScript')
}

// Compile generated Typescript API and run integration tests.
function testMorphirIRTestTypeScript(cb) {
    return src('tests-integration/typescript/CodecsTest-Morphir-IR.ts')
        .pipe(mocha({ require: 'ts-node/register' }));
}

// Make sure all dependencies are permitted in highly-restricted environments as well
async function checkPackageLockJson() {
    const packageLockJson = JSON.parse((await readFile('package-lock.json')).toString())
    const hasRuntimeDependencyOnPackage = (packageName) => {
        const runtimeDependencyInPackages = 
            packageLockJson.packages 
            && packageLockJson.packages[`node_modules/${packageName}`]
            && !packageLockJson.packages[`node_modules/${packageName}`].dev
        const runtimeDependencyInDependencies = 
            packageLockJson.dependencies 
            && packageLockJson.dependencies[packageName]
            && !packageLockJson.dependencies[packageName].dev
        return runtimeDependencyInPackages || runtimeDependencyInDependencies    
    }
    if (hasRuntimeDependencyOnPackage('binwrap')) {
        throw Error('Runtime dependency on binwrap was detected!')
    }
}

testMorphirIR = series(
    testMorphirIRMake,
    testMorphirIRGenTypeScript,
    testMorphirIRTestTypeScript,
)


const test =
    parallel(
        testUnit,
        testIntegration,
        // testMorphirIR,
    )

const csvfiles=series(
        testCreateCSV,
)

exports.clean = clean;
exports.makeCLI = makeCLI;
exports.makeDevCLI = makeDevCLI;
exports.buildCLI2 = buildCLI2;
exports.build = build;
exports.test = test;
exports.csvfiles=csvfiles;
exports.testIntegration = testIntegration;
exports.testIntegrationSpark = testIntegrationSpark;
exports.testMorphirIR = testMorphirIR;
exports.testMorphirIRTypeScript = testMorphirIR;
exports.checkPackageLockJson = checkPackageLockJson;
exports.default =
    series(
        clean,
        checkPackageLockJson,
        series(
            cloneMorphirJVM,
            copyMorphirJVMAssets,
            cleanupMorphirJVM
        ),
        build
    );
