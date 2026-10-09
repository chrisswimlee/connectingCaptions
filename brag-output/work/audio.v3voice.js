// v3 mix: voice clips from timeline.json over a ducked D-major bed.
const fs=require('fs'); const {execSync}=require('child_process');
const SR=44100, DUR=25.5, N=Math.round(SR*DUR);
const TL=JSON.parse(fs.readFileSync('timeline.json'));
const mk=()=>[new Float32Array(N),new Float32Array(N)];
const music=mk(), mwet=mk(), voice=mk(), vwet=mk(), fx=mk(), fxwet=mk();
const BPM=112, BEAT=60/BPM, BAR=BEAT*4;
const mtof=m=>440*Math.pow(2,(m-69)/12);
const CH=[[62,66,69],[59,62,66],[55,59,62],[57,61,64]];
const chordAt=t=>CH[Math.floor(t/BAR)%4];
let seed=7; const rnd=()=>{seed=(seed*16807)%2147483647;return seed/2147483647*2-1;};
function note(bus,wet,t0,len,fn,gain,pan,send){ const a=Math.floor(t0*SR), n=Math.floor(len*SR);
  const gl=gain*Math.cos((pan+1)*Math.PI/4), gr=gain*Math.sin((pan+1)*Math.PI/4);
  for(let k=0;k<n;k++){const i=a+k; if(i<0||i>=N) continue; const v=fn(k/SR); bus[0][i]+=v*gl; bus[1][i]+=v*gr; if(send){wet[0][i]+=v*gl*send; wet[1][i]+=v*gr*send;}} }
const OUT=22.0; // outro: drums stop, last chord rings
const fadeEnd=t=>t<24.0?1:Math.max(0,1-(t-24.0)/1.5);
// pad
for(let b=0;b*BAR<DUR;b++){ const t0=b*BAR, ch=CH[b%4];
  ch.forEach((m,j)=>[-1,1].forEach(det=>{ const f=mtof(m-12)*(1+det*0.003); const L=BAR+0.8;
    note(music,mwet,t0,L,t=>{const e=Math.min(1,t/0.5)*Math.min(1,Math.max(0,(L-t)/0.8)); let v=0; for(let h=1;h<=6;h++) v+=Math.sin(2*Math.PI*f*h*t+j)/(h*h*0.8+0.2); return v*e*fadeEnd(t0+t);},0.035,det*.4,0.5); }));
}
// pluck arpeggio
for(let i=0;i*BEAT/2<DUR-0.5;i++){ const t0=i*BEAT/2, ch=chordAt(t0), m=ch[[0,1,2,1][i%4]]+12, f=mtof(m);
  note(music,mwet,t0,0.6,t=>Math.exp(-t*9)*(Math.sin(2*Math.PI*f*t)+0.3*Math.sin(4*Math.PI*f*t)*Math.exp(-t*20)),0.09*fadeEnd(t0),(i%2?.35:-.35),0.5); }
// kick, sub, hats from the room reveal to the outro
for(let i=0;i*BEAT<DUR;i++){ const t0=i*BEAT; if(t0<3.9||t0>OUT-0.1) continue;
  note(music,mwet,t0,0.35,t=>Math.sin(2*Math.PI*(45*t+75*(1-Math.exp(-t*30))/30))*Math.exp(-t*9),0.2,0,0);
  const f=mtof(chordAt(t0)[0]-24); note(music,mwet,t0,BEAT*0.95,t=>Math.sin(2*Math.PI*f*t)*Math.min(1,t/0.01)*Math.exp(-t*2.5),0.16,0,0);
  let lp=0; note(music,mwet,t0+BEAT/2,0.06,t=>{const x=rnd(),hp=x-lp; lp=x; return hp*Math.exp(-t*70);},0.03,.2,0.2); }
