// v6 timeline (Why → How → What). No voice: words arrive at speaking pace; a sentence prints when ready.
const fs=require('fs');
const W=0.2, READY=0.35;
const S=[
  {id:'w1', at:0.0,  en:'Everyone in the room should follow along.', ko:'모두가 함께 따라갈 수 있어야 합니다.', print:1.55},
  {id:'w2', at:3.55, en:'And your words should stay yours.',         ko:'그리고 당신의 말은 당신의 것이어야 합니다.', print:4.85},
  {id:'a',  at:11.8, en:"Welcome to tonight's talk.",                ko:'오늘 발표에 오신 것을 환영합니다.'},
  {id:'b',  at:13.2, en:"Each sentence appears when it's ready.",    ko:'각 문장은 준비되면 바로 나타납니다.'},
  {id:'c',  at:15.0, en:'It all runs on this Mac.',                  ko:'모두 이 Mac에서 돌아갑니다.'},
  {id:'e',  at:17.6, en:'Questions are welcome after the talk.',     ko:'발표 후에 질문 받겠습니다.'},
].map(s=>{ const words=s.en.split(' '); const step=s.print?Math.min(W,(s.print-0.3-s.at)/(words.length-1)):W;
  const wordTimes=words.map((_,i)=>+(s.at+i*step).toFixed(3));
  return {...s,words,wordTimes,print:s.print??+(wordTimes.at(-1)+READY).toFixed(3)}; });
fs.writeFileSync('timeline.json',JSON.stringify(S,null,1)); fs.writeFileSync('timeline.js','window.TL='+JSON.stringify(S)+';');
S.forEach(s=>console.log(s.id,s.at,'last word',s.wordTimes.at(-1),'print',s.print));
