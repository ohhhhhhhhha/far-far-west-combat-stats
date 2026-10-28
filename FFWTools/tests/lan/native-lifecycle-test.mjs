import assert from 'node:assert/strict';
export function verifyLifecycle({createNative,probe}){
 const starts=()=>probe.Read('lan_startup_count'),ends=()=>probe.Read('lan_cleanup_count');
 const baseStart=starts(),baseEnd=ends();const native=createNative();
 try {const h=native.Create();assert.equal(starts(),baseStart,'constructing a transport must not initialize Winsock');
  native.Status(h);native.Id(h);assert.equal(starts(),baseStart,'read-only status must not initialize Winsock');
  assert.notEqual(native.Configure(h,'host','invalid','127.0.0.1',0,''),'');assert.equal(starts(),baseStart);
  assert.equal(native.Configure(h,'host','7','127.0.0.1',0,''),'');assert.equal(starts(),baseStart+1);
  native.Stop(h);assert.equal(ends(),baseEnd+1);native.Stop(h);assert.equal(ends(),baseEnd+1);
  assert.equal(native.Configure(h,'host','7','127.0.0.1',0,''),'');assert.equal(starts(),baseStart+2);
  native.Dispose();assert.equal(ends(),baseEnd+2,'explicit runtime owner disposal balances startup');
  return {passed:true,constructorStartupCalls:0,explicitConfigureStarts:2,explicitStopAndDisposeCleanups:2};
 }finally{native.Dispose();}
}