// final D chord ring at the outro
[50,62,66,69,74].forEach((m,j)=>{const f=mtof(m); note(music,mwet,OUT,3.5,t=>Math.sin(2*Math.PI*f*t)*Math.min(1,t/0.02)*Math.exp(-t*1.1),j?0.05:0.12,(j-2)*.15,0.6);});
// bells on prints, logo; wifi toggle click; whoosh on pull-back
function bell(t0,m,g,pan){ const f=mtof(m); note(fx,fxwet,t0,2.0,t=>Math.sin(2*Math.PI*f*t+1.2*Math.exp(-t*4)*Math.sin(2*Math.PI*f*3.5*t))*Math.exp(-t*3)*Math.min(1,t/0.004),g,pan,0.9); }
TL.forEach(s=>{ const ch=chordAt(s.print); bell(s.print,ch[0]+24,0.06,-.2); bell(s.print+0.05,ch[2]+24,0.04,.2); });
bell(22.1,74,0.07,0); bell(22.15,78,0.05,-.3); bell(22.2,81,0.05,.3);
note(fx,fxwet,14.05,0.04,t=>Math.sin(2*Math.PI*1800*t)*Math.exp(-t*120),0.05,.5,0.2);
{ let lp=0; note(fx,fxwet,2.95,1.1,t=>{const k=Math.sin(Math.PI*Math.min(1,t/1.1)); lp+=(0.03+0.12*k)*(rnd()-lp); return lp*k;},0.10,0,0.5); }
// voices
function load(id){ const raw=execSync(`ffmpeg -loglevel error -i voice/${id}.aiff -f f32le -ac 1 -ar ${SR} -`,{maxBuffer:1<<28}); return new Float32Array(raw.buffer,raw.byteOffset,raw.length/4); }
function place(id,t0,gain,pan,send){ const x=load(id); const a=Math.floor(t0*SR); const gl=gain*Math.cos((pan+1)*Math.PI/4), gr=gain*Math.sin((pan+1)*Math.PI/4);
  for(let k=0;k<x.length;k++){const i=a+k; if(i>=N) break; voice[0][i]+=x[k]*gl; voice[1][i]+=x[k]*gr; vwet[0][i]+=x[k]*gl*send; vwet[1][i]+=x[k]*gr*send;} }
TL.forEach(s=>{ place(s.id,s.at,0.9,0,0.18); if(s.speakKo) place(s.speakKo,s.speakAt,0.72,0.3,0.45); });
// duck the music under the voice (envelope follower, ~8 dB)
const duck=new Float32Array(N); { let e=0; const atk=Math.exp(-1/(0.01*SR)), rel=Math.exp(-1/(0.35*SR));
  for(let i=0;i<N;i++){ const x=Math.abs(voice[0][i])+Math.abs(voice[1][i]); e= x>e? atk*e+(1-atk)*x : rel*e+(1-rel)*x; duck[i]=1-0.6*Math.min(1,e/0.08); } }
// reverb
function verb(x,off){ const y=new Float32Array(N); const combs=[1557,1617,1491,1422].map(d=>({b:new Float32Array(d+off),i:0,lp:0}));
  const aps=[556,441].map(d=>({b:new Float32Array(d+off),i:0}));
  for(let n=0;n<N;n++){ let s=0; for(const c of combs){const o=c.b[c.i]; c.lp=o*0.7+c.lp*0.3; c.b[c.i]=x[n]+c.lp*0.84; c.i=(c.i+1)%c.b.length; s+=o;}
    s*=0.25; for(const a of aps){const o=a.b[a.i]; const v=-s+o; a.b[a.i]=s+o*0.5; a.i=(a.i+1)%a.b.length; s=v;} y[n]=s; } return y; }
const wetSum=[0,1].map(c=>{const w=new Float32Array(N); for(let i=0;i<N;i++) w[i]=mwet[c][i]*duck[i]+vwet[c][i]+fxwet[c][i]; return verb(w,c*23);});
const L=new Float32Array(N),R=new Float32Array(N); let peak=0;
for(let i=0;i<N;i++){ for(const [c,o] of [[0,L],[1,R]]){ o[i]=Math.tanh((music[c][i]*duck[i]+voice[c][i]+fx[c][i]+wetSum[c][i]*0.32)*1.1); peak=Math.max(peak,Math.abs(o[i])); } }
const g=0.89/peak, out=Buffer.alloc(44+N*4);
out.write('RIFF',0);out.writeUInt32LE(36+N*4,4);out.write('WAVEfmt ',8);out.writeUInt32LE(16,16);out.writeUInt16LE(1,20);out.writeUInt16LE(2,22);out.writeUInt32LE(SR,24);out.writeUInt32LE(SR*4,28);out.writeUInt16LE(4,32);out.writeUInt16LE(16,34);out.write('data',36);out.writeUInt32LE(N*4,40);
for(let i=0;i<N;i++){ out.writeInt16LE(Math.round(L[i]*g*32767),44+i*4); out.writeInt16LE(Math.round(R[i]*g*32767),46+i*4); }
fs.writeFileSync('music.wav',out); console.log('peak',peak.toFixed(3));
