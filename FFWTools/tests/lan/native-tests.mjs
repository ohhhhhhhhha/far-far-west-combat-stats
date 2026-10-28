import assert from 'node:assert/strict';
export async function smoke(native){
 const handles=[native.Create(),native.Create(),native.Create()];const [h,a,b]=handles; const channel=4605527;
 assert.equal(native.Configure(h,'host','7','127.0.0.1',0,''),'','LAN host must open a real loopback listener');
 const host=native.Id(h);assert.match(host,/^lan:[0-9a-f]{32}:7$/);const room=host.split(':')[1];
 const guestA='lan:'+room+':43',guestB='lan:'+room+':9001';
 assert.equal(native.Configure(a,'guest','43','127.0.0.1',native.Port(h),native.Pair(h,guestA)),'');
 assert.equal(native.Configure(b,'guest','9001','127.0.0.1',native.Port(h),native.Pair(h,guestB)),'');
 const pump=async(n=30)=>{for(let i=0;i<n;i++){for(const p of handles)native.Update(p);await new Promise(r=>setTimeout(r,5));}};
 await pump();assert.match(native.Status(h),/connected:2/);assert.match(native.Status(a),/connected:1/);
 assert.equal(native.Send(a,host,channel,'{"amount":11}'),'');assert.equal(native.Send(b,host,channel,'{"amount":29}'),'');await pump();
 const received=[native.Poll(h,channel),native.Poll(h,channel)].sort();assert.deepEqual(received,[guestA+'\n{"amount":11}',guestB+'\n{"amount":29}'].sort());
 assert.equal(native.Send(h,guestA,channel,'{"total":40}'),'');assert.equal(native.Send(h,guestB,channel,'{"total":40}'),'');await pump();
 assert.equal(native.Poll(a,channel),host+'\n{"total":40}');assert.equal(native.Poll(b,channel),host+'\n{"total":40}');
 return {hostAndTwoGuests:true,received:2,broadcast:2};
}
