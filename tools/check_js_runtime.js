/* 浏览器版运行时一致性校验
 *
 * player.js 是 Godot 工程的浏览器等价实现。本脚本在 Node 的 vm 沙箱里
 * 加载它（用桩替掉 DOM / Canvas / WebAudio），然后：
 *   1. 用同一份 story/*.avg 解析，核对节点数
 *   2. 跑随机通关，确认无死链、无死循环、能到达结局
 * 目的：保证浏览器版与 Godot 版的剧本解析和结局判定不会跑偏。
 *
 * 用法： node tools/check_js_runtime.js [次数]
 */
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const ROOT = path.dirname(__dirname);
const PREVIEW = path.join(ROOT, 'tools', 'preview');
const RUNS = parseInt(process.argv[2] || '300', 10);

const stub = () => new Proxy({}, {
  get: (t, k) => {
    if (k === 'getContext') return () => new Proxy({
      createRadialGradient: () => ({ addColorStop() {} }),
      createLinearGradient: () => ({ addColorStop() {} }),
    }, { get: () => () => {} });
    if (['clientWidth', 'clientHeight', 'width', 'height'].includes(k)) return 100;
    if (k === 'style') return {};
    if (k === 'children') return [];
    if (k === 'firstChild') return { textContent: '' };
    return () => {};
  }
});

const sandbox = {
  console, Math, JSON, Object, Array, Set, Map, String, Number,
  parseInt, parseFloat, isNaN, Date,
  setTimeout: () => {}, devicePixelRatio: 1,
  requestAnimationFrame: () => {}, performance: { now: () => 0 },
  addEventListener: () => {},
  localStorage: { getItem: () => null, setItem() {} },
  window: {}, fetch: () => {},
  document: {
    querySelector: () => stub(), getElementById: () => stub(),
    createElement: () => stub(), querySelectorAll: () => [],
  },
  AudioContext: function () {
    return {
      currentTime: 0, sampleRate: 44100, destination: {},
      createGain: () => ({ gain: { value: 0, setValueAtTime() {}, exponentialRampToValueAtTime() {} }, connect() {}, disconnect() {} }),
      createOscillator: () => ({ type: '', frequency: { value: 0, setValueAtTime() {}, exponentialRampToValueAtTime() {} }, connect() {}, start() {}, stop() {} }),
      createBuffer: () => ({ getChannelData: () => new Float32Array(16) }),
      createBufferSource: () => ({ connect() {}, start() {}, stop() {}, buffer: null, loop: false }),
    };
  },
};
sandbox.globalThis = sandbox;

let src = fs.readFileSync(path.join(PREVIEW, 'player.js'), 'utf8')
  .replace(/\nboot\(\);?\s*$/, '\n');
vm.createContext(sandbox);
vm.runInContext(src, sandbox);

const meta = JSON.parse(fs.readFileSync(path.join(PREVIEW, 'data', 'meta.json'), 'utf8'));
vm.runInContext('ITEMS=' + JSON.stringify(meta.items) + ';CLUES=' + JSON.stringify(meta.clues) + ';', sandbox);
for (const f of meta.story) {
  const txt = fs.readFileSync(path.join(PREVIEW, 'data', f), 'utf8');
  vm.runInContext('parseStory(' + JSON.stringify(txt) + ')', sandbox);
}

const nodeCount = vm.runInContext('Object.keys(NODES).length', sandbox);

const sim = `
(function(){
 let ok=0, fails=[], counts={};
 function applyEff(ins){ const {cmd,args}=ins;
  switch(cmd){
    case 'set': { const v=args[1]; if(v.startsWith('=')) setNum(args[0],+v.slice(1)); else addNum(args[0],+v); break; }
    case 'flag': S.flags[args[0]] = !(args[1]&&args[1].toLowerCase()==='false'); break;
    case 'state': S.states[args[0]]=args[1]; break;
    case 'item': if(args[0].startsWith('-')) S.items.delete(args[0].slice(1)); else S.items.add(args[0].replace(/^\\+/,'')); break;
    case 'clue': S.clues.add(args[0]); break;
    case 'death': S.deaths.push(args[0]); break;
    case 'settle': settle(+args[0]); break;
    case 'chapter': S.chapter=+args[0]; break;
    case 'goto': { let t=args[0]; if(t==='__ending__') t=determineEnding(); return {go:t}; }
    case 'ending': return {end: args[0]==='auto'?determineEnding():args[0]};
    case 'return': return {end:'__ret__'};
  } return null; }
 for(let run=0; run<${RUNS}; run++){
  S.nums=Object.assign({},NUM_DEFAULT); S.flags={}; S.states=Object.assign({},ENUM_DEFAULT);
  S.items=new Set(); S.clues=new Set(); S.visited=new Set(); S.deaths=[]; S.chapter=1;
  let nid='prologue', steps=0, ending=null;
  try{
   outer: while(true){
    if(!NODES[nid]) throw new Error('missing node '+nid);
    S.visited.add(nid); const prog=NODES[nid]; let i=0;
    while(i<prog.length){
      if(++steps>60000) throw new Error('possible loop near '+nid);
      const ins=prog[i++];
      if(ins.op==='say') continue;
      if(ins.op==='branch'){ if(!ev(ins.cond)) i=ins.jump; continue; }
      if(ins.op==='jump'){ i=ins.jump; continue; }
      if(ins.op==='choices'){
        const vis=ins.choices.filter(c=>!c.cond||ev(c.cond));
        const use=vis.filter(c=>!c.lock||ev(c.lock));
        if(!use.length){ if(!vis.length) continue; throw new Error('all locked at '+nid); }
        const c=use[(Math.random()*use.length)|0];
        for(const e of c.effects) applyEff(e);
        if(c.target){ nid=c.target; continue outer; }
        continue; }
      const r=applyEff(ins);
      if(r&&r.end){ ending=r.end; break outer; }
      if(r&&r.go){ nid=r.go; continue outer; } }
    throw new Error('dead end at '+nid); }
   counts[ending]=(counts[ending]||0)+1; ok++;
  }catch(e){ fails.push(e.message); } }
 return JSON.stringify({ok, nfail:fails.length, fails:fails.slice(0,4), counts});
})()`;

const res = JSON.parse(vm.runInContext(sim, sandbox));

console.log('='.repeat(62));
console.log('浏览器版运行时一致性校验');
console.log('='.repeat(62));
console.log('  剧本文件   :', meta.story.length);
console.log('  解析节点数 :', nodeCount);
console.log('  随机通关   :', res.ok + '/' + RUNS, '成功，失败', res.nfail);
if (res.fails.length) res.fails.forEach(f => console.log('    [ERROR]', f));
console.log('  结局分布   :');
for (const [k, v] of Object.entries(res.counts).sort((a, b) => b[1] - a[1])) {
  console.log('    ' + k.padEnd(30), v);
}
console.log('-'.repeat(62));
console.log(res.nfail === 0 ? '结果: 通过' : '结果: 存在问题');
process.exit(res.nfail === 0 ? 0 : 1);
