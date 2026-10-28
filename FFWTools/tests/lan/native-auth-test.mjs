import net from 'node:net';
import assert from 'node:assert/strict';
export async function unauthenticatedFailureCannotEraseInbox(native){
 const h=native.Create(),g=native.Create();let attacker;
 const frame=s=>{const b=Buffer.from(s);const prefix=Buffer.alloc(4);prefix.writeUInt32BE(b.length);return Buffer.concat([prefix,b]);};
 const pump=async(n=20)=>{for(let i=0;i<n;i++){native.Update(g);native.Update(h);await new Promise(r=>setTimeout(r,5));}};
 try{
  assert.equal(native.Configure(h,'host','7','127.0.0.1',0,''),'');const host=native.Id(h);const peer=host.replace(/:7$/,':43');
  assert.equal(native.Configure(g,'guest','43','127.0.0.1',native.Port(h),native.Pair(h,peer)),'');await pump();
  assert.equal(native.Send(g,host,4605527,'{"settled":73}'),'');await pump();
  attacker=net.connect(native.Port(h),'127.0.0.1');attacker.on('error',()=>{});attacker.on('data',()=>{});await new Promise(r=>attacker.once('connect',r));
  attacker.write(frame('C|'+peer+'|'+('b'.repeat(32))));await pump();attacker.write(frame('A|'+('0'.repeat(64))));await pump();
  assert.equal(native.Poll(h,4605527),peer+'\n{"settled":73}','an unauthenticated socket must not erase a legitimate peer queued event');
  assert.match(native.Status(h),/connected:1/);return {passed:true,legitimateQueuedMessageRetained:true,authenticatedConnectionRetained:true};
 }finally{attacker?.destroy();native.Stop(h);native.Stop(g);}
}
