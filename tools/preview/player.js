/* 《晚自习之后》Web 试玩预览
 * 这是 Godot 工程 (game/) 的浏览器等价实现，用于在无法运行 Godot 的环境下试玩同一套剧本。
 * 剧本、变量、结局判定与 game/story/*.avg + autoload/*.gd 完全一致。 */

// ---------------------------------------------------------------- 配置（对应 config.gd）
const NUM_RANGE = {
  truth:[0,1500],evidence_count:[0,8], sanity:[0,100], memory_echo:[0,460], shenhe_focus:[0,190],
  trust_zhouxu:[-12,14], trust_liangye:[-12,18], trust_xuqing:[-10,6], trust_oldqin:[-6,12],
  route_obedience:[0,24], route_investigate:[0,24], route_empathy:[0,14], route_hostility:[0,14],
  taboo_count:[0,25], save_route_score:[0,150], end_cycle_score:[0,20], control_route_score:[0,20],
};
const NUM_DEFAULT = { truth:0, sanity:70, memory_echo:0, shenhe_focus:0, trust_zhouxu:0,
  trust_liangye:0, trust_xuqing:0, trust_oldqin:0, route_obedience:0, route_investigate:0,
  route_empathy:0, route_hostility:0, taboo_count:0, save_route_score:0, end_cycle_score:0, control_route_score:0 };
const NUM_LABEL = { truth:"真相", sanity:"理智", memory_echo:"回响", shenhe_focus:"关注",
  trust_zhouxu:"周叙信任", trust_liangye:"梁野信任", trust_xuqing:"许清态度", trust_oldqin:"老秦信任",
  route_obedience:"守规", route_investigate:"调查", route_empathy:"共情", route_hostility:"对抗",
  taboo_count:"违规", save_route_score:"救人线", end_cycle_score:"终止线", control_route_score:"接管线" };
const ENUM_DEFAULT = { liangye_state:"normal", oldqin_state:"alive", zhouxu_state:"normal",
  xuqing_state:"hidden", shenhe_state:"echo", liangye_final_state_ch3:"fragile_alive",
  zhouxu_final_state_ch3:"split_guard", truth_state:"partial",
  liangye_end_state:"present_unstable", zhouxu_end_state:"follow_to_threshold" };
const CHARS = {
  linzhou:{n:"林昼",c:"#dbdde6"}, zhouxu:{n:"周叙",c:"#9ebddb"}, liangye:{n:"梁野",c:"#e0c28c"},
  xuqing:{n:"许清",c:"#c79ea9"}, shenhe:{n:"沈禾",c:"#b8dcd4"}, oldqin:{n:"老秦",c:"#b3a98c"},
  voice:{n:"女声",c:"#a8d6d2"}, radio:{n:"广播",c:"#cc8c7a"}, classmate:{n:"同学",c:"#b3b3b6"},
  crowd:{n:"众人",c:"#a8a8ab"}, unknown:{n:"？？？",c:"#9a9aa6"}, me:{n:"我",c:"#eae8e2"},
};
const ENDING_INFO = {
  ending_true_release:{t:"《点名停止》",tag:"TRUE END",c:"#b8d6d0"},
  ending_bittersweet_exchange:{t:"《留堂》",tag:"BITTERSWEET END",c:"#c7b894"},
  ending_manager:{t:"《管理员》",tag:"COLD END",c:"#9fa8bd"},
  ending_destroyer:{t:"《焚校》",tag:"DESTRUCTION END",c:"#dc7040"},
  ending_empty_seat:{t:"《到》",tag:"BAD END",c:"#b3423c"},
};

// ---------------------------------------------------------------- 状态
const S = {
  nums:{...NUM_DEFAULT}, flags:{}, states:{...ENUM_DEFAULT}, items:new Set(), clues:new Set(),
  visited:new Set(), deaths:[], history:[], chapter:1, ending:null,
};
let ITEMS={}, CLUES={}, NODES={};
let settings = { gore:2, speed:24, shake:true, flash:true };

function n(k){ return S.nums[k]|0; }
function addNum(k,d){ const r=NUM_RANGE[k]||[-999,999]; S.nums[k]=Math.max(r[0],Math.min(r[1],(S.nums[k]|0)+d)); }
function setNum(k,v){ const r=NUM_RANGE[k]||[-999,999]; S.nums[k]=Math.max(r[0],Math.min(r[1],v)); }

// ---------------------------------------------------------------- 剧本解析（对应 story_engine.gd）
function parseStory(txt){
  const lines = txt.replace(/\r\n/g,"\n").split("\n");
  let cur=null, prog=[], ifs=[], lastChoices=null;
  const flush=()=>{ if(cur) NODES[cur]=prog; };
  for(const raw of lines){
    const s = raw.trim();
    if(!s){ lastChoices=null; continue; }
    if(s.startsWith("--")) continue;
    if(s.startsWith("==")){ flush(); cur=s.slice(2).trim(); prog=[]; ifs=[]; lastChoices=null; continue; }
    if(cur===null) continue;
    if(lastChoices && /^\s/.test(raw) && s.startsWith("@")){ lastChoices[lastChoices.length-1].effects.push(parseCmd(s)); continue; }
    if(s.startsWith("*")){
      const ch = parseChoice(s.slice(1).trim());
      if(prog.length && prog[prog.length-1].op==="choices"){ prog[prog.length-1].choices.push(ch); lastChoices=prog[prog.length-1].choices; }
      else { prog.push({op:"choices",choices:[ch]}); lastChoices=prog[prog.length-1].choices; }
      continue;
    }
    lastChoices=null;
    if(s.startsWith("@")){
      const head = s.slice(1).split(/\s+/)[0].toLowerCase();
      if(head==="if"){ prog.push({op:"branch",cond:s.slice(3).trim(),jump:-1}); ifs.push({ci:prog.length-1,ex:[]}); }
      else if(head==="elif"){ const f=ifs[ifs.length-1]; prog.push({op:"jump",jump:-1}); f.ex.push(prog.length-1);
        prog[f.ci].jump=prog.length; prog.push({op:"branch",cond:s.slice(5).trim(),jump:-1}); f.ci=prog.length-1; }
      else if(head==="else"){ const f=ifs[ifs.length-1]; prog.push({op:"jump",jump:-1}); f.ex.push(prog.length-1);
        prog[f.ci].jump=prog.length; f.ci=-1; }
      else if(head==="endif"){ const f=ifs.pop(); if(f.ci>=0) prog[f.ci].jump=prog.length; f.ex.forEach(i=>prog[i].jump=prog.length); }
      else prog.push(parseCmd(s));
      continue;
    }
    if(s.startsWith(">")){ prog.push({op:"say",who:"",text:s.slice(1).trim(),style:"note"}); continue; }
    prog.push(parseSay(s));
  }
  flush();
}
function parseCmd(s){ const p=s.slice(1).split(/\s+/); return {op:"cmd",cmd:p[0].toLowerCase(),args:p.slice(1),rest:s.slice(1+p[0].length).trim()}; }
function parseChoice(s){
  let cond="",lock="",body=s;
  while(body.startsWith("[")){ const i=body.indexOf("]"); if(i<0)break;
    const tag=body.slice(1,i).trim(); body=body.slice(i+1).trim();
    if(tag.startsWith("if ")) cond=tag.slice(3).trim(); else if(tag.startsWith("lock ")) lock=tag.slice(5).trim(); }
  let target=""; const a=body.lastIndexOf("->");
  if(a>=0){ target=body.slice(a+2).trim(); body=body.slice(0,a).trim(); }
  return {text:body,target,cond,lock,effects:[]};
}
function parseSay(s){
  let i=s.indexOf("："); const j=s.indexOf(":");
  if(i<0 || (j>=0&&j<i)) i=j;
  if(i>0 && i<=24){
    let head=s.slice(0,i).trim(); const text=s.slice(i+1).trim(); let emo="";
    let p=head.indexOf("("); if(p<0)p=head.indexOf("（");
    if(p>0){ emo=head.slice(p+1,head.length-1).trim(); head=head.slice(0,p).trim(); }
    if(CHARS[head]) return {op:"say",who:head,emo,text,style:"line"};
  }
  return {op:"say",who:"",text:s,style:"narration"};
}

// ---------------------------------------------------------------- 条件求值
function ev(e){ e=(e||"").trim(); if(!e) return true;
  if(e.includes(" or ")) return e.split(" or ").some(ev);
  if(e.includes(" and ")) return e.split(" and ").every(ev);
  return atom(e); }
function atom(a){ let s=a.trim();
  if(s.startsWith("!")) return !atom(s.slice(1));
  if(s.startsWith("item:")) return S.items.has(s.slice(5));
  if(s.startsWith("clue:")) return S.clues.has(s.slice(5));
  if(s.startsWith("visited:")) return S.visited.has(s.slice(8));
  if(s.startsWith("death:")) return S.deaths.some(d=>d.startsWith(s.slice(6)));
  if(s.startsWith("state:")){ const b=s.slice(6);
    if(b.includes("==")){ const [k,v]=b.split("=="); const cur=S.states[k.trim()]||"";
      return v.includes("|") ? v.trim().split("|").includes(cur) : cur===v.trim(); }
    if(b.includes("!=")){ const [k,v]=b.split("!="); return (S.states[k.trim()]||"")!==v.trim(); }
    return false; }
  if(s.startsWith("cycles")) return cmpn(0,s.slice(6));
  if(s.startsWith("chapter")) return cmpn(S.chapter,s.slice(7));
  if(s.startsWith("gore")) return cmpn(settings.gore,s.slice(4));
  for(const op of ["<=",">=","==","!=","<",">"]){ const i=s.indexOf(op);
    if(i>0){ const k=s.slice(0,i).trim(); if(NUM_RANGE[k]) return cmpn(n(k),s.slice(i)); return false; } }
  if(NUM_RANGE[s]) return n(s)>0;
  return !!S.flags[s]; }
function cmpn(v,tail){ const t=tail.trim();
  if(t.startsWith(">=")) return v>=+t.slice(2); if(t.startsWith("<=")) return v<=+t.slice(2);
  if(t.startsWith("==")) return v===+t.slice(2); if(t.startsWith("!=")) return v!==+t.slice(2);
  if(t.startsWith(">")) return v>+t.slice(1); if(t.startsWith("<")) return v<+t.slice(1); return v!==0; }

