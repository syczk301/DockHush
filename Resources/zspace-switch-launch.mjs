import { execFileSync } from 'node:child_process';
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { homedir } from 'node:os';
import { createServer } from 'node:net';

if (!globalThis.WebSocket || !globalThis.fetch) throw new Error('Node.js 22 or newer is required.');
const app = '/Applications/极空间.app';
const executable = app + '/Contents/MacOS/极空间';
const statePath = join(homedir(), 'Library/Application Support/DockHush/zspace-session.json');
const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
function runningPid() {
  try {
    const lines = execFileSync('/bin/ps', ['-ww','-axo','pid=,comm='], {encoding:'utf8',env:{...process.env,LC_ALL:'en_US.UTF-8'}}).split('\n');
    const line = lines.find(line => line.trim().replace(/^\d+\s+/, '') === executable);
    return line ? Number(line.trim().match(/^\d+/)[0]) : null;
  } catch { return null; }
}
const existing = runningPid();
const hide = process.argv.includes("--hide");
if (hide && !existing) { console.log("NOT_RUNNING"); process.exit(0); }
if (existing) {
  let state;
  try { state = JSON.parse(readFileSync(statePath,'utf8')); } catch {}
  if (state?.pid !== existing) throw new Error('极空间当前实例尚未安装后台模式；请先正常退出极空间，再从助手中打开。');
  execFileSync(executable, [hide ? '--background-hide-helper-hide' : '--background-hide-helper-show'], {stdio:'ignore', timeout:15000});
  console.log('REOPENED hooked instance', existing);
  process.exit(0);
}
// Reserve a random loopback port; never expose the inspector on network interfaces.
const server = createServer();
await new Promise(resolve => server.listen(0,'127.0.0.1',resolve));
const port = server.address().port;
await new Promise(resolve => server.close(resolve));
execFileSync('/usr/bin/open', ['-g','-a',app,'--args',`--inspect=127.0.0.1:${port}`]);
let socket;
let inspectorClosed=false;
try {
  let endpoint;
  for (let i=0;i<60;i++) {
    try {
      const response = await fetch(`http://127.0.0.1:${port}/json/list`, {signal:AbortSignal.timeout(500)});
      const targets = await response.json();
      endpoint = targets.find(target => target.webSocketDebuggerUrl)?.webSocketDebuggerUrl;
      if (endpoint) break;
    } catch {}
    await sleep(200);
  }
  if (!endpoint) throw new Error('极空间未开放本机调试入口，未安装后台模式。');
  const url = new URL(endpoint);
  if (url.hostname !== '127.0.0.1' || Number(url.port) !== port) throw new Error('Unexpected inspector endpoint');
  socket = new WebSocket(endpoint);
  await new Promise((resolve,reject) => { socket.addEventListener('open',resolve,{once:true}); socket.addEventListener('error',reject,{once:true}); });
  let nextID=0;
  const pending = new Map();
  socket.addEventListener('message', event => {
    const message=JSON.parse(event.data);
    const item=pending.get(message.id);
    if (!item) return;
    pending.delete(message.id); clearTimeout(item.timer);
    message.error ? item.reject(new Error(JSON.stringify(message.error))) : item.resolve(message.result);
  });
  function command(method,params) {
    return new Promise((resolve,reject) => {
      const id=++nextID;
      const timer=setTimeout(() => { pending.delete(id);reject(new Error('Inspector command timed out')); },5000);
      pending.set(id,{resolve,reject,timer});
      socket.send(JSON.stringify({id,method,params}));
    });
  }
  async function evaluate(expression) {
    const result=await command('Runtime.evaluate',{expression,returnByValue:true});
    if (result.exceptionDetails) throw new Error('Runtime evaluation failed: '+JSON.stringify(result.exceptionDetails));
    return result.result.value;
  }
  const identity=await evaluate('({pid:process.pid,executable:process.execPath})');
  if (identity.executable !== executable || identity.pid !== runningPid()) throw new Error('Target process mismatch: '+JSON.stringify({identity,observedPid:runningPid()}));
  const hook=readFileSync(join(dirname(fileURLToPath(import.meta.url)),'zspace-switch-hook.js'),'utf8');
  const result=await evaluate(hook);
  if (!result?.installed || result.pid !== identity.pid) throw new Error('Hook verification failed');
  // Close the main-process inspector as soon as the hook is installed.
  await evaluate("setTimeout(() => { const r = typeof require === 'function' ? require : process.mainModule.require.bind(process.mainModule); r('inspector').close(); }, 100); 'closing'");
  socket.close();
  let stillOpen=true;
  for (let i=0; i<40; i++) {
    await sleep(200);
    try { await fetch(`http://127.0.0.1:${port}/json/list`,{signal:AbortSignal.timeout(500)}); }
    catch { stillOpen=false; break; }
  }
  if (stillOpen) throw new Error('Inspector did not close; do not treat this run as complete.');
  inspectorClosed=true;
  mkdirSync(dirname(statePath),{recursive:true});
  writeFileSync(statePath,JSON.stringify({pid:identity.pid,installed:true,rulesVersion:2}),{mode:0o600});
  console.log('INSTALLED', JSON.stringify({...result,inspectorClosed:true}));
} finally {
  socket?.close();
  // On failure do not leave a debugger-enabled app running unattended.
  if (!inspectorClosed) {
    const pid=runningPid();
    if (pid) { try { process.kill(pid,'SIGTERM'); } catch {} }
  }
}
