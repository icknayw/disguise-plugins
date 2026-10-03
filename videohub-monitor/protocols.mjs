import net from 'node:net';
export const lightwareQueries = [
 'GET /MEDIA/XP/VIDEO.*', 'GET /MEDIA/NAMES/VIDEO.*', 'GET /MEDIA/PORTS/VIDEO',
];
export function safeQuery(protocol, text) {
 if(protocol==='lightware' && lightwareQueries.includes(text)) return text+'\r\n';
 if(protocol==='videohub' && text==='PING:') return 'PING:\n\n';
 throw Error('Read-only: command is not permitted');
}
export function emptyState() {return {inputs:[],outputs:[],routes:{},locks:{},inputStatus:{},outputStatus:{},model:'',updatedAt:null};}
function ports(n,prefix,old=[]) {return Array.from({length:n},(_,i)=>({number:i+1,label:old[i]?.label||`${prefix} ${i+1}`}));}
export function parseVideohub(block,state) {
 const [header,...rows]=block.trim().split('\n');
 if(header==='VIDEOHUB DEVICE:') {
  const props=Object.fromEntries(rows.map(r=>{const n=r.indexOf(':');return [r.slice(0,n),r.slice(n+1).trim()]}));
  state.model=props['Model name']||'';
  state.present=props['Device present']==='true';
  for(const [key,label] of [['inputs','Input'],['outputs','Output']]) {const n=Number(props['Video '+key]);if(Number.isInteger(n)&&n>0&&n<=512)state[key]=ports(n,label,state[key]);}
 }
 const key={'INPUT LABELS:':'inputs','OUTPUT LABELS:':'outputs'}[header];
 for(const row of rows) {
  const m=row.match(/^(\d+) (.*)$/);if(!m)continue;
  const index=Number(m[1]);if(key&&state[key][index])state[key][index].label=m[2];
  if(header==='VIDEO OUTPUT ROUTING:'&&/^\d+$/.test(m[2]))state.routes[index+1]=Number(m[2])+1;
  if(header==='VIDEO OUTPUT LOCKS:')state.locks[index+1]=m[2];
 }
}
export function parseLightware(line,state) {
 let m=line.match(/^n- \/MEDIA\/PORTS\/VIDEO\/([IO])(\d+)$/);
 if(m) {const key=m[1]==='I'?'inputs':'outputs',n=Number(m[2]);if(n<=512&&n>state[key].length)state[key]=ports(n,key==='inputs'?'Input':'Output',state[key]);return;}
 m=line.match(/^p[rw] (\S+)=(.*)$/);if(!m)return;
 const [,path,value]=m;
 const name=path.match(/^\/MEDIA\/NAMES\/VIDEO\.([IO])(\d+)$/);
 if(name) {const key=name[1]==='I'?'inputs':'outputs',n=Number(name[2]);if(n>512)return;if(n>state[key].length)state[key]=ports(n,name[1]==='I'?'Input':'Output',state[key]);state[key][n-1].label=value.replace(/^\d+;/,'');return;}
 const values=value.split(';');if(values.at(-1)==='')values.pop();
 if(path==='/MEDIA/XP/VIDEO.DestinationConnectionStatus') {state.routes={};values.forEach((v,i)=>{state.routes[i+1]=/^I\d+$/.test(v)?Number(v.slice(1)):null});state.outputs=ports(values.length,'Output',state.outputs);}
 if(path==='/MEDIA/XP/VIDEO.SourcePortStatus') {state.inputs=ports(values.length,'Input',state.inputs);state.inputStatus=Object.fromEntries(values.map((v,i)=>[i+1,v]));}
 if(path==='/MEDIA/XP/VIDEO.DestinationPortStatus')state.outputStatus=Object.fromEntries(values.map((v,i)=>[i+1,v]));
}
export function connectMonitor({host,protocol,onState,onConnection,audit}) {
 const port=protocol==='lightware'?6107:9990;
 let stopped=false,socket,retry,poll,watchdog,buffer='',state=emptyState();
 function publish(){state.updatedAt=new Date().toISOString();onState(structuredClone(state));}
 function send(query){const bytes=safeQuery(protocol,query);audit({direction:'TX',host,port,text:bytes});socket.write(bytes);}
 function connect(){
  if(stopped)return;state=emptyState();buffer='';onConnection('connecting','');
  socket=net.createConnection({host,port});socket.setEncoding('utf8');socket.setTimeout(12000);
  socket.on('connect',()=>{
   const request=()=>{if(protocol==='lightware')lightwareQueries.forEach(send);else send('PING:');};
   if(protocol==='lightware')request();
   poll=setInterval(request,protocol==='lightware'?4000:10000);
   watchdog=setTimeout(()=>{if(!state.updatedAt)socket.destroy(Error('No matrix status received'));},8000);
  });
  socket.on('data',data=>{
   audit({direction:'RX',host,port,text:data});buffer+=data.replace(/\r/g,'');
   if(buffer.length>2000000){socket.destroy(Error('Response too large'));return;}
   const delimiter=protocol==='lightware'?'\n':'\n\n';let n;
   while((n=buffer.indexOf(delimiter))>=0){const message=buffer.slice(0,n);buffer=buffer.slice(n+delimiter.length);if(protocol==='lightware')parseLightware(message,state);else parseVideohub(message,state);}
   if(state.inputs.length&&state.outputs.length&&Object.keys(state.routes).length===state.outputs.length&&state.present!==false){publish();onConnection('online','');}
  });
  socket.on('timeout',()=>socket.destroy(Error('Device stopped responding')));
  socket.on('error',e=>onConnection('offline',e.message));
  socket.on('close',()=>{clearInterval(poll);clearTimeout(watchdog);if(!stopped){onConnection('offline','Connection lost. Retrying.');retry=setTimeout(connect,4000)}});
 }
 connect();return ()=>{stopped=true;clearTimeout(retry);clearTimeout(watchdog);clearInterval(poll);socket?.destroy();};
}