// ---------------------------------------------------------------- 章节结算 / 结局判定（对应 game_state.gd）
function settle(ch){
  const F=S.flags, st=S.states;
  if(ch===1){
    if(F.flag_liangye_library && F.flag_library_page109) st.liangye_state="fear_alive";
    else if(n("trust_liangye")<0 && !F.flag_liangye_library) st.liangye_state="missing_marked";
    else if(n("trust_liangye")>=2) st.liangye_state="ally_shaken"; else st.liangye_state="normal";
    st.zhouxu_state = n("trust_zhouxu")>=2?"guarding":(n("trust_zhouxu")<=-2?"hiding":"normal");
    st.shenhe_state = n("shenhe_focus")>=5?"calling":"echo";
    if(n("trust_xuqing")<=-2) st.xuqing_state="suspected";
    S.chapter=2;
  } else if(ch===2){
    if(F.flag_liangye_marked && n("trust_liangye")<0){ st.liangye_state="missing_marked"; S.items.add("item_library_card"); addNum("truth",2); if(!S.deaths.includes("梁野"))S.deaths.push("梁野"); }
    else if(F.flag_liangye_half) st.liangye_state="half_assimilated";
    else if(n("trust_liangye")>=2) st.liangye_state="ally_shaken"; else st.liangye_state="fear_alive";
    st.zhouxu_state = n("trust_zhouxu")>=2?"guarding":(n("trust_zhouxu")<=-2?"coercing":"hiding");
    if(F.flag_oldqin_burndeath) st.oldqin_state="burned";
    if(n("shenhe_focus")>=8||F.flag_first_face_to_face_shenhe) st.shenhe_state="half_present";
    else if(n("shenhe_focus")>=4) st.shenhe_state="calling";
    if(n("trust_xuqing")<=-3||F.flag_found_xuqing_log_fragment) st.xuqing_state="suspected";
    S.chapter=3;
  } else if(ch===3){
    if(F.flag_gave_up_roommate) st.liangye_final_state_ch3="abandoned";
    else if(F.flag_liangye_half_assimilated) st.liangye_final_state_ch3 = n("trust_liangye")>=1?"rescued_half":"missing";
    else if(F.flag_liangye_returned && n("trust_liangye")>=3) st.liangye_final_state_ch3="anchor_alive";
    else if(F.flag_liangye_returned) st.liangye_final_state_ch3="fragile_alive";
    else if(st.liangye_state==="missing_marked") st.liangye_final_state_ch3="missing";
    else st.liangye_final_state_ch3="fragile_alive";
    if(n("trust_zhouxu")>=3 && F.flag_zhouxu_confessed_part) st.zhouxu_final_state_ch3="confessor_protector";
    else if(n("trust_zhouxu")<=-2) st.zhouxu_final_state_ch3="coercer";
    else st.zhouxu_final_state_ch3="split_guard";
    if(F.flag_name_written_back) F.true_end_precondition_1=true;
    if(F.flag_night_roster_taken||S.items.has("item_night_roster")) F.true_end_precondition_2=true;
    S.chapter=4;
  } else if(ch===4){
    const t=n("truth");
    const core = F.flag_saw_fire_video && F.flag_saw_self_repeat && F.flag_rule_terms_complete;
    st.truth_state = (t>=(S.flags["flag_testimony_given"]?700:1180)&&core&&F.flag_true_linday_status_known) ? "complete"
      : ((t>=863&&(F.flag_saw_fire_video||F.flag_roster_core_taken)) ? "high" : "partial");
    const m={anchor_alive:"present_anchor",rescued_half:"present_fragile_truth",fragile_alive:"present_unstable"};
    st.liangye_end_state = F.flag_liangye_final_loss ? "absent_echo" : (m[st.liangye_final_state_ch3]||"absent_echo");
    st.zhouxu_end_state = st.zhouxu_final_state_ch3==="confessor_protector"
      ? (n("trust_zhouxu")>=3?"enter_with_player":"follow_to_threshold")
      : (st.zhouxu_final_state_ch3==="coercer"?"pressure_player":"follow_to_threshold");
    const ready = (S.items.has("item_roster_core")||S.items.has("item_night_roster"))
      && (S.items.has("item_admin_key")||F.flag_fakewall_opened) && n("truth")>=564;
    if(ready) F.flag_terminal_broadcast_ready=true;
    S.chapter=5;
  }
}
function determineEnding(){
 if(S.saveTampered) return "ending_empty_seat";
 if(S.flags["flag_count_overflow"]){S.states.truth_state="complete";S.flags["flag_terminal_broadcast_ready"]=1;S.flags["true_end_precondition_1"]=1;S.flags["true_end_precondition_2"]=1;S.flags["flag_rule_terms_complete"]=1;}
  const F=S.flags, st=S.states;
  if(st.truth_state==="complete" && F.true_end_precondition_1 && F.true_end_precondition_2
     && n("save_route_score")>=58 && F.flag_rule_terms_complete && F.flag_terminal_broadcast_ready
     && !F.flag_gave_up_roommate && ["present_anchor","present_fragile_truth"].includes(st.liangye_end_state))
    return "ending_true_release";
  if(n("save_route_score")>=36 && F.flag_terminal_broadcast_ready
     && (st.liangye_end_state==="absent_echo" || !F.flag_rule_terms_complete || F.flag_player_self_substitute))
    return "ending_bittersweet_exchange";
  if(n("end_cycle_score")>=9 && F.flag_terminal_broadcast_ready && F.flag_chose_end_cycle)
    return "ending_destroyer";
  if(n("control_route_score")>=9 || (F.flag_gave_up_roommate && n("control_route_score")>=7))
    return "ending_manager";
  return "ending_empty_seat";
}

// ---------------------------------------------------------------- DOM
const $ = s => document.querySelector(s);
const elWho=$("#who"), elText=$("#text"), elChoices=$("#choices"), elNext=$("#next"),
      elStats=$("#stats"), elBox=$("#box"), elClick=$("#clickarea");

// ---------------------------------------------------------------- 背景绘制
const bgc=$("#bg"), bx=bgc.getContext("2d");
const fxc=$("#fxlayer"), fx=fxc.getContext("2d");
let sceneId="black", variant="", T=0, flicker=0, bloodAmt=0;
function resize(){ for(const c of [bgc,fxc]){ c.width=c.clientWidth*devicePixelRatio; c.height=c.clientHeight*devicePixelRatio; } }
addEventListener("resize",resize);

const PAL = v => {
  const base={sky:"#292b33",wall:"#333330",wall2:"#242424",floor:"#1c1c1f",light:"#f2e6b8"};
  const m={ day:{sky:"#9ea8ad",wall:"#706e66",wall2:"#54534f",floor:"#454340"},
    dusk:{sky:"#6b4d42",wall:"#52453d",wall2:"#38312e",floor:"#2e2926"},
    night:{sky:"#12141f",wall:"#26262a",floor:"#141416",wall2:"#1a1a1c"},
    dark:{sky:"#080809",wall:"#141416",wall2:"#0d0d0f",floor:"#0a0a0c",light:"#6b7a85"},
    rain:{sky:"#22262b",wall:"#2b2d2e",wall2:"#1c1e21",floor:"#171a1c"},
    blood:{wall:"#331c1c",wall2:"#211212",floor:"#190d0d",light:"#d95244"},
    fire:{sky:"#4d2412",wall:"#4d2b1a",wall2:"#301a0f",floor:"#241209",light:"#ffa848"} };
  return {...base,...(m[v]||{})};
};
function rnd(seed){ let s=seed>>>0; return ()=>{ s=(s*1664525+1013904223)>>>0; return s/4294967296; }; }

