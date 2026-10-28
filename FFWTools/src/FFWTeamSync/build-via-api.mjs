import fs from 'node:fs/promises';
import path from 'node:path';
import { createRequire } from 'node:module';
import { Worker } from 'node:worker_threads';
import { createHash } from 'node:crypto';
import { prepareNative } from './prepare-native.mjs';
// Public build APIs only. No exec/spawn, command interpreter, batch or remote CI.
// MSBuild's standard C++ tasks invoke the installed compiler/librarian/linker.
export async function buildNative({root,frameworkDll,dotnetPackageDirectory,visualStudio='C:/Program Files/Microsoft Visual Studio/2022/Community',windowsDirectory='C:/Windows',includeTests=true}) {
 const require=createRequire(import.meta.url);const dir=path.join(root,'FFWTools/src/FFWTeamSync');
 const ms=path.join(visualStudio,'MSBuild/Current/Bin/amd64');const prepared=await prepareNative({root,frameworkDll});
 const source=path.join(dir,'BuildApi.cs');const hash=createHash('sha256').update(await fs.readFile(source)).digest('hex').slice(0,16);
 const helper=path.join(prepared.directory,'api-'+hash+'.dll');
 const framework=path.join(windowsDirectory,'Microsoft.NET/Framework64/v4.0.30319');
 const dotnetPath=tfm=>dotnetPackageDirectory?path.join(dotnetPackageDirectory,tfm+'.js'):require.resolve('node-api-dotnet/'+tfm);
 if(!await fs.stat(helper).catch(()=>null)){
  const worker=new Worker(path.join(dir,'compile-managed-worker.cjs'),{workerData:{package:dotnetPath('net8.0'),roslyn:path.join(visualStudio,'MSBuild/Current/Bin/Roslyn'),source,references:['mscorlib.dll','System.dll','System.Core.dll'].map(n=>path.join(framework,n)).concat([path.join(ms,'Microsoft.Build.dll'),path.join(ms,'Microsoft.Build.Framework.dll')]),name:'FFW.NativeBuild3',output:helper}});
  try{const result=await new Promise((resolve,reject)=>{worker.once('message',resolve);worker.once('error',reject);});if(!result.ok)throw Error(JSON.stringify(result));}finally{await worker.terminate();}
 }
 const dotnet=require(dotnetPath('net472'));dotnet.load(helper);
 const projects=['FFWTeamSyncLan.vcxproj',...(includeTests?['LanTransportTests.vcxproj']:[])];const results=[];
 for(const project of projects){const log=path.join(prepared.directory,project+'.log');const result=dotnet.FFW.NativeBuild3.Launcher.Build(helper,ms,path.join(dir,project),visualStudio,log);results.push({project,result,log});if(result!=='Success')throw Error('Native build failed; see '+log);}
 return {prepared,results,runtime:path.join(prepared.directory,'runtime/main.dll'),tests:includeTests?path.join(prepared.directory,'tests/LanTransportTests.dll'):undefined};
}
