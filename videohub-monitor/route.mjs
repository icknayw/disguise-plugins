import net from 'node:net';
import {emptyState,parseVideohub} from './protocols.mjs';
export function route({host,input,output,previous,routes=[{input,output,previous}],port=9990,audit=()=>{},timeout=5000}){
 if(!net.isIPv4(host)||!Array.isArray(routes)||!routes.length||routes.length>512||routes.some(r=>!r||![r.input,r.output,r.previous].every(n=>Number.isInteger(n)&&n>=1&&n<=512))||new Set(routes.map(r=>r.output)).size!==routes.length)return Promise.reject(Error('Invalid route'));
 return new Promise((resolve,reject)=>{
  const s=net.createConnection({host,port});s.setEncoding('utf8');const state=emptyState();let buffer='',sent=false,ack=false,observed=new Set(),done=false;
  const finish=(error)=>{if(done)return;done=true;clearTimeout(timer);s.destroy();error?reject(error):resolve({confirmed:true,routes});};
  const timer=setTimeout(()=>finish(Error(sent?'No confirmed routing update. Check the matrix before retrying.':'Matrix status timed out')),timeout);
  s.on('error',e=>finish(e));s.on('close',()=>{if(!done)finish(Error(sent?'Connection lost after command. Check the matrix before retrying.':'Matrix disconnected'));});
  s.on('data',data=>{
   buffer+=data.replace(/\r/g,'');if(buffer.length>2e6)return finish(Error('Invalid matrix response'));
   let n;while((n=buffer.indexOf('\n\n'))>=0){const block=buffer.slice(0,n);buffer=buffer.slice(n+2);parseVideohub(block,state);
    if(sent){if(block.trim()==='NAK')return finish(Error('Matrix rejected batch. Check all selected outputs before retrying.'));if(block.trim()==='ACK')ack=true;if(block.startsWith('VIDEO OUTPUT ROUTING:')){for(const row of block.split('\n').slice(1)){const [o,i]=row.split(' ').map(Number);const wanted=routes.find(r=>r.output===o+1);if(wanted){if(wanted.input===i+1)observed.add(wanted.output);else observed.delete(wanted.output);}}}if(ack&&routes.every(r=>observed.has(r.output)))return finish();}
   }
   if(sent||done)return;
   const complete=state.present===true&&state.inputs.length&&state.outputs.length&&Object.keys(state.routes).length===state.outputs.length&&Object.keys(state.locks).length===state.outputs.length;
   if(!complete)return;
   for(const r of routes){
    if(r.input>state.inputs.length||r.output>state.outputs.length)return finish(Error('Port no longer exists'));
    if(state.locks[r.output]!=='U')return finish(Error('Output '+r.output+' is locked'));
    if(state.routes[r.output]!==r.previous)return finish(Error('Output '+r.output+' changed. Select its crosspoint again.'));
    if(r.previous===r.input)observed.add(r.output);
   }
   const changes=routes.filter(r=>r.previous!==r.input);
   if(!changes.length)return finish();
   const command='VIDEO OUTPUT ROUTING:\n'+changes.map(r=>`${r.output-1} ${r.input-1}`).join('\n')+'\n\n';
   try{audit({event:'route-send',host,routes,command});sent=true;s.write(command);}catch(e){finish(e);}
  });
 });
}