function drawBG(){
  const W=bgc.width, H=bgc.height, p=PAL(variant), lm=1-flicker*0.5;
  bx.setTransform(1,0,0,1,0,0); bx.clearRect(0,0,W,H);
  const dim=(hex,k)=>{ const c=parseInt(hex.slice(1),16);
    const r=Math.min(255,((c>>16)&255)*k)|0, g=Math.min(255,((c>>8)&255)*k)|0, b=Math.min(255,(c&255)*k)|0;
    return `rgb(${r},${g},${b})`; };
  const R=(x,y,w,h,col)=>{ bx.fillStyle=col; bx.fillRect(x,y,w,h); };
  R(0,0,W,H,dim(p.wall2,lm));
  const S_=(f)=>f;
  switch(sceneId){
    case "black": R(0,0,W,H,"#000"); break;
    case "white": R(0,0,W,H,"#d9d9d4"); break;
    case "classroom": {
      R(0,0,W,H,dim(p.wall,lm)); R(0,H*0.55,W,H*0.2,dim(p.wall2,lm)); R(0,H*0.72,W,H*0.28,dim(p.floor,lm));
      R(W*0.08,H*0.18,W*0.46,H*0.34,"#1a231e"); bx.strokeStyle="#54483380"; bx.lineWidth=3; bx.strokeRect(W*0.08,H*0.18,W*0.46,H*0.34);
      for(let i=0;i<3;i++){ const wx=W*(0.60+i*0.135); R(wx,H*0.16,W*0.11,H*0.36,p.sky);
        bx.strokeStyle="#40403a"; bx.strokeRect(wx,H*0.16,W*0.11,H*0.36); }
      for(let r=0;r<4;r++) for(let c=0;c<5;c++){
        const d=r/4, dw=W*(0.075+d*0.04), dh=H*(0.035+d*0.025);
        const dx=W*0.5+(c-2)*W*(0.09+d*0.055)-dw/2, dy=H*(0.60+d*0.26);
        const empty=(r===3&&c===4);
        R(dx,dy,dw,dh,dim(empty?"#332b25":"#473c30",lm));
        if(empty){ bx.fillStyle=`rgba(180,192,200,${0.06+0.04*Math.sin(T*1.4)})`; bx.fillRect(dx,dy,dw,dh); } }
      for(let i=0;i<2;i++){ const lx=W*(0.3+i*0.4); const on=variant==="dark"?0.15:1;
        bx.fillStyle=`rgba(235,240,225,${0.5*on*lm})`; bx.fillRect(lx-W*0.09,H*0.06,W*0.18,H*0.022);
        cone(lx,H*0.08,W*0.22,H*0.8,p.light,0.045*on*lm); }
      break; }
    case "office": {
      R(0,0,W,H,dim(p.wall,lm)); R(0,H*0.70,W,H*0.30,dim(p.floor,lm));
      for(let i=0;i<3;i++){ const cx=W*(0.05+i*0.15); R(cx,H*0.22,W*0.13,H*0.5,dim("#3d3a33",lm));
        for(let k=0;k<4;k++){ R(cx+6,H*(0.24+k*0.12),W*0.13-12,H*0.09,dim("#2e2b26",lm)); } }
      R(W*0.52,H*0.55,W*0.42,H*0.12,dim("#4f4032",lm)); R(W*0.52,H*0.67,W*0.42,H*0.22,dim("#382e24",lm));
      R(W*0.52+40,H*0.55-18,130,34,"#d1cdbe"); R(W*0.52+200,H*0.55-14,110,28,"#bdb6a1");
      R(W*0.63,H*0.12,W*0.3,H*0.3,p.sky); break; }
    case "hallway": {
      R(0,0,W,H,dim(p.wall2,lm)); const vx=W*0.5, vy=H*0.52;
      poly([[0,H],[W,H],[vx+W*0.07,vy+H*0.1],[vx-W*0.07,vy+H*0.1]],dim(p.floor,lm));
      poly([[0,0],[W,0],[vx+W*0.07,vy-H*0.1],[vx-W*0.07,vy-H*0.1]],dim(p.wall,lm*0.7));
      R(vx-W*0.07,vy-H*0.1,W*0.14,H*0.2,"#08080a");
      for(let i=0;i<4;i++){ const f=0.16+i*0.19, f2=f+0.14;
        const x0=lerp(0,vx-W*0.07,f), x1=lerp(0,vx-W*0.07,f2);
        const yt=lerp(0,vy-H*0.1,f), yb=lerp(H,vy+H*0.1,f), yt1=lerp(0,vy-H*0.1,f2), yb1=lerp(H,vy+H*0.1,f2);
        poly([[x0,yt+(yb-yt)*0.18],[x1,yt1+(yb1-yt1)*0.18],[x1,yb1],[x0,yb]],dim("#2b2620",lm));
        poly([[W-x0,yt+(yb-yt)*0.18],[W-x1,yt1+(yb1-yt1)*0.18],[W-x1,yb1],[W-x0,yb]],dim("#2b2620",lm)); }
      for(let i=0;i<3;i++){ const f2=0.2+i*0.22, ly=lerp(0,vy-H*0.1,f2+0.2), lw=lerp(W*0.16,W*0.03,f2);
        let on=1; if(i===1) on = 0.25+0.75*(((T*3.1)%1)>0.5?1:0);
        bx.fillStyle=`rgba(235,240,225,${0.5*on*lm})`; bx.fillRect(vx-lw/2,ly,lw,Math.max(2,8*(1-f2)));
        cone(vx,ly,lw*1.6,H*0.6,p.light,0.035*on*lm); }
      break; }
    case "library": {
      R(0,0,W,H,dim("#211c17",lm)); R(0,H*0.78,W,H*0.22,dim("#1a1512",lm));
      for(let i=0;i<5;i++){ const bxx=W*(0.03+i*0.2), bw=W*0.16;
        R(bxx,H*0.08,bw,H*0.72,dim("#30241a",lm));
        for(let sh=0;sh<6;sh++){ const sy=H*(0.10+sh*0.115); R(bxx+4,sy,bw-8,H*0.10,"#17110d");
          const rr=rnd(i*31+sh); let x=bxx+8;
          while(x<bxx+bw-14){ const w=6+rr()*10, h=H*(0.06+rr()*0.035);
            R(x,sy+H*0.10-h,w,h,`rgb(${(46+rr()*60)|0},${(35+rr()*35)|0},${(25+rr()*30)|0})`); x+=w+1.5; } } }
      cone(W*0.5,0,W*0.3,H,p.light,0.03*lm); break; }
    case "dorm": case "dorm_door": {
      if(sceneId==="dorm"){
        R(0,0,W,H,dim(p.wall,lm)); R(0,H*0.74,W,H*0.26,dim(p.floor,lm));
        for(let side=0;side<2;side++){ const bxx=side?W*0.60:W*0.04, bw=W*0.36;
          for(let lv=0;lv<2;lv++){ const by=H*(0.20+lv*0.30);
            R(bxx,by,bw,H*0.06,dim("#4d4740",lm)); R(bxx+6,by-H*0.045,bw-12,H*0.05,dim("#5c4d47",lm));
            R(bxx,by,8,H*0.32,dim("#38352f",lm)); R(bxx+bw-8,by,8,H*0.32,dim("#38352f",lm)); } }
        R(W*0.44,H*0.28,W*0.13,H*0.46,dim("#332921",lm));
        bx.fillStyle=`rgba(215,218,190,${0.10+0.06*Math.sin(T*2.2)})`; bx.fillRect(W*0.44,H*0.74-4,W*0.13,4);
      } else {
        R(0,0,W,H,"#111113"); const dx=W*0.24,dw=W*0.52;
        R(dx,H*0.06,dw,H*0.9,dim("#2b211c",lm));
        R(dx+W*0.05,H*0.14,dw-W*0.10,H*0.3,"#211a15"); R(dx+W*0.05,H*0.56,dw-W*0.10,H*0.3,"#211a15");
        circle(dx+dw/2,H*0.06+H*0.9*0.34,16,"#0d0d0f");
        circle(dx+dw/2,H*0.06+H*0.9*0.34,12,`rgba(140,153,148,${0.25+0.2*Math.sin(T*1.1)})`);
        R(dx,H*0.96-7,dw,7,"rgba(220,220,199,0.22)");
        const sh = S.flags.flag_shadow_count_wrong?3:2;
        for(let i=0;i<sh;i++) R(dx+dw*(0.28+i*0.2),H*0.96-7,26,7,"rgba(0,0,0,0.85)");
      } break; }
    case "oldbuilding_out": {
      R(0,0,W,H,p.sky); R(W*0.08,H*0.14,W*0.84,H*0.72,dim("#292927",lm));
      for(let r=0;r<4;r++) for(let c=0;c<7;c++){
        const wx=W*0.08+W*0.84*(0.05+c*0.132), wy=H*0.14+H*0.72*(0.08+r*0.22);
        const on=(r===1&&c===4); let col="#0d0d0f";
        if(on){ const fl=0.55+0.45*Math.sin(T*6+1.3); col=`rgb(${(217*fl+30)|0},${(184*fl+25)|0},${(107*fl+18)|0})`; }
        R(wx,wy,W*0.84*0.095,H*0.72*0.14,col); }
      R(0,H*0.86,W,H*0.14,dim("#181a14",lm));
      const rr=rnd(99); bx.strokeStyle="rgba(41,51,36,0.7)"; bx.lineWidth=1.5;
      for(let i=0;i<60;i++){ const gx=rr()*W, gh=6+rr()*20; bx.beginPath(); bx.moveTo(gx,H*0.87); bx.lineTo(gx+(rr()*8-4),H*0.87-gh); bx.stroke(); }
      break; }
    case "oldbuilding_stair": {
      R(0,0,W,H,dim("#171717",lm));
      for(let i=0;i<9;i++){ const f=i/9, w=lerp(W*0.9,W*0.3,f), y=H*(0.95-f*0.62), h=lerp(H*0.06,H*0.03,f);
        R(W/2-w/2,y,w,h,dim("#2b2926",1-f*0.5)); R(W/2-w/2,y,w,2,"rgba(77,71,61,0.5)"); }
      R(W*0.35,H*0.06,W*0.3,H*0.28,"#050507"); break; }
    case "broadcast_door": {
      R(0,0,W,H,"#0f0f11"); R(W*0.28,H*0.10,W*0.44,H*0.84,dim("#242627",lm));
      const red=0.5+0.5*Math.sin(T*5);
      R(W*0.72-W*0.06,H*0.10,W*0.06,H*0.84,"#050505");
      bx.fillStyle=`rgba(217,36,26,${0.10+0.30*red})`; bx.fillRect(W*0.72-W*0.06,H*0.10,W*0.06,H*0.84);
      R(W*0.34,H*0.20,W*0.16,H*0.07,"rgba(140,135,117,0.85)"); break; }
    case "broadcast_room": {
      R(0,0,W,H,dim("#141214",lm)); R(0,H*0.76,W,H*0.24,"#0c0c0f");
      for(let r=0;r<5;r++) for(let c=0;c<12;c++)
        R(W*0.05+c*W*0.078,H*0.08+r*H*0.075,W*0.07,H*0.065,dim((r+c)%2?"#211f21":"#1c1a1c",lm));
      R(W*0.12,H*0.58,W*0.76,H*0.2,dim("#2e2b28",lm));
      for(let i=0;i<14;i++){ const fx2=W*0.12+22+i*(W*0.76-44)/14;
        R(fx2,H*0.58+16,6,H*0.2-40,"#191919");
        const kv=0.3+0.5*Math.abs(Math.sin(T*(0.7+i*0.11)));
        R(fx2-5,H*0.58+16+(H*0.2-46)*(1-kv),16,8,"#8c857b"); }
      for(let i=0;i<10;i++){ const on = i/10 < 0.35+0.4*Math.abs(Math.sin(T*3));
        R(W*0.12+20+i*22,H*0.58-22,16,10,on?"rgba(230,64,46,0.9)":"rgba(51,26,26,0.7)"); }
      bx.fillStyle=`rgba(128,20,15,${0.35+0.5*(((T*1.4)%1)>0.5?1:0)})`; bx.fillRect(W*0.40,H*0.03,W*0.2,H*0.05);
      break; }
    case "duty_room": {
      R(0,0,W,H,dim("#26241f",lm)); R(0,H*0.72,W,H*0.28,dim("#1a1815",lm));
      R(W*0.06,H*0.16,W*0.3,H*0.36,dim("#423324",lm));
      for(let r=0;r<3;r++) for(let c=0;c<6;c++){
        const kx=W*0.06+18+c*(W*0.3-36)/6, ky=H*0.16+24+r*(H*0.36-40)/3;
        bx.strokeStyle="rgba(153,140,89,0.8)"; bx.beginPath(); bx.moveTo(kx,ky); bx.lineTo(kx,ky+16); bx.stroke();
        circle(kx,ky+20,5,"rgba(158,143,82,0.85)"); }
      R(W*0.45,H*0.55,W*0.48,H*0.1,dim("#4d3d2b",lm));
      const tv={x:W*0.72,y:H*0.28,w:W*0.2,h:H*0.2}; R(tv.x,tv.y,tv.w,tv.h,"#1a1a1c");
      const rr2=rnd((T*20)|0); for(let i=0;i<200;i++)
        R(tv.x+rr2()*tv.w,tv.y+rr2()*tv.h,2,2,`rgba(180,184,180,${rr2()*0.5})`);
      break; }
    case "schoolyard": {
      R(0,0,W,H,p.sky); R(0,H*0.62,W,H*0.38,dim("#1c211c",lm));
      for(let i=0;i<3;i++){ const bw=W*0.28,bxx=W*(0.02+i*0.33),bh=H*(0.22+(i%2)*0.05);
        R(bxx,H*0.62-bh,bw,bh,dim("#1a1a1f",lm));
        for(let r=0;r<3;r++) for(let c=0;c<5;c++){ const lit=(i+r+c)%7===0;
          R(bxx+12+c*(bw-24)/5,H*0.62-bh+12+r*(bh-24)/3,(bw-24)/7,bh/7,lit?"rgba(217,199,128,0.55)":"#0f0f14"); } }
      bx.strokeStyle="rgba(140,140,140,0.8)"; bx.lineWidth=3;
      bx.beginPath(); bx.moveTo(W*0.5,H*0.62); bx.lineTo(W*0.5,H*0.18); bx.stroke();
      poly([[W*0.5,H*0.19],[W*0.56+Math.sin(T*0.9)*6,H*0.21],[W*0.5,H*0.27]],"rgba(115,31,26,0.85)");
      break; }
    case "history_hall": {
      R(0,0,W,H,dim("#1f1c1c",lm)); R(0,H*0.76,W,H*0.24,dim("#141212",lm));
      for(let i=0;i<6;i++){ const fx2=W*(0.04+i*0.157);
        R(fx2,H*0.16,W*0.13,H*0.24,dim("#382e21",lm)); R(fx2+6,H*0.16+6,W*0.13-12,H*0.24-12,dim("#4d4b44",lm));
        for(let k=0;k<7;k++){ if(i===3&&k===4) continue;
          const hx=fx2+12+k*(W*0.13-24)/7;
          R(hx,H*0.16+H*0.24*0.5,(W*0.13-24)/9,H*0.24*0.34,"#29292e");
          circle(hx+(W*0.13-24)/18,H*0.16+H*0.24*0.46,3.5,"#6b6661"); } }
      R(W*0.12,H*0.52,W*0.76,H*0.2,"rgba(90,107,112,0.14)"); break; }
    case "archive": {
      R(0,0,W,H,dim("#1a1714",lm)); R(0,H*0.78,W,H*0.22,"#121010");
      for(let i=0;i<7;i++){ const rx=W*(0.02+i*0.14); R(rx,H*0.06,W*0.115,H*0.74,dim("#2b2822",lm));
        for(let sh=0;sh<7;sh++){ const sy=H*(0.08+sh*0.10); R(rx+3,sy,W*0.115-6,H*0.085,"#171512");
          const rr3=rnd(i*13+sh);
          for(let k=0;k<6;k++) R(rx+6+k*(W*0.115-14)/6,sy+6,(W*0.115-16)/7,H*0.07,
            `rgb(${(72+rr3()*56)|0},${(61+rr3()*36)|0},${(46+rr3()*26)|0})`); } }
      break; }
    case "monitor_room": {
      R(0,0,W,H,dim("#101216",lm));
      for(let r=0;r<3;r++) for(let c=0;c<4;c++){
        const m={x:W*(0.06+c*0.23),y:H*(0.08+r*0.25),w:W*0.2,h:H*0.2};
        R(m.x,m.y,m.w,m.h,"#1a1a1c"); R(m.x+4,m.y+4,m.w-8,m.h-8,"#0a0d10");
        const rr4=rnd(r*10+c+((T*6)|0));
        if((r*4+c)%5===0){ for(let i=0;i<90;i++) R(m.x+6+rr4()*(m.w-12),m.y+6+rr4()*(m.h-12),2,2,`rgba(180,184,180,${rr4()*0.6})`); }
        else { R(m.x+8,m.y+8,m.w-16,m.h-16,"#141c1f"); R(m.x+m.w*0.4,m.y+m.h*0.45,m.w*0.08,m.h*0.4,"rgba(5,5,5,0.9)"); }
        const scan=((T*0.4+(r*4+c)*0.13)%1); R(m.x+4,m.y+4+scan*(m.h-8),m.w-8,3,"rgba(153,217,204,0.10)"); }
      R(0,H*0.86,W,H*0.14,"#1c1c1f"); break; }
    case "mirror": {
      R(0,0,W,H,"#0f0f11"); R(W*0.1,H*0.12,W*0.8,H*0.52,"#242b2e");
      const off=Math.sin(T*0.8)*8, cx=W*0.5+off;
      circle(cx,H*0.12+H*0.52*0.38,H*0.52*0.13,"rgba(26,28,31,0.9)");
      R(cx-W*0.056,H*0.12+H*0.52*0.52,W*0.112,H*0.52*0.45,"rgba(26,28,31,0.9)");
      R(W*0.08,H*0.66,W*0.84,H*0.08,dim("#4d4f4d",lm)); R(0,H*0.74,W,H*0.26,"#171719"); break; }
    default: { R(0,0,W,H,dim(p.wall2,lm)); R(0,H*0.72,W,H*0.28,dim(p.floor,lm)); }
  }
  // 颗粒
  const g=rnd((T*12)|0);
  for(let i=0;i<90;i++){ bx.fillStyle=`rgba(255,255,255,${g()*0.05})`; bx.fillRect(g()*W,g()*H,2,2); }
  if(variant==="rain"){ bx.strokeStyle="rgba(190,208,224,0.16)"; bx.lineWidth=1.2;
    const rr5=rnd(4242);
    for(let i=0;i<120;i++){ const sp=1+rr5()*2, x=(rr5()*W+T*40*sp)%W, y=(rr5()*H+T*900*sp)%H;
      bx.beginPath(); bx.moveTo(x,y); bx.lineTo(x-5,y+26*sp); bx.stroke(); } }
  if(bloodAmt>0.01 && settings.gore>0){ const rr6=rnd(7);
    const nn=(bloodAmt*(settings.gore===1?10:26))|0;
    for(let i=0;i<nn;i++){ const cx2=rr6()*W, cy=H*(0.35+rr6()*0.6), r2=(6+rr6()*28)*(settings.gore===1?0.6:1);
      circle(cx2,cy,r2,`rgba(107,15,18,${0.55*bloodAmt})`);
      if(settings.gore===2&&rr6()<0.6){ const h=(20+rr6()*100)*bloodAmt;
        R(cx2-r2*0.18,cy,r2*0.36,h,`rgba(107,15,18,${0.4*bloodAmt})`); } } }
  // 暗角
  const grad=bx.createRadialGradient(W/2,H/2,Math.min(W,H)*0.28,W/2,H/2,Math.max(W,H)*0.75);
  grad.addColorStop(0,"rgba(0,0,0,0)"); grad.addColorStop(1,"rgba(0,0,0,0.72)");
  bx.fillStyle=grad; bx.fillRect(0,0,W,H);
  drawActors();
}
function lerp(a,b,t){ return a+(b-a)*t; }
function poly(pts,col){ bx.fillStyle=col; bx.beginPath(); bx.moveTo(pts[0][0],pts[0][1]);
  for(let i=1;i<pts.length;i++) bx.lineTo(pts[i][0],pts[i][1]); bx.closePath(); bx.fill(); }
