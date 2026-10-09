const fs=require('fs');
const SR=44100, DUR=21, N=SR*DUR;
const dry=[new Float32Array(N),new Float32Array(N)], wet=[new Float32Array(N),new Float32Array(N)], pad=[new Float32Array(N),new Float32Array(N)];
const BPM=112, BEAT=60/BPM, BAR=BEAT*4;
const mtof=m=>440*Math.pow(2,(m-69)/12);
// D, Bm, G, A
const CH=[[62,66,69],[59,62,66],[55,59,62],[57,61,64]];
const chordAt=t=>CH[Math.floor(t/BAR)%4];
let seed=7; const rnd=()=>{seed=(seed*16807)%2147483647;return seed/2147483647*2-1;};
function add(buf,i,l,r){ if(i>=0&&i<N){buf[0][i]+=l;buf[1][i]+=r;} }
function note(t0,len,fn,gain,pan,send){ const a=Math.floor(t0*SR), n=Math.floor(len*SR);
  const gl=gain*Math.cos((pan+1)*Math.PI/4), gr=gain*Math.sin((pan+1)*Math.PI/4);
  for(let k=0;k<n;k++){const v=fn(k/SR); add(dry,a+k,v*gl,v*gr); if(send) add(wet,a+k,v*gl*send,v*gr*send);} }
const fadeEnd=t=>t<19.6?1:Math.max(0,1-(t-19.6)/1.4);
// pad: soft additive saw, per bar
for(let b=0;b*BAR<DUR;b++){ const t0=b*BAR, ch=CH[b%4];
  ch.forEach((m,j)=>[-1,1].forEach(det=>{ const f=mtof(m-12)*(1+det*0.003);
    const a=Math.floor(t0*SR), n=Math.floor((BAR+0.8)*SR);
    for(let k=0;k<n;k++){const t=k/SR; const e=Math.min(1,t/0.5)*Math.min(1,Math.max(0,(BAR+0.8-t)/0.8));
      let v=0; for(let h=1;h<=6;h++) v+=Math.sin(2*Math.PI*f*h*t+j)/ (h*h*0.8+0.2);
      const g=0.035*e*fadeEnd(t0+t); const idx=a+k; if(idx<N){pad[0][idx]+=v*g*(det<0?1:.6); pad[1][idx]+=v*g*(det<0?.6:1);} }
  }));
}
// pluck arpeggio 8ths
for(let i=0;i*BEAT/2<DUR-0.5;i++){ const t0=i*BEAT/2, ch=chordAt(t0); const m=ch[[0,1,2,1][i%4]]+12+(i%8>=4?12:0)*0;
  const g=(t0<3.6?0.11:0.09)*fadeEnd(t0); const f=mtof(m);
  note(t0,0.6,t=>Math.exp(-t*9)*(Math.sin(2*Math.PI*f*t)+0.3*Math.sin(4*Math.PI*f*t)*Math.exp(-t*20)),g,(i%2?.35:-.35),0.5); }
// drums + bass from reveal
const kicks=[];
for(let i=0;i*BEAT<DUR;i++){ const t0=i*BEAT; if(t0<3.55||t0>19.4) continue; kicks.push(t0);
  note(t0,0.35,t=>Math.sin(2*Math.PI*(45*t+75*(1-Math.exp(-t*30))/30))*Math.exp(-t*9),0.2,0,0);
  const r=chordAt(t0)[0]-24; const f=mtof(r);
  note(t0,BEAT*0.95,t=>Math.sin(2*Math.PI*f*t)*Math.min(1,t/0.01)*Math.exp(-t*2.5),0.16,0,0);
  let lp=0; note(t0+BEAT/2,0.06,t=>{const x=rnd(); const hp=x-lp; lp=x; return hp*Math.exp(-t*70);},0.03,.2,0.2);
}
// bells (FM), in key, soft
function bell(t0,m,g,pan){ const f=mtof(m); note(t0,2.0,t=>Math.sin(2*Math.PI*f*t+1.2*Math.exp(-t*4)*Math.sin(2*Math.PI*f*3.5*t))*Math.exp(-t*3)*Math.min(1,t/0.004),g,pan,0.9); }
function chordBell(t0,g){ const ch=chordAt(t0); bell(t0,ch[0]+24,g,-.2); bell(t0+0.05,ch[2]+24,g*.7,.2); }
[1.35,7.65,9.05,10.35,12.45].forEach(t=>chordBell(t,0.09));
bell(3.68,74,0.08,0); bell(3.73,81,0.05,.3); bell(18.33,74,0.08,0); bell(18.38,78,0.05,-.3); bell(18.43,81,0.05,.3);
[[16.0,74],[16.2,78],[16.4,81]].forEach(([t,m],i)=>bell(t,m+12,0.035,[-.4,0,.4][i]));
// word ticks: one soft pitched tap per word, in key
[[0,74],[.17,76],[.34,78],[.52,81],[.72,78],[.92,81]].forEach(([t0,m])=>{ const f=mtof(m+12);
  note(t0,0.12,t=>Math.sin(2*Math.PI*f*t)*Math.exp(-t*45)*Math.min(1,t/0.002),0.035,(rnd()*.3),0.3); });
