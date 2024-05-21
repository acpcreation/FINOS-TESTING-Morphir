import * as util from "util";
import * as fs from "fs";
import {z} from "zod";
import {getUri} from "get-uri";
import {labelToName, decode} from "whatwg-encoding";
import {Readable} from "stream";
const parseDataUrl = require("data-urls");
const fsReadFile = util.promisify(fs.readFile);

const DataUrl = z.string().trim().transform((val, ctx) => {
  const parsed = parseDataUrl(val)
  if(parsed == null) {
    ctx.addIssue({
      code: z.ZodIssueCode.custom,
      message: "Not a valid data url"
    })
    return z.NEVER;
  }
  return parsed;
});

const FileUrl = z.string().trim().url().transform((val,ctx) => {
  if(!val.startsWith("file:")){
    ctx.addIssue({
      code: z.ZodIssueCode.custom,
      message: "Not a valid file url"
    })
    return z.NEVER;
  }
  return new URL(val);
});

const PathOrUrl = z.union([FileUrl, z.string().trim().min(1)]);

const DependencyBase = z.object({
  source: z.enum(["dependencies", "localDependencies", "includes"]).optional()
});

const UnclassifiedDependency = DependencyBase.extend({
  kind: z.literal("unclassified"),
  path: z.string()
});


const FileDependency = DependencyBase.extend({
  kind: z.literal("file"),
  pathOrUrl: PathOrUrl,
});

const DataUrlDependency = DependencyBase.extend({
  kind: z.literal("dataUrl"),
  url: DataUrl
})

const LocalDependency = z.discriminatedUnion("kind",[
    FileDependency,
    DataUrlDependency
]);

const HttpDependency = DependencyBase.extend({
  kind: z.literal("http"),
  url: z.string().url()
});

const GithubData = z.object({
  owner: z.string(),
  repo: z.string(),
  baseUrl: z.string().optional()
});

const GithubConfig = z.union([GithubData, z.string()]);

const GithubDependency = DependencyBase.extend({
  kind: z.literal("github"),
  config: GithubConfig,
});

const RemoteDependency = z.discriminatedUnion("kind", [
  HttpDependency,
  GithubDependency
]);

const DependencyInfo = z.discriminatedUnion("kind", [
  FileDependency,
  DataUrlDependency,
  HttpDependency,
  GithubDependency,
  UnclassifiedDependency
]);

const ClassifiedDependency = z.discriminatedUnion("kind",[
  FileDependency,
  DataUrlDependency,
  HttpDependency,
  GithubDependency
]);


const DependencySettings = z.union([DataUrl, FileUrl, z.string().trim()])
const Dependencies = z.array(DependencySettings).default([]);

export const DependencyConfig = z.object({
  dependencies: Dependencies,
  localDependencies: z.array(z.string()).default([]),
  includes: z.array(z.string()).default([]),
});

const MorphirDistribution = z.tuple([z.string()]).rest(z.unknown());
const MorphirIRFile = z.object({
  formatVersion: z.number().int(),
  distribution: MorphirDistribution
}).passthrough();

type DataUrl = z.infer<typeof DataUrl>;
type FileUrl = z.infer<typeof FileUrl>;
type LocalDependency = z.infer<typeof LocalDependency>;
type PathDependency = z.infer<typeof FileDependency>;
type PathOrUrl = z.infer<typeof PathOrUrl>;
type DataUrlDependency = z.infer<typeof DataUrlDependency>;
type UnclassifiedDependency = z.infer<typeof UnclassifiedDependency>;
type ClassifiedDependency = z.infer<typeof ClassifiedDependency>;
type HttpDependency = z.infer<typeof HttpDependency>;
type GithubDependency = z.infer<typeof GithubDependency>;
type RemoteDependency = z.infer<typeof RemoteDependency>;
type GithubData = z.infer<typeof GithubData>;
type GithubConfig = z.infer<typeof GithubConfig>;
type DependencyInfo = z.infer<typeof DependencyInfo>;
type MorphirDistribution = z.infer<typeof MorphirDistribution>;
type MorphirIRFile = z.infer<typeof MorphirIRFile>;
export type DependencyConfig = z.infer<typeof DependencyConfig>;