function circle(x,y,r,col){ bx.fillStyle=col; bx.beginPath(); bx.arc(x,y,r,0,Math.PI*2); bx.fill(); }
function cone(x,y,w,h,col,a){ const c=parseInt(col.slice(1),16);
  bx.fillStyle=`rgba(${(c>>16)&255},${(c>>8)&255},${c&255},${a})`;
  bx.beginPath(); bx.moveTo(x,y); bx.lineTo(x-w,y+h); bx.lineTo(x+w,y+h); bx.closePath(); bx.fill(); }

// ---------------------------------------------------------------- 立绘
let actors=[]; // {who,emo,pos,active}
function drawActors(){
  const W=bgc.width,H=bgc.height;
  const slots={farleft:0.10,left:0.22,center:0.5,right:0.78,farright:0.90};
  actors.forEach((a,i)=>{
    const fr = slots[a.pos]!==undefined ? slots[a.pos] : 0.5+(i-(actors.length-1)*0.5)*0.26;
    drawActor(a, W*fr, H*0.94-H*0.16, H*0.66);
  });
}
function drawActor(a,cx,ground,height){
  const info=CHARS[a.who]||{c:"#cccccc"};
  const dim=a.active?1:0.45;
  const br=Math.sin(T*(a.who==="shenhe"?0.55:1.1))*2;
  const headR=height*0.072, headY=ground-height+headR*1.2+br;
  bx.globalAlpha=1;
  circle(cx,ground,height*0.09,"rgba(0,0,0,0.35)");
  const mix=(hex,k)=>{ const c=parseInt(hex.slice(1),16);
    return `rgba(${(((c>>16)&255)*k)|0},${(((c>>8)&255)*k)|0},${((c&255)*k)|0},1)`; };
  let uniform=mix(a.who==="shenhe"?"#3d4d4f":(a.who==="xuqing"?"#473c45":"#333a45"),dim);
  let skin=mix(a.who==="shenhe"?"#c7d1cd":"#b8a89b",dim);
  const bodyDark=mix("#282a2e",dim);
  const legW=height*0.052;
  bx.fillStyle=bodyDark; bx.fillRect(cx-legW*1.5,ground-height*0.42,legW,height*0.42);
  bx.fillRect(cx+legW*0.5,ground-height*0.42,legW,height*0.42);
  if(a.who!=="xuqing"){ bx.fillStyle=mix("#1a1a1c",dim);
    bx.fillRect(cx-legW*1.7,ground-height*0.035,legW*1.5,height*0.035);
    bx.fillRect(cx+legW*0.3,ground-height*0.035,legW*1.5,height*0.035); }
  const tW=height*0.19, tH=height*0.40, tX=cx-tW/2, tY=ground-height*0.42-tH+br*0.4;
  bx.fillStyle=uniform; bx.fillRect(tX,tY,tW,tH);
  bx.fillStyle=`rgba(210,212,216,${0.55*dim})`; bx.fillRect(tX,tY+tH*0.16,tW,tH*0.045);
  bx.fillStyle=`rgba(64,89,140,${0.6*dim})`; bx.fillRect(tX,tY+tH*0.22,tW,tH*0.02);
  const armW=height*0.042, sw=Math.sin(T*1.05)*3;
  bx.fillStyle=uniform; bx.fillRect(tX-armW*0.9,tY+tH*0.06+sw,armW,tH*0.82);
  bx.fillRect(tX+tW-armW*0.1,tY+tH*0.06-sw,armW,tH*0.82);
  circle(tX-armW*0.4,tY+tH*0.9+sw,armW*0.55,skin);
  circle(tX+tW+armW*0.4,tY+tH*0.9-sw,armW*0.55,skin);
  bx.fillStyle=skin; bx.fillRect(cx-headR*0.34,tY-headR*0.55,headR*0.68,headR*0.6);
  circle(cx,headY,headR,skin);
  // 头发
  const hair=mix("#17161a",dim);
  if(a.who==="shenhe"||a.who==="voice"){ circle(cx,headY-headR*0.15,headR*1.06,mix("#12171a",dim));
    bx.strokeStyle=mix("#12171a",dim); bx.lineWidth=3;
    for(let i=0;i<11;i++){ const hx=cx-headR+i*headR*0.2, wv=Math.sin(T*0.7+i)*headR*0.12;
      bx.beginPath(); bx.moveTo(hx,headY-headR*0.4); bx.lineTo(hx+wv,headY+headR*2.6); bx.stroke(); } }
  else if(a.who==="xuqing"){ circle(cx,headY-headR*0.2,headR*1.04,hair);
    bx.fillStyle=hair; bx.fillRect(cx-headR*1.15,headY-headR*0.4,headR*0.32,headR*1.9);
    bx.fillRect(cx+headR*0.83,headY-headR*0.4,headR*0.32,headR*1.9); }
  else if(a.who==="zhouxu"){ bx.fillStyle=hair; bx.fillRect(cx-headR*1.02,headY-headR*1.18,headR*2.04,headR*0.95); }
  else if(a.who==="liangye"){ circle(cx,headY-headR*0.25,headR*1.05,hair);
    bx.strokeStyle=hair; bx.lineWidth=2.5;
    for(let i=0;i<6;i++){ const an=-Math.PI*0.9+i*0.32; bx.beginPath();
      bx.moveTo(cx+Math.cos(an)*headR*0.95,headY+Math.sin(an)*headR*0.95);
      bx.lineTo(cx+Math.cos(an)*headR*1.42,headY+Math.sin(an)*headR*1.42); bx.stroke(); } }
  else if(a.who==="oldqin"){ bx.strokeStyle=mix("#8c8b80",dim); bx.lineWidth=5;
    bx.beginPath(); bx.arc(cx,headY-headR*0.1,headR,Math.PI*1.05,Math.PI*1.95); bx.stroke(); }
  else circle(cx,headY-headR*0.2,headR*1.02,hair);
  // 表情
  const ink=mix("#0f0f12",dim), ex=headR*0.38, ey=headY-headR*0.08;
  bx.fillStyle=ink; bx.strokeStyle=ink; bx.lineWidth=2.4;
  const e=a.emo||"normal";
  if(["fear","panic","terrified"].includes(e)){
    circle(cx-ex,ey,headR*0.17,mix("#eaeae6",dim)); circle(cx+ex,ey,headR*0.17,mix("#eaeae6",dim));
    circle(cx-ex,ey,headR*0.075,ink); circle(cx+ex,ey,headR*0.075,ink);
    bx.beginPath(); bx.arc(cx,headY+headR*0.42,headR*0.22,Math.PI*0.15,Math.PI*0.85); bx.stroke();
  } else if(["hollow","dead","void"].includes(e)){
    circle(cx-ex,ey,headR*0.16,"#08080a"); circle(cx+ex,ey,headR*0.16,"#08080a");
    bx.beginPath(); bx.moveTo(cx-headR*0.18,headY+headR*0.46); bx.lineTo(cx+headR*0.18,headY+headR*0.46); bx.stroke();
  } else if(["smile","smirk"].includes(e)){
    bx.beginPath(); bx.moveTo(cx-ex-headR*0.12,ey); bx.lineTo(cx-ex+headR*0.12,ey-headR*0.05); bx.stroke();
    bx.beginPath(); bx.moveTo(cx+ex-headR*0.12,ey-headR*0.05); bx.lineTo(cx+ex+headR*0.12,ey); bx.stroke();
    bx.beginPath(); bx.arc(cx,headY+headR*0.28,headR*0.28,Math.PI*0.18,Math.PI*0.82); bx.stroke();
  } else if(["sad","tired"].includes(e)){
    bx.beginPath(); bx.arc(cx-ex,ey,headR*0.14,Math.PI,Math.PI*2); bx.stroke();
    bx.beginPath(); bx.arc(cx+ex,ey,headR*0.14,Math.PI,Math.PI*2); bx.stroke();
  } else if(["cold","flat","angry"].includes(e)){
    bx.beginPath(); bx.moveTo(cx-ex-headR*0.14,ey); bx.lineTo(cx-ex+headR*0.14,ey); bx.stroke();
    bx.beginPath(); bx.moveTo(cx+ex-headR*0.14,ey); bx.lineTo(cx+ex+headR*0.14,ey); bx.stroke();
    bx.beginPath(); bx.moveTo(cx-headR*0.2,headY+headR*0.44); bx.lineTo(cx+headR*0.2,headY+headR*0.44); bx.stroke();
  } else {
    bx.fillRect(cx-ex-headR*0.12,ey-headR*0.055,headR*0.24,headR*0.11);
    bx.fillRect(cx+ex-headR*0.12,ey-headR*0.055,headR*0.24,headR*0.11);
    bx.beginPath(); bx.moveTo(cx-headR*0.16,headY+headR*0.44); bx.lineTo(cx+headR*0.16,headY+headR*0.44); bx.stroke();
  }
  if(a.who==="shenhe"){ bx.strokeStyle="rgba(153,191,191,0.35)"; bx.lineWidth=1.5;
    for(let i=0;i<5;i++){ const dx2=cx+(i-2)*headR*0.35, dy=headY+headR*0.9+((T*60+i*33)%(height*0.35));
      bx.beginPath(); bx.moveTo(dx2,dy); bx.lineTo(dx2,dy+8); bx.stroke(); }
    bx.fillStyle="rgba(15,10,8,0.9)"; bx.fillRect(tX-armW,tY+tH*0.78,armW*1.4,tH*0.12);
    bx.fillRect(tX+tW-armW*0.3,tY+tH*0.78,armW*1.4,tH*0.12);
    // 异常重影
    bx.globalAlpha=0.10; circle(cx+Math.sin(T*7)*9,headY,headR,"#b3e6dd"); bx.globalAlpha=1; }
  if(a.active){ bx.strokeStyle=info.c+"33"; bx.lineWidth=2;
    bx.beginPath(); bx.arc(cx,headY,headR+3,0,Math.PI*2); bx.stroke(); }
}

