import http from 'node:http';import fs from 'node:fs';import path from 'node:path';import net from 'node:net';
import {connectMonitor,emptyState} from './protocols.mjs';import {route} from './route.mjs';
const folder=import.meta.dirname,config=JSON.parse(fs.readFileSync(path.join(folder,'plugin-config.json'))),settingsPath=path.join(folder,'settings.json');
let settings=fs.existsSync(settingsPath)?JSON.parse(fs.readFileSync(settingsPath)): {host:'',size:'compact',inputs:null,outputs:null};
settings={size:'compact',orientation:'inputs-left',inputs:null,outputs:null,...settings};
if(settings.host&&!net.isIPv4(settings.host))throw Error('Invalid saved IP');
let state=emptyState(),connection='offline',error='',stop,busy=false;const requests=new Map();
function audit(event){const file=path.join(folder,'routing-audit.ndjson');if(fs.existsSync(file)&&fs.statSync(file).size>5e6)fs.renameSync(file,file+'.previous');fs.appendFileSync(file,JSON.stringify({at:new Date().toISOString(),...event})+'\n');}
function connect(){stop?.();state=emptyState();connection=settings.host?'connecting':'offline';error='';if(settings.host)stop=connectMonitor({host:settings.host,protocol:'videohub',onState:s=>state=s,onConnection:(c,e)=>{connection=c;error=e},audit:()=>{}});}
function payload(){return {app:config.id,version:2,title:'Videohub Monitor',...state,connection,error,settings,busy};}
const files={'/':'index.html','/settings':'index.html','/app.js':'app.js','/style.css':'style.css'};
function visible(list,ports){return list===null?ports.map(p=>p.number):list;}
const allowedHosts=new Set(['localhost','127.0.0.1',...(config.allowedHosts||[])]);
const server=http.createServer(async(req,res)=>{
 const json=(status,data)=>{res.writeHead(status,{'Content-Type':'application/json','Cache-Control':'no-store'});res.end(JSON.stringify(data));};
 try{const pathname=new URL(req.url,'http://localhost').pathname;
 if(req.method==='GET'&&pathname==='/api/state')return json(200,payload());
 if(req.method==='POST'){
  if(req.headers['x-videohub-monitor']!=='1'||(req.headers.origin&&!(()=>{try{const u=new URL(req.headers.origin);return u.protocol==='http:'&&Number(u.port)===config.port&&allowedHosts.has(u.hostname.toLowerCase());}catch{return false;}})()))return json(403,{error:'Origin rejected'});
  if(!req.headers['content-type']?.startsWith('application/json'))return json(415,{error:'JSON required'});
  let raw='';for await(const b of req){raw+=b;if(raw.length>30000)return json(413,{error:'Request too large'});}const body=JSON.parse(raw);
  if(pathname==='/api/fit'){
   const {width,height,contentWidth,contentHeight}=body;
   if(![width,height,contentWidth,contentHeight].every(n=>Number.isFinite(n)&&n>=100&&n<=10000))return json(400,{error:'Invalid dimensions'});
   let script=fs.readFileSync(path.join(folder,'fit-window.py'),'utf8');for(const [key,value]of Object.entries({VW:width,VH:height,CW:contentWidth,CH:contentHeight}))script=script.replaceAll('{{'+key+'}}',String(Math.round(value)));
   try{const r=await fetch('http://'+(req.socket.remoteAddress?.replace(/^::ffff:/,'')||'127.0.0.1')+'/api/session/python/execute',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({script}),signal:AbortSignal.timeout(2500)});const result=await r.json();return json(200,{ok:result.status?.code===0});}catch{return json(200,{ok:false});}
  }
  if(pathname==='/api/settings'){
   if(busy)return json(409,{error:'Wait for the current route to finish'});
   if(typeof body.host!=='string'||(body.host&&!net.isIPv4(body.host))||!['compact','standard','large'].includes(body.size))return json(400,{error:'Enter a valid IPv4 address and size'});
   for(const key of ['inputs','outputs'])if(body[key]!==null&&(!Array.isArray(body[key])||body[key].length>512||body[key].some(n=>!Number.isInteger(n)||n<1||n>512)||new Set(body[key]).size!==body[key].length))return json(400,{error:'Invalid port selection'});
   if(body.orientation!==undefined&&!['inputs-left','inputs-top'].includes(body.orientation))return json(400,{error:'Invalid orientation'});
   const changed=body.host!==settings.host,next={host:body.host,size:body.size,orientation:body.orientation||settings.orientation,inputs:changed?null:body.inputs,outputs:changed?null:body.outputs};
   if(fs.existsSync(settingsPath))fs.copyFileSync(settingsPath,settingsPath+'.bak');fs.writeFileSync(settingsPath+'.tmp',JSON.stringify(next,null,2));fs.renameSync(settingsPath+'.tmp',settingsPath);settings=next;if(changed)connect();return json(200,payload());
  }
  if(pathname==='/api/route'){
   if(typeof body.id!=='string'||!/^[a-zA-Z0-9-]{8,80}$/.test(body.id))return json(400,{error:'Invalid request ID'});
   const routes=body.routes??[{input:body.input,output:body.output,previous:body.previous}];
   if(!Array.isArray(routes)||!routes.length||routes.length>512||routes.some(r=>!r||![r.input,r.output,r.previous].every(Number.isInteger))||new Set(routes.map(r=>r.output)).size!==routes.length)return json(400,{error:'Invalid route batch'});
   const signature=JSON.stringify([body.host,routes]);
   if(requests.has(body.id)){const old=requests.get(body.id);return old.signature===signature?json(old.code,old.result):json(409,{error:'Request ID already used'});}
   if(busy)return json(409,{error:'Another route is pending'});
   if(connection!=='online'||!state.updatedAt||Date.now()-Date.parse(state.updatedAt)>15000)return json(409,{error:'Fresh matrix status required'});
   if(body.host!==settings.host)return json(409,{error:'Matrix IP changed. Select the route again.'});
   for(const r of routes){
    if(!state.inputs.some(p=>p.number===r.input)||!state.outputs.some(p=>p.number===r.output)||!visible(settings.inputs,state.inputs).includes(r.input)||!visible(settings.outputs,state.outputs).includes(r.output))return json(400,{error:'Select visible inputs and outputs'});
    if(state.routes[r.output]!==r.previous||state.locks[r.output]!=='U')return json(409,{error:'Output '+r.output+' changed or is locked. Select again.'});
   }
   busy=true;const record={signature,code:202,result:{pending:true}};requests.set(body.id,record);if(requests.size>1000)requests.delete(requests.keys().next().value);
   try{const result=await route({host:body.host,routes,audit});record.code=200;record.result=result;audit({event:'route-confirmed',id:body.id,...result});}catch(e){record.code=502;record.result={error:e.message};audit({event:'route-failed',id:body.id,error:e.message});}finally{busy=false;}
   return json(record.code,record.result);
  }
  return json(404,{error:'Not found'});
 }
 if(req.method!=='GET'||!files[pathname])return json(404,{error:'Not found'});
 const file=files[pathname];res.writeHead(200,{'Content-Type':file.endsWith('.js')?'text/javascript':file.endsWith('.css')?'text/css':'text/html','Cache-Control':'no-store','Content-Security-Policy':"default-src 'self'; style-src 'self'; script-src 'self'; connect-src 'self'; base-uri 'none'; form-action 'self'"});res.end(fs.readFileSync(path.join(folder,file)));
 }catch(e){json(400,{error:e.message});}
});
server.requestTimeout=10000;server.headersTimeout=10000;server.listen(config.port,config.bind||'127.0.0.1',connect);server.on('error',e=>{console.error(e);process.exit(1)});process.on('SIGTERM',()=>{stop?.();server.close(()=>process.exit())});
