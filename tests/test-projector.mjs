import http from 'node:http';import net from 'node:net';import crypto from 'node:crypto';import assert from 'node:assert/strict';import {execFile} from 'node:child_process';import {fileURLToPath} from 'node:url';
// Runs projector-monitor/Projector.ps1 against loopback fakes. Needs powershell.exe (Windows) or pwsh.
const script=fileURLToPath(new URL('../projector-monitor/Projector.ps1',import.meta.url));
const shell=await new Promise(r=>execFile(process.platform==='win32'?'powershell.exe':'pwsh',['-NoProfile','-Command','1'],e=>r(e?null:process.platform==='win32'?'powershell.exe':'pwsh')));
if(!shell){console.log('Projector tests skipped: PowerShell not found');process.exit(0);}
const md5=s=>crypto.createHash('md5').update(s).digest('hex');
function run(args){const flat=Object.entries(args).map(([k,v])=>`-${k} '${String(v).replace(/'/g,"''")}'`).join(' ');return new Promise((r,j)=>execFile(shell,['-NoProfile','-Command',`& '${script}' ${flat} | ConvertTo-Json -Compress`],{timeout:30000},(e,out,err)=>e?j(Error(err||e.message)):r(JSON.parse(out))));}
async function listen(server){await new Promise(r=>server.listen(0,'127.0.0.1',r));return server.address().port;}

// Epson: ESC/VP21 over HTTP with Digest auth. Replies are "KEY=VALUE\r:", "\r:" for an accepted set, or "ERR\r:".
let state={},seen=[];
const epson=http.createServer((req,res)=>{
 const url=new URL(req.url,'http://x'),auth=req.headers.authorization||'',f=Object.fromEntries([...auth.matchAll(/(\w+)="?([^",]*)"?/g)].map(m=>[m[1],m[2]]));
 const ha1=md5('EPSONWEB:EPSONWEB:secret'),ok=auth.startsWith('Digest ')&&f.response===md5(`${ha1}:${f.nonce}:${f.nc}:${f.cnonce}:${f.qop}:${md5(req.method+':'+f.uri)}`);
 if(!ok){res.writeHead(401,{'WWW-Authenticate':`Digest realm="EPSONWEB", nonce="${crypto.randomBytes(8).toString('hex')}", qop="auth", algorithm=MD5`});return res.end();}
 const cmd=url.searchParams.get('cmd');seen.push(cmd);const [key,arg]=cmd.split(/[ ?]/);
 if(cmd.endsWith('?'))return res.end(key in state?`${key}=${state[key]}\r:`:'ERR\r:');
 if(state.reject)return res.end('ERR\r:');state[key]=arg;res.end('\r:');
});
const ep=await listen(epson),base={Brand:'epson',Address:'127.0.0.1',Port:ep,Username:'EPSONWEB'};
state={PWR:'01',ERR:'00',LAMP:'1234',SHUTTER:'OFF',SOURCE:'56',FREEZE:'OFF',SIGNAL:'01',SNO:'X5ABC123'};
let r=await run({...base,Password:'secret'});
assert.equal(r.connection,'online');assert.deepEqual([r.power,r.shutter,r.input,r.freeze,r.signal,r.fault,r.lightHours,r.serial,r.error],['On','Open','SDI 1','Off','Detected','None',1234,'X5ABC123','']);console.log('Epson status (on) passed');
state={PWR:'04',ERR:'00',LAMP:'1234'};seen=[];r=await run({...base,Password:'secret'});
assert.equal(r.connection,'online');assert.equal(r.power,'Standby');assert.equal(r.input,null);assert.equal(r.shutter,null);assert.deepEqual(seen,['PWR?','ERR?','LAMP?']);console.log('Epson standby skips picture queries passed');
state={PWR:'05',ERR:'04'};r=await run({...base,Password:'secret'});
assert.equal(r.power,'Abnormal standby');assert.equal(r.fault,'High temperature');assert.match(r.error,/High temperature/);console.log('Epson fault passed');
r=await run({...base,Password:'wrong'});assert.equal(r.connection,'auth');assert.match(r.error,/Login rejected/);
r=await run({...base,Password:''});assert.equal(r.connection,'auth');assert.match(r.error,/Password required/);console.log('Epson authentication errors passed');
state={SHUTTER:'OFF'};seen=[];r=await run({...base,Password:'secret',Action:'shutter-close'});
assert.equal(r.ok,true);assert.deepEqual(seen,['SHUTTER ON']);assert.equal(state.SHUTTER,'ON');
seen=[];r=await run({...base,Password:'secret',Action:'power-on'});assert.equal(r.ok,true);assert.deepEqual(seen,['PWR ON']);
state={reject:true};r=await run({...base,Password:'secret',Action:'power-off'});assert.equal(r.ok,false);assert.match(r.error,/rejected/);console.log('Epson controls passed');
await new Promise(r=>epson.close(r));
r=await run({...base,Password:'secret'});assert.equal(r.connection,'offline');assert.match(r.error,new RegExp('port '+ep));console.log('Epson offline passed');

// Panasonic: NTCONTROL with MD5 challenge. One command per connection; the reply echoes control commands.
const replies={QPW:'001',QID:'PT-RQ25K',QSN:'SH1234',QSH:'1',QIN:'DM1,SD1',QFZ:'0','QTM:0':'+0031/+0087','QTM:1':'+0042/+0107','QVX:RTMS1':'RTMS1=812','QVX:LRTS3=00':'LRTS3=00:640','QVX:POWI1':'POWI1=+00003','QVX:SVRS0':'SVRS0=1.05',PON:'PON'};
const pana=net.createServer(s=>{s.write('NTCONTROL 1 0a1b2c3d\r');s.on('data',d=>{const line=d.toString().replace(/\r$/,''),hash=md5('dispadmin:secret:0a1b2c3d');if(!line.startsWith(hash+'00'))return s.end('ERRA\r');const c=line.slice(hash.length+2);s.end('00'+(replies[c]??'ER401')+'\r');});});
const pp=await listen(pana),pbase={Brand:'panasonic',Address:'127.0.0.1',Port:pp,Username:'dispadmin'};
r=await run({...pbase,Password:'secret'});
assert.deepEqual([r.connection,r.power,r.shutter,r.input,r.model,r.intakeC,r.projectorHours,r.lightHours,r.firmware],['online','On','Closed','Slot / SDI','PT-RQ25K',31,812,640,'1.05']);
r=await run({...pbase,Password:'secret',Action:'power-on'});assert.equal(r.ok,true);
r=await run({...pbase,Password:'wrong'});assert.equal(r.connection,'auth');console.log('Panasonic status, control and login passed');
await new Promise(r=>pana.close(r));