// ---------------------------------------------------------------- 特效
let effects=[], shakeOff={x:0,y:0}, namesPool=[];
const FXDUR={shake:.5,bigshake:1.1,flash:.35,redflash:.5,glitch:.9,static:1.2,blood:2.4,bloodburst:1.6,
  fog:4,heartbeat:3,names:3.2,darken:2,whiteout:1.4,scanlines:2.5,crack:1.8,handprint:3,eyes:2.6,rewind:1.5,flicker:1.2};
function playFX(name,power=1){
  if((name==="shake"||name==="bigshake")&&!settings.shake) return;
  if(["flash","whiteout","redflash"].includes(name)&&!settings.flash) power*=0.25;
  if(["blood","bloodburst","handprint"].includes(name)&&settings.gore===0) return;
  if(["blood","bloodburst"].includes(name)&&settings.gore===1) power*=0.5;
  if(name==="flicker"){ flicker=1; return; }
  if(name==="names") namesPool=["沈禾","沈禾（删除）","林昼（补）","林昼（待定）","梁野","周叙","第109次"];
  if(["blood","bloodburst"].includes(name)) bloodAmt=Math.min(1,bloodAmt+0.35*power);
  effects.push({name,t:0,dur:FXDUR[name]||0.6,power});
  sfx(name);
}
function drawFX(dt){
  const W=fxc.width,H=fxc.height;
  fx.setTransform(1,0,0,1,0,0); fx.clearRect(0,0,W,H);
  shakeOff={x:0,y:0};
  effects=effects.filter(e=>{ e.t+=dt; return e.t<e.dur; });
  for(const e of effects){
    const f=e.t/e.dur, p=e.power*(1-f);
    switch(e.name){
      case "shake": shakeOff.x+=(Math.random()*2-1)*9*p; shakeOff.y+=(Math.random()*2-1)*9*p; break;
      case "bigshake": shakeOff.x+=(Math.random()*2-1)*26*p; shakeOff.y+=(Math.random()*2-1)*26*p; break;
      case "flash": fx.fillStyle=`rgba(255,255,255,${(1-f)*0.72*e.power})`; fx.fillRect(0,0,W,H); break;
      case "whiteout": fx.fillStyle=`rgba(242,242,235,${Math.max(0,(1-Math.abs(f-0.35)/0.65))*e.power*0.92})`; fx.fillRect(0,0,W,H); break;
      case "redflash": fx.fillStyle=`rgba(153,13,10,${(1-f)*0.55*e.power})`; fx.fillRect(0,0,W,H); break;
      case "darken": fx.fillStyle=`rgba(0,0,0,${Math.sin(Math.PI*f)*0.8*e.power})`; fx.fillRect(0,0,W,H); break;
      case "static": { const r=rnd((T*24)|0);
        for(let i=0;i<700;i++){ fx.fillStyle=`rgba(217,222,217,${r()*0.35*p})`; fx.fillRect(r()*W,r()*H,3,2); } break; }
      case "scanlines": { for(let y=0;y<H;y+=4){ fx.fillStyle=`rgba(0,0,0,${0.18*p})`; fx.fillRect(0,y,W,1.5); } break; }
      case "glitch": { const r=rnd(((T*24)|0)*7);
        for(let i=0;i<12;i++){ const y=r()*H,h=4+r()*30,dx=(r()*80-40)*p;
          fx.fillStyle=`rgba(230,51,51,${0.06*p})`; fx.fillRect(dx,y,W,h);
          fx.fillStyle=`rgba(51,230,217,${0.06*p})`; fx.fillRect(-dx,y+3,W,h); } break; }
      case "bloodburst": case "blood": { if(settings.gore===0)break; const r=rnd(1234);
        const nn=e.name==="bloodburst"?(settings.gore===2?40:16):12;
        for(let i=0;i<nn;i++){ const x=r()*W,y=r()*H,rr=(8+r()*38)*p;
          fx.fillStyle=`rgba(158,23,23,${0.5*p})`; fx.beginPath(); fx.arc(x,y,rr,0,Math.PI*2); fx.fill();
          if(settings.gore===2){ fx.fillRect(x-rr*0.14,y,rr*0.28,rr*(1+r()*3)); } } break; }
      case "fog": { const r=rnd(77); const a=Math.sin(Math.PI*f)*e.power;
        for(let i=0;i<26;i++){ const bx2=((r()*W+T*(4+r()*12))%(W+300))-150, by=r()*H, rr=80+r()*180;
          fx.fillStyle=`rgba(168,179,184,${0.022*a})`; fx.beginPath(); fx.arc(bx2,by,rr,0,Math.PI*2); fx.fill(); } break; }
      case "heartbeat": { const beat=Math.pow(Math.max(0,Math.sin(f*Math.PI*6)),6), a=beat*0.42*e.power;
        const g=fx.createRadialGradient(W/2,H/2,Math.min(W,H)*0.2,W/2,H/2,Math.max(W,H)*0.7);
        g.addColorStop(0,"rgba(0,0,0,0)"); g.addColorStop(1,`rgba(92,5,5,${a})`);
        fx.fillStyle=g; fx.fillRect(0,0,W,H); break; }
      case "names": { const r=rnd(909);
        namesPool.forEach((txt,i)=>{ const x=(0.05+r()*0.65)*W, y=(0.12+r()*0.78)*H;
          const lf=Math.max(0,Math.min(1,(f-i*0.06)*1.6)), a=Math.sin(Math.PI*lf)*0.5*e.power;
          fx.fillStyle=`rgba(217,217,209,${a})`; fx.font=`${(26+r()*32)|0}px serif`; fx.fillText(txt,x,y); }); break; }
      case "eyes": { const r=rnd(2024), a=Math.sin(Math.PI*f)*0.5*e.power;
        for(let i=0;i<9;i++){ const x=r()*W,y=r()*H*0.85,rr=6+r()*9;
          fx.fillStyle=`rgba(230,230,224,${a*0.5})`; fx.beginPath(); fx.arc(x,y,rr,0,Math.PI*2); fx.fill();
          fx.fillStyle=`rgba(10,10,12,${a})`; fx.beginPath(); fx.arc(x,y,rr*0.42,0,Math.PI*2); fx.fill(); } break; }
      case "handprint": { if(settings.gore===0)break; const a=Math.sin(Math.PI*Math.min(1,f*1.2))*e.power*0.7;
        const cx=W*0.72, cy=H*0.44, sc=H*0.16;
        fx.fillStyle=`rgba(107,15,18,${a})`; fx.beginPath(); fx.arc(cx,cy,sc*0.42,0,Math.PI*2); fx.fill();
        for(let i=0;i<5;i++){ const an=-Math.PI*0.85+i*0.42, tx=cx+Math.cos(an)*sc*0.75, ty=cy+Math.sin(an)*sc*0.75;
          fx.lineWidth=sc*0.16; fx.strokeStyle=`rgba(107,15,18,${a})`;
          fx.beginPath(); fx.moveTo(cx,cy); fx.lineTo(tx,ty); fx.stroke(); } break; }
      case "crack": { const r=rnd(31337), a=Math.min(1,f*3)*e.power*0.6;
        fx.strokeStyle=`rgba(217,224,230,${a})`;
        for(let i=0;i<14;i++){ let an=r()*Math.PI*2, px=W*0.5, py=H*0.42;
          const len=(60+r()*W*0.4)*Math.min(1,f*2);
          for(let k=0;k<6;k++){ const nx=px+Math.cos(an)*(len/6), ny=py+Math.sin(an)*(len/6);
            fx.lineWidth=Math.max(0.6,2.5-k*0.3); fx.beginPath(); fx.moveTo(px,py); fx.lineTo(nx,ny); fx.stroke();
            an+=r()*0.7-0.35; px=nx; py=ny; } } break; }
      case "rewind": { const a=(1-f)*e.power;
        for(let y=0;y<H;y+=7){ const dx=Math.sin((y/H)*40+T*30)*12*a;
          fx.fillStyle=`rgba(204,230,224,${0.08*a})`; fx.fillRect(dx,y,W,2); } break; }
    }
  }
  document.getElementById("app").style.transform = (shakeOff.x||shakeOff.y)
    ? `translate(${shakeOff.x/devicePixelRatio}px,${shakeOff.y/devicePixelRatio}px)` : "";
}

