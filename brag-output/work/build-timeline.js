// Single source of truth for captions + voice. Writes timeline.json and timeline.js (for the page).
const {execSync}=require('child_process'); const fs=require('fs');
function speech(file){ // non-silent intervals in seconds
  const dur=+execSync(`ffprobe -v error -show_entries format=duration -of csv=p=0 voice/${file}.aiff`).toString();
  const log=execSync(`ffmpeg -hide_banner -i voice/${file}.aiff -af silencedetect=n=-40dB:d=0.12 -f null - 2>&1`).toString();
  const st=[...log.matchAll(/silence_start: ([\d.]+)/g)].map(m=>+m[1]), en=[...log.matchAll(/silence_end: ([\d.]+)/g)].map(m=>+m[1]);
  const segs=[]; let cur=0; st.forEach((s,i)=>{ if(s>cur+0.01) segs.push([cur,s]); cur=en[i]??dur; }); if(cur<dur-0.05) segs.push([cur,dur]);
  return {dur,segs};
}
// voice start times (s) — the edit
const S=[
  {id:'s1',at:0.05, en:'Hi everyone, thanks for coming.', ko:'여러분, 와 주셔서 감사합니다.'},
  {id:'s2',at:4.10, en:'Half of you are hearing this in Korean.', ko:'여러분 중 절반은 한국어로 듣고 계십니다.', speakKo:'s2ko'},
  {id:'s3',at:9.75, en:"Tonight's demo is Connecting Captions.", ko:'오늘 데모는 Connecting Captions입니다.', term:'Connecting Captions'},
  {id:'s5',at:14.30,en:'And none of this needs the internet.', ko:'이 모든 건 인터넷 없이 됩니다.'},
  {id:'s6',at:18.45,en:'See you at the after-party.', ko:'뒤풀이에서 만나요.'},
];
const out=S.map(s=>{
  const {segs}=speech(s.id); const words=s.en.split(' ');
  // split words into phrases at commas when the clip has a matching pause
  let phrases=[[]]; words.forEach(w=>{phrases[phrases.length-1].push(w); if(/,$/.test(w)) phrases.push([]);}); phrases=phrases.filter(p=>p.length);
  const spans=phrases.length===segs.length?segs:[[segs[0][0],segs[segs.length-1][1]]];
  if(spans.length!==phrases.length) phrases=[words];
  const wt=[]; phrases.forEach((ph,i)=>{ const [a,b]=spans[i]; const w=ph.map(x=>x.replace(/[^\w']/g,'').length+1.5); const tot=w.reduce((x,y)=>x+y,0);
    let acc=0; ph.forEach((x,j)=>{ wt.push(+(s.at+a+(b-a)*acc/tot).toFixed(3)); acc+=w[j]; }); });
  const end=+(s.at+segs[segs.length-1][1]).toFixed(3);
  const o={...s,words,wordTimes:wt,speechEnd:end,print:+(end+0.12).toFixed(3)};
  if(s.speakKo){ const k=speech(s.speakKo); o.speakAt=+(o.print+0.2).toFixed(3); o.speakEnd=+(o.speakAt+k.segs[k.segs.length-1][1]).toFixed(3); }
  return o;
});
out.find(o=>o.id==='s1').print=2.15; // hook flip (no voice; English is on screen from frame 0)
fs.writeFileSync('timeline.json',JSON.stringify(out,null,1));
fs.writeFileSync('timeline.js','window.TL='+JSON.stringify(out)+';');
out.forEach(o=>console.log(o.id,'voice',o.at,'speechEnd',o.speechEnd,'print',o.print,o.speakAt?`ko ${o.speakAt}-${o.speakEnd}`:''));