// pull-back whoosh
{ let lp=0; note(1.2,1.0,t=>{const k=Math.sin(Math.PI*Math.min(1,t/1.0)); lp+=(0.03+0.12*k)*(rnd()-lp); return lp*k;},0.09,0,0.5); }
// swell into reveal
{ let lp=0; note(2.7,1.0,t=>{const k=t/1.0; lp+= (0.02+0.2*k)*(rnd()-lp); return lp*k*k*(t<0.95?1:(1-t)/0.05);},0.12,0,0.6); }
// sidechain pad by kicks, then mix
for(let i=0;i<N;i++){ const t=i/SR; let d=1; for(const k of kicks){ if(t>=k&&t<k+0.3){d=1-0.45*Math.exp(-(t-k)*10);break;} }
  for(let c=0;c<2;c++){ dry[c][i]+=pad[c][i]*d; wet[c][i]+=pad[c][i]*d*0.5; } }
// reverb: 4 combs + 2 allpass per channel
function verb(x,off){ const y=new Float32Array(N); const combs=[1557,1617,1491,1422].map(d=>({b:new Float32Array(d+off),i:0,lp:0}));
  const aps=[556,441].map(d=>({b:new Float32Array(d+off),i:0}));
  for(let n=0;n<N;n++){ let s=0; for(const c of combs){const o=c.b[c.i]; c.lp=o*0.7+c.lp*0.3; c.b[c.i]=x[n]+c.lp*0.86; c.i=(c.i+1)%c.b.length; s+=o;}
    s*=0.25; for(const a of aps){const o=a.b[a.i]; const v=-s+o; a.b[a.i]=s+o*0.5; a.i=(a.i+1)%a.b.length; s=v;} y[n]=s; } return y; }
const rv=[verb(wet[0],0),verb(wet[1],23)];
const out=Buffer.alloc(44+N*4); let peak=0; const L=new Float32Array(N),R=new Float32Array(N);
for(let i=0;i<N;i++){ L[i]=Math.tanh((dry[0][i]+rv[0][i]*0.35)*1.2); R[i]=Math.tanh((dry[1][i]+rv[1][i]*0.35)*1.2); peak=Math.max(peak,Math.abs(L[i]),Math.abs(R[i])); }
const g=0.89/peak;
out.write('RIFF',0);out.writeUInt32LE(36+N*4,4);out.write('WAVEfmt ',8);out.writeUInt32LE(16,16);out.writeUInt16LE(1,20);out.writeUInt16LE(2,22);out.writeUInt32LE(SR,24);out.writeUInt32LE(SR*4,28);out.writeUInt16LE(4,32);out.writeUInt16LE(16,34);out.write('data',36);out.writeUInt32LE(N*4,40);
for(let i=0;i<N;i++){ const fe=i<SR*0.02?i/(SR*0.02):1; out.writeInt16LE(Math.round(L[i]*g*fe*32767),44+i*4); out.writeInt16LE(Math.round(R[i]*g*fe*32767),46+i*4); }
fs.writeFileSync('music.wav',out); console.log('peak',peak.toFixed(3));