// ---------------------------------------------------------------- 音频（WebAudio 程序化）
let AC=null;
function ac(){ if(!AC) AC=new (window.AudioContext||window.webkitAudioContext)(); return AC; }
let bgmNodes=[], ambNode=null;
function stopBGM(){ bgmNodes.forEach(nd=>{try{nd.stop()}catch(e){}}); bgmNodes=[]; }
function playBGM(id){
  stopBGM(); const c=ac();
  const freqMap={ bgm_title:[55,82.5,110],bgm_menu:[55,82.5,110],bgm_day_class:[98,147],bgm_unease:[61.7,92.5,123.4],
    bgm_investigate:[73.4,110],bgm_rollcall:[58,87,232],bgm_horror:[43.6,65.4,87.3],bgm_chase:[49,98],
    bgm_truth:[65.4,98,130.8],bgm_final:[49,73.4,146.8],bgm_ending_true:[65.4,98,164.8],bgm_ending_bad:[41.2,61.7] };
  const fs=freqMap[id]||[60,90];
  const g=c.createGain(); g.gain.value=0.055; g.connect(c.destination);
  fs.forEach((f,i)=>{ const o=c.createOscillator(); o.type=i%2?"triangle":"sine"; o.frequency.value=f;
    const gg=c.createGain(); gg.gain.value=1/(1+i); o.connect(gg); gg.connect(g); o.start(); bgmNodes.push(o); });
  bgmNodes.push({stop:()=>g.disconnect()});
}
function noiseBuf(dur,cut){ const c=ac(), sr=c.sampleRate, b=c.createBuffer(1,sr*dur,sr), d=b.getChannelData(0);
  let prev=0; for(let i=0;i<d.length;i++){ const w=Math.random()*2-1; prev=prev+cut*(w-prev); d[i]=prev; } return b; }
function playAmb(id){ if(ambNode){try{ambNode.stop()}catch(e){}} const c=ac();
  const cut = id==="amb_rain"?0.35:(id==="amb_broadcast_static"?0.6:0.03);
  const src=c.createBufferSource(); src.buffer=noiseBuf(3,cut); src.loop=true;
  const g=c.createGain(); g.gain.value = id==="amb_rain"?0.05:(id==="amb_broadcast_static"?0.035:0.025);
  src.connect(g); g.connect(c.destination); src.start(); ambNode=src; }
function sfx(id,vol=1){
  const c=ac(), t=c.currentTime;
  const beep=(f,d,type="sine",v=0.12,slide=0)=>{ const o=c.createOscillator(),g=c.createGain();
    o.type=type; o.frequency.setValueAtTime(f,t); if(slide) o.frequency.exponentialRampToValueAtTime(Math.max(20,f+slide),t+d);
    g.gain.setValueAtTime(v*vol,t); g.gain.exponentialRampToValueAtTime(0.0001,t+d);
    o.connect(g); g.connect(c.destination); o.start(t); o.stop(t+d); };
  const nz=(d,cut,v=0.15)=>{ const s=c.createBufferSource(); s.buffer=noiseBuf(d,cut);
    const g=c.createGain(); g.gain.setValueAtTime(v*vol,t); g.gain.exponentialRampToValueAtTime(0.0001,t+d);
    s.connect(g); g.connect(c.destination); s.start(t); s.stop(t+d); };
  switch(id){
    case "sfx_click": beep(1400,0.05,"square",0.05); break;
    case "sfx_page": nz(0.3,0.5,0.10); break;
    case "sfx_knock_soft": case "sfx_knock_pattern":
      [0,0.32,0.64,1.45,1.78].forEach(dt=>setTimeout(()=>beep(96,0.18,"sine",0.22),dt*1000)); break;
    case "sfx_knock_hard": [0,0.26,0.52].forEach(dt=>setTimeout(()=>beep(90,0.2,"sine",0.3),dt*1000)); break;
    case "sfx_door": beep(220,1.0,"sawtooth",0.05,-80); break;
    case "sfx_door_slam": beep(62,0.5,"sine",0.35); nz(0.3,0.2,0.2); break;
    case "sfx_broadcast_click": beep(320,0.08,"square",0.10); break;
    case "static": case "sfx_broadcast_static": case "glitch": nz(1.0,0.6,0.10); break;
    case "heartbeat": [0,0.28,1.0,1.28,2.0,2.28].forEach(dt=>setTimeout(()=>beep(44,0.22,"sine",0.3),dt*1000)); break;
    case "sfx_heartbeat": [0,0.28].forEach(dt=>setTimeout(()=>beep(44,0.22,"sine",0.3),dt*1000)); break;
    case "sfx_scream": beep(620,1.0,"sawtooth",0.10,-320); break;
    case "sfx_whisper": nz(1.2,0.25,0.07); break;
    case "sfx_glass": for(let i=0;i<10;i++) setTimeout(()=>beep(1600+Math.random()*3000,0.12,"triangle",0.05),i*30); break;
    case "sfx_step": nz(0.16,0.35,0.10); break;
    case "sfx_steps_run": for(let i=0;i<7;i++) setTimeout(()=>nz(0.12,0.35,0.10),i*220); break;
    case "sfx_chair": beep(320,0.5,"sawtooth",0.05,-100); break;
    case "sfx_sting": beep(1100,0.9,"sawtooth",0.10,-950); break;
    case "sfx_low_boom": case "shake": beep(36,1.2,"sine",0.28,-14); break;
    case "bigshake": beep(30,1.6,"sine",0.35,-12); break;
    case "sfx_water": beep(1400,0.12,"sine",0.09,-700); break;
    case "sfx_flesh": case "bloodburst": nz(0.4,0.12,0.22); break;
    case "sfx_bell": [523.25,659.25,784].forEach((f,i)=>setTimeout(()=>beep(f,1.6,"sine",0.08),i*40)); break;
    case "sfx_write": nz(0.5,0.45,0.05); break;
    case "sfx_lighter": nz(0.05,0.9,0.2); break;
    case "sfx_fire_burst": nz(1.4,0.1,0.2); break;
    case "rewind": case "sfx_rewind": beep(2600,0.8,"sawtooth",0.07,-1800); break;
    case "sfx_breath": nz(1.2,0.08,0.12); break;
    case "names": nz(1.0,0.25,0.06); break;
  }
}

// ---------------------------------------------------------------- 运行时
let curNode=null, ip=0, waitingChoice=false, typing=false, fullText="", shown=0,
    autoMode=false, skipMode=false, autoTimer=0, blocked=false, pendingWait=0, curWho="";