function instanceOfFileUrl(object:any): object is FileUrl {
  return 'protocol' in object.members;
}

function toLocalDependency(dependency: string): LocalDependency {
  const dataUrl = parseDataUrl(dependency);
  if(dataUrl == null){
    return {kind: "file", pathOrUrl: PathOrUrl.parse(dependency)};
  } else {
    return {kind:"dataUrl", url: dataUrl};
  }
}

export async function loadDependencies(dependencyConfig:DependencyConfig) {
  let localDependencies:LocalDependency[] = (dependencyConfig.localDependencies ?? []).map(toLocalDependency).map((d) => {
    d.source = "localDependencies";
    return d;
  });
  if(dependencyConfig.includes) {
    const includes = dependencyConfig.includes.map(toLocalDependency).map((d) => {
      d.source = "includes";
      return d;
    });
    localDependencies.push(...includes);
  }
  if(dependencyConfig.dependencies) {
    const deps = dependencyConfig.dependencies.map(async (input) => {
      let parseResult = DataUrl.safeParse(input);
      if (parseResult.success) {
        localDependencies.push( {kind: "dataUrl", url: parseResult.data, source: "dependencies"} );
      } else {
        let parseResult = FileUrl.safeParse(input);
        if(parseResult.success) {
          localDependencies.push({kind: "file", pathOrUrl: parseResult.data, source:"dependencies"});
        }
      }
    })
  }
  return await loadLocalDependencies(localDependencies);
}

async function loadLocalDependencies(dependencies:LocalDependency[]): Promise<any[]> {
  const promises = dependencies.map(async dependency => {
    switch (dependency.kind) {
      case 'file':
        if(typeof dependency.pathOrUrl === "string") {
          console.error("Handling path: ", dependency.pathOrUrl);
          if (fs.existsSync(dependency.pathOrUrl)) {
            const irJsonStr = (await fsReadFile(dependency.pathOrUrl)).toString();
            return JSON.parse(irJsonStr);
          } else {
            throw new LocalDependencyNotFound(`Local dependency at path "${dependency.pathOrUrl}" does not exist`, dependency.pathOrUrl);
          }
        } else {
          console.error("Handling url: ", dependency.pathOrUrl);
          try {
            const stream = await getUri(dependency.pathOrUrl);
            const jsonBuffer = await toBuffer(stream);
            return JSON.parse(jsonBuffer.toString());
          } catch (err:any) {
            if(err.code === 'ENOTFOUND') {
              throw new LocalDependencyNotFound(`Local dependency at url "${dependency.pathOrUrl}" does not exist`, dependency.pathOrUrl, err);
            } else {
              throw err;
            }
          }
        }
        break;
      case 'dataUrl':
        const encodingName = labelToName(dependency.url.mimeType.parameters.get("charset") || "utf-8") || "UTF-8";
        const bodyDecoded = decode(dependency.url.body, encodingName);
        return JSON.parse(bodyDecoded);
    }
  })
  return Promise.all(promises);
}

async function loadHttpDependencies(dependencies:HttpDependency[]): Promise<any[]> {
  const promises = dependencies.map(async dependency => {

  });
  return Promise.all(promises);
}

function isRemoteDependency(dependency:DependencyInfo): undefined | boolean {
  switch (dependency.kind) {
    case 'dataUrl':
    case 'file':
      return false;
    case 'http':
      return true;
    case 'github':
      return true;
    default:
      return undefined;
  }
}

async function toBuffer(stream: Readable): Promise<Buffer> {
  const chunks: Buffer[] = [];
  for await (const chunk of stream) {
    chunks.push(chunk);
  }
  return Buffer.concat(chunks);
}

class LocalDependencyNotFound extends Error {
  constructor(message:string, pathOrUrl?:PathOrUrl, cause?:Error) {
    super(message);
    this.name = "LocalDependencyNotFound";
    if(cause){
      this.cause = cause;
    }
    if(pathOrUrl) {
      this.pathOrUrl = pathOrUrl;
    }
  }

  cause?:Error;
  pathOrUrl?:PathOrUrl;

}