function start(id){
  if(!NODES[id]){ console.error("节点不存在",id); return; }
  curNode=NODES[id]; ip=0; S.visited.add(id); S.curId=id; waitingChoice=false; advance();
}
function advance(){
  if(!curNode||waitingChoice||blocked) return;
  while(ip<curNode.length){
    const ins=curNode[ip]; ip++;
    if(ins.op==="say"){ showLine(ins); return; }
    if(ins.op==="branch"){ if(!ev(ins.cond)) ip=ins.jump; continue; }
    if(ins.op==="jump"){ ip=ins.jump; continue; }
    if(ins.op==="choices"){
      const vis=ins.choices.filter(c=>!c.cond||ev(c.cond));
      if(!vis.length) continue;
      waitingChoice=true; showChoices(vis); return;
    }
    if(execCmd(ins)) return;
  }
}
function execCmd(ins){
  const {cmd,args,rest}=ins;
  switch(cmd){
    case "bg": sceneId=args[0]; variant=args[1]||""; bloodAmt = variant==="blood"?0.8:0; break;
    case "bgm": playBGM(args[0]); break;
    case "stopbgm": stopBGM(); break;
    case "amb": playAmb(args[0]); break;
    case "stopamb": if(ambNode){try{ambNode.stop()}catch(e){} ambNode=null;} break;
    case "sfx": sfx(args[0],parseFloat(args[1]||"1")); break;
    case "fx": playFX(args[0],parseFloat(args[1]||"1")); break;
    case "show": { const ex=actors.find(a=>a.who===args[0]);
      if(ex){ ex.emo=args[1]||"normal"; ex.pos=args[2]||ex.pos; }
      else actors.push({who:args[0],emo:args[1]||"normal",pos:args[2]||"center",active:false}); break; }
    case "hide": actors=actors.filter(a=>a.who!==args[0]); break;
    case "clearchars": actors=[]; break;
    case "set": { const v=args[1];
      if(v.startsWith("=")) setNum(args[0],+v.slice(1)); else addNum(args[0],+v); refreshStats(); break; }
    case "flag": S.flags[args[0]] = !(args[1]&&args[1].toLowerCase()==="false"); break;
    case "state": S.states[args[0]]=args[1]; break;
    case "item": if(args[0].startsWith("-")) S.items.delete(args[0].slice(1));
      else { const id=args[0].replace(/^\+/,""); S.items.add(id); toast("获得道具："+(ITEMS[id]?.name||id)); } break;
    case "clue": S.clues.add(args[0]); toast("线索："+(CLUES[args[0]]?.name||args[0])); break;
    case "death": if(!S.deaths.includes(args[0])) S.deaths.push(args[0]); break;
    case "gallery": break;
    case "title": bigCard("",rest); return true;
    case "note": noteCard(rest.replace(/\\n/g,"\n")); return true;
    case "roster": rosterCard(); return true;
    case "time": case "timeat": case "advtime": break;
    case "wait": blocked=true; pendingWait=parseFloat(args[0]||"1"); return true;
    case "chapter": { S.chapter=+args[0]; bigCard(+args[0]>=5?"第 终 章":"第 "+args[0]+" 章",rest.slice(args[0].length).trim()); return true; }
    case "settle": settle(+args[0]); break;
    case "autosave": save("auto"); break;
    case "goto": { let t=args[0]; if(t==="__ending__") t=determineEnding(); start(t); return true; }
    case "ending": { let e=args[0]==="auto"?determineEnding():args[0]; showEnding(e); return true; }
    case "return": return true;
  }
  return false;
}

// ---------------------------------------------------------------- 文本显示
function corrupt(t){
  const san=n("sanity"); if(san>=40) return t;
  const rate = san>=25?0.02:(san>=10?0.05:0.09);
  const pool=["到","沈","禾","补","缺","名","昼","█","…"];
  let out=""; for(const ch of t) out += (Math.random()<rate&&ch.trim()) ? pool[(Math.random()*pool.length)|0] : ch;
  return out;
}
function showLine(l){
  clearChoices();
  curWho=l.who||"";
  const txt=corrupt(l.text);
  S.history.push({who:curWho,text:txt});
  elWho.textContent = curWho ? (CHARS[curWho]?.n||curWho) : "";
  elWho.style.color = curWho ? (CHARS[curWho]?.c||"#dcb887") : "";
  actors.forEach(a=>a.active = a.who===curWho);
  const cls = l.style==="narration"?"narr":(l.style==="note"?"note":"");
  fullText=txt; shown=0; typing=true;
  elText.innerHTML = `<span class="${cls}"></span>`;
  elNext.style.display="none";
}
function showChoices(list){
  clearChoices(); elNext.style.display="none"; sfx("sfx_chair");
  list.forEach(c=>{
    const enabled = !c.lock || ev(c.lock);
    const b=document.createElement("button");
    b.innerHTML = c.text + (enabled?"":` <span class="hint">〔条件未满足〕</span>`);
    if(!enabled) b.className="locked";
    b.onclick=()=>{ if(!enabled) return; sfx("sfx_click");
      clearChoices(); waitingChoice=false;
      S.history.push({who:"__choice__",text:c.text});
      c.effects.forEach(execCmd);
      if(c.target) start(c.target); else advance(); };
    elChoices.appendChild(b);
  });
}
function clearChoices(){ elChoices.innerHTML=""; }

// ---------------------------------------------------------------- 浮层
function bigCard(idx,title){
  blocked=true; sfx("sfx_bell");
  const d=document.createElement("div"); d.className="bigcard";
  d.innerHTML = `${idx?`<div class="idx">${idx}</div>`:""}<div class="t">${title}</div>`;
  d.style.opacity=0; document.getElementById("app").appendChild(d);
  d.animate([{opacity:0},{opacity:1},{opacity:1},{opacity:0}],{duration:3600,easing:"ease"}).onfinish=()=>{
    d.remove(); blocked=false; advance(); };
}
function noteCard(text){
  blocked=true; sfx("sfx_page");
  const m=document.createElement("div"); m.className="modal";
  m.innerHTML=`<div class="paper">${text}</div>`;
  m.onclick=()=>{ m.remove(); blocked=false; sfx("sfx_page"); advance(); };
  document.getElementById("app").appendChild(m);
}
function rosterCard(){
  blocked=true; sfx("sfx_page");
  const zt = {enter_with_player:"（在册 / 同行）",pressure_player:"（在册 / 门外）"}[S.states.zhouxu_end_state]||"（在册）";
  const lt = {present_anchor:"（在册 / 锚）",present_fragile_truth:"（在册 / 已听见）",absent_echo:"（缺失 / 已听见）"}
    [S.states.liangye_end_state] || (S.states.liangye_state==="missing_marked"?"（待定 / 缺失）":"（旁听）");
  let pt="（待定"; if(S.flags.flag_true_linday_status_known) pt+=" / 可补";
  if(n("shenhe_focus")>=10) pt+=" / 替补候选"; pt+="）";
  const lines=["高二（三）班　补录名单","————————————————",
    "周叙　　"+zt,"梁野　　"+lt,"许清　　（记录）",
    "沈禾　　"+(S.flags.flag_name_written_back?"（被写回）":"（删除未完成）"),
    "林昼　　"+pt, "————————————————","未到齐者，晚自习不下课。"];
  const m=document.createElement("div"); m.className="modal";
  m.innerHTML=`<div class="paper center">${lines.join("\n")}</div>`;
  m.onclick=()=>{ m.remove(); blocked=false; advance(); };
  document.getElementById("app").appendChild(m);
}
function toast(text){
  const d=document.createElement("div");
  d.style.cssText="position:absolute;top:64px;left:50%;transform:translateX(-50%);z-index:45;"+
    "background:rgba(20,20,22,.95);border:1px solid rgba(180,133,82,.8);padding:9px 20px;font-size:15px;color:#eaD6ae;";
  d.textContent=text; document.getElementById("app").appendChild(d);
  d.animate([{opacity:0},{opacity:1},{opacity:1},{opacity:0}],{duration:2600}).onfinish=()=>d.remove();
}
function sheet(title,html){
  const m=document.createElement("div"); m.className="modal";
  m.innerHTML=`<div class="sheet"><h2>${title}</h2>${html}<div style="text-align:right;margin-top:14px">
    <button class="btn" id="__cl">关闭</button></div></div>`;
  m.querySelector("#__cl").onclick=()=>m.remove();
  m.onclick=e=>{ if(e.target===m) m.remove(); };
  document.getElementById("app").appendChild(m);
}

// ---------------------------------------------------------------- 结局
function showEnding(id){
  const info=ENDING_INFO[id]||ENDING_INFO.ending_empty_seat;
  playBGM(id==="ending_true_release"?"bgm_ending_true":"bgm_ending_bad");
  if(ambNode){try{ambNode.stop()}catch(e){}}
  const rec=JSON.parse(localStorage.getItem("wzx_endings")||"{}");
  rec[id]=(rec[id]||0)+1; localStorage.setItem("wzx_endings",JSON.stringify(rec));
  const clueList=Object.keys(CLUES).length;
  const m=document.createElement("div"); m.className="modal";
  m.innerHTML=`<div class="sheet center">
    <div style="color:#8a8781;font-size:14px;letter-spacing:3px">${info.tag}</div>
    <h2 style="font-size:42px;color:${info.c};margin:8px 0 18px">${info.t}</h2>
    <div class="row" style="border:none">真相 ${n("truth")}　理智 ${n("sanity")}　回响 ${n("memory_echo")}　关注 ${n("shenhe_focus")}</div>
    <div class="row" style="border:none">线索 ${S.clues.size} / ${clueList}　　${S.deaths.length?("失去："+S.deaths.join("、")):"无人失去"}</div>
    <div class="row" style="border:none;color:#c9a24a">${hintFor(id)}</div>
    <div style="margin-top:16px"><button class="btn" id="__again">再来一次</button></div></div>`;
  m.querySelector("#__again").onclick=()=>location.reload();
  document.getElementById("app").appendChild(m);
}
function hintFor(id){
  return {
    ending_true_release:"你把她的名字念全了。试试别的路：接管，或者点火。",
    ending_bittersweet_exchange:"真结局需要：写回名字 + 夜间核对名单 + 完整真相 + 梁野还在。",
    ending_manager:"救人线分数够高时（救梁野、补沈禾名字、先点沈禾），会出现另一条路。",
    ending_destroyer:"火能烧掉名单，但烧不掉“少一个人”这件事本身。",
    ending_empty_seat:"不要替任何人答“到”。先把她的名字弄全。",
  }[id]||"";
}

// ---------------------------------------------------------------- 存档
function save(slot){ try{ localStorage.setItem("wzx_"+slot, JSON.stringify({
  nums:S.nums,flags:S.flags,states:S.states,items:[...S.items],clues:[...S.clues],
  visited:[...S.visited],deaths:S.deaths,chapter:S.chapter,node:S.curId })); }catch(e){} }
function load(slot){ const raw=localStorage.getItem("wzx_"+slot); if(!raw) return false;
  const d=JSON.parse(raw); S.nums={...NUM_DEFAULT,...d.nums}; S.flags=d.flags||{};
  S.states={...ENUM_DEFAULT,...d.states}; S.items=new Set(d.items||[]); S.clues=new Set(d.clues||[]);
  S.visited=new Set(d.visited||[]); S.deaths=d.deaths||[]; S.chapter=d.chapter||1;
  refreshStats(); start(d.node&&NODES[d.node]?d.node:"prologue"); return true; }

// ---------------------------------------------------------------- UI
function refreshStats(){
  elStats.innerHTML = ["truth","sanity","memory_echo","shenhe_focus"].map(k=>{
    const v=n(k); let c="#b8b5ae";
    if(k==="sanity") c = v>=60?"#8ec7b7":(v>=30?"#dbb85a":"#db4d42");
    else if(k==="truth") c="#adbfd9"; else if(k==="shenhe_focus"&&v>=8) c="#db6659";
    return `<span class="stat" style="color:${c}">${NUM_LABEL[k]} <b>${v}</b></span>`; }).join("");
}
$("#bAuto").onclick=e=>{ autoMode=!autoMode; skipMode=false; e.target.classList.toggle("on",autoMode); $("#bSkip").classList.remove("on"); };
$("#bSkip").onclick=e=>{ skipMode=!skipMode; autoMode=false; e.target.classList.toggle("on",skipMode); $("#bAuto").classList.remove("on"); };
$("#bLog").onclick=()=>{ const h=S.history.slice(-160).map(x=>
  x.who==="__choice__" ? `<div class="row" style="color:#c98b46">▶ ${x.text}</div>`
  : `<div class="row">${x.who?`<b style="color:${CHARS[x.who]?.c}">${CHARS[x.who]?.n}</b>　`:""}${x.text}</div>`).join("");
  sheet("回想",h||"<div class='row'>（还没有内容）</div>"); };
$("#bClue").onclick=()=>{ let h="";
  for(const k in CLUES){ const got=S.clues.has(k), c=CLUES[k];
    h+=`<div class="row ${got?"":"locked"}">${got?`【第${c.ch}章】${c.name}<br><span style="font-size:15px;color:#a8a49c">${c.text}</span>`:"【？】未获得的线索"}</div>`; }
  h+=`<div class="row" style="color:#c9a24a;margin-top:10px">—— 随身物品 ——</div>`;
  if(!S.items.size) h+=`<div class="row locked">（空）</div>`;
  S.items.forEach(i=>{ const it=ITEMS[i]||{}; h+=`<div class="row">◆ ${it.name||i}<br>
    <span style="font-size:15px;color:#a8a49c">${it.desc||""}</span></div>`; });
  sheet(`线索簿（${S.clues.size} / ${Object.keys(CLUES).length}）`,h); };
$("#bStat").onclick=()=>{ let h="";
  const bar=k=>{ const r=NUM_RANGE[k],v=n(k),pct=((v-r[0])/(r[1]-r[0])*100)|0;
    return `<div class="row"><span style="display:inline-block;width:110px">${NUM_LABEL[k]}</span>
      <span style="display:inline-block;width:min(320px,45%);height:12px;background:#1e1e21;vertical-align:middle">
      <span style="display:block;height:100%;width:${pct}%;background:${k==="sanity"?"#59a08c":(k==="truth"?"#6685b3":"#9e4d42")}"></span></span>
      <span style="margin-left:10px">${v}</span></div>`; };
  ["truth","sanity","memory_echo","shenhe_focus"].forEach(k=>h+=bar(k));
  h+=`<div class="row" style="color:#c9a24a">—— 关系 ——</div>`;
  ["trust_zhouxu","trust_liangye","trust_xuqing","trust_oldqin"].forEach(k=>h+=bar(k));
  h+=`<div class="row" style="color:#c9a24a">—— 倾向 ——</div>`;
  ["route_obedience","route_investigate","route_empathy","route_hostility","taboo_count"].forEach(k=>h+=bar(k));
  h+=`<div class="row" style="color:#c9a24a">—— 相关的人 ——</div>`;
  h+=`<div class="row">梁野：${lyDesc()}</div><div class="row">周叙：${zxDesc()}</div>`;
  h+=`<div class="row">许清：${xqDesc()}</div><div class="row">沈禾：${shDesc()}</div>`;
  sheet("状态",h); };
function lyDesc(){ return {anchor_alive:"还在。他说过不会先走。",rescued_half:"拉回来了，但他说话有时是过去时。",
  abandoned:"你放开了手。",missing:"没有回来。"}[S.states.liangye_final_state_ch3]
  || {missing_marked:"被点到过名，一整天都在发抖。",half_assimilated:"回来了。影子却没跟上。",
  fear_alive:"怕得要命，但还在你旁边。",ally_shaken:"肯跟你一起查了。"}[S.states.liangye_state] || "还算正常。"; }
function zxDesc(){ return {confessor_protector:"他坦白了一部分，并且决定站在你这边。",coercer:"他只想尽快结束。"}
  [S.states.zhouxu_final_state_ch3] || {guarding:"他在护着你，也在瞒着你。",hiding:"他躲着你的问题。",
  coercing:"他开始逼你做决定。"}[S.states.zhouxu_state] || "班长。做事很稳。"; }
function xqDesc(){ return {revealed:"已经确认：她五年前就不在名册上了。",destabilized:"被你说破了。",
  observer:"她不再拦你，只是看着。",suspected:"她走路没有声音，也从不穿鞋。"}[S.states.xuqing_state]||"班主任。语文老师。"; }
function shDesc(){ return {seated_core:"她坐在播音椅上。",half_present:"她已经能被看见一部分了。",
  calling:"她在叫名字。"}[S.states.shenhe_state]||"只是一个只剩半个字的名字。"; }
$("#bMenu").onclick=()=>{
  sheet("设置",`
  <div class="row">血腥表现：
    ${[0,1,2].map(i=>`<button class="btn gore" data-v="${i}" style="${settings.gore===i?"color:#ffb9a4;border-color:#a4564a":""}">${["关闭","温和","完整"][i]}</button>`).join(" ")}</div>
  <div class="row">文本速度：
    ${[8,16,24,60].map(i=>`<button class="btn spd" data-v="${i}" style="${settings.speed===i?"color:#ffb9a4;border-color:#a4564a":""}">${{8:"很慢",16:"慢",24:"正常",60:"极快"}[i]}</button>`).join(" ")}</div>
  <div class="row">画面震动：<button class="btn tg" data-k="shake">${settings.shake?"开":"关"}</button>
    　强闪光：<button class="btn tg" data-k="flash">${settings.flash?"开":"关"}</button></div>
  <div class="row" style="color:#8d8a84;font-size:14px">本作含惊吓演出、血腥描写与压抑题材，可随时降低强度。</div>
  <div class="row"><button class="btn" id="__title">返回标题</button></div>`);
  document.querySelectorAll(".gore").forEach(b=>b.onclick=()=>{settings.gore=+b.dataset.v; b.closest(".modal").remove();});
  document.querySelectorAll(".spd").forEach(b=>b.onclick=()=>{settings.speed=+b.dataset.v; b.closest(".modal").remove();});
  document.querySelectorAll(".tg").forEach(b=>b.onclick=()=>{settings[b.dataset.k]=!settings[b.dataset.k]; b.textContent=settings[b.dataset.k]?"开":"关";});
  const t=document.querySelector("#__title"); if(t) t.onclick=()=>location.reload();
};
elClick.onclick=()=>{ if(elChoices.children.length) return; tap(); };
addEventListener("keydown",e=>{ if(["Space","Enter"].includes(e.code)){ e.preventDefault(); tap(); } });
function tap(){
  if(blocked) return;
  if(typing){ typing=false; shown=fullText.length; renderText(); elNext.style.display=""; return; }
  autoTimer=0; advance();
}
function renderText(){
  const span=elText.firstChild;
  if(span) span.textContent = fullText.slice(0,shown);
}

// ---------------------------------------------------------------- 主循环
let last=performance.now();
function loop(now){
  const dt=Math.min(0.05,(now-last)/1000); last=now; T+=dt;
  flicker=Math.max(0,flicker-dt*0.9);
  if(pendingWait>0){ pendingWait-=dt; if(pendingWait<=0){ pendingWait=0; blocked=false; advance(); } }
  else if(typing){
    const cps = skipMode?400:settings.speed;
    shown=Math.min(fullText.length, shown+cps*dt);
    renderText();
    if(shown>=fullText.length){ typing=false; shown=fullText.length; elNext.style.display=""; }
  } else if((autoMode||skipMode)&&!blocked&&!elChoices.children.length){
    autoTimer+=dt; if(autoTimer >= (skipMode?0.05:1.6)){ autoTimer=0; advance(); }
  }
  drawBG(); drawFX(dt);
  requestAnimationFrame(loop);
}

// ---------------------------------------------------------------- 启动
async function boot(){
  resize();
  const meta = await (await fetch("data/meta.json")).json();
  ITEMS=meta.items; CLUES=meta.clues;
  const files = meta.story;
  for(const f of files){ parseStory(await (await fetch("data/"+f)).text()); }
  console.log("节点数",Object.keys(NODES).length);
  refreshStats();
  showTitle();
  requestAnimationFrame(loop);
}
function showTitle(){
  sceneId="oldbuilding_out"; variant="rain";
  const d=document.createElement("div"); d.id="title";
  const cyc = Object.values(JSON.parse(localStorage.getItem("wzx_endings")||"{}")).reduce((a,b)=>a+b,0);
  d.innerHTML=`<h1>晚自习之后</h1><div class="sub">AFTER EVENING STUDY</div>
    ${cyc?`<div style="color:#b8564a;font-size:15px;margin-bottom:8px">这是第 ${109+cyc} 次重排。</div>`:""}
    <button class="btn" id="tNew">开始新游戏</button>
    ${localStorage.getItem("wzx_auto")?`<button class="btn" id="tCont">继续（自动存档）</button>`:""}
    <button class="btn" id="tGal">结局与记录</button>
    <div id="warn">v1.0.0　Godot 4.7.1 工程的浏览器试玩版　含惊吓与血腥描写，建议佩戴耳机</div>`;
  document.getElementById("app").appendChild(d);
  d.querySelector("#tNew").onclick=()=>{ ac().resume?.(); d.remove(); playBGM("bgm_unease"); start("prologue"); };
  const c=d.querySelector("#tCont"); if(c) c.onclick=()=>{ ac().resume?.(); d.remove(); load("auto"); };
  d.querySelector("#tGal").onclick=()=>{ const rec=JSON.parse(localStorage.getItem("wzx_endings")||"{}");
    let h=""; for(const k in ENDING_INFO){ const got=rec[k];
      h+=`<div class="row ${got?"":"locked"}">${got?`${ENDING_INFO[k].tag}　${ENDING_INFO[k].t}　（达成 ${got} 次）`:"？？？"}</div>`; }
    sheet("结局与记录",h); };
  playBGM("bgm_title");
}
boot();
