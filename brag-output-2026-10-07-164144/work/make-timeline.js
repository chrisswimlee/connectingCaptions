// Words arrive at speaking pace; a sentence prints when it is ready.
const fs=require('fs');
const S=[
  {id:'w1',at:0.15, step:.19,en:"A live interpreter shouldn't need the cloud.",ko:'실시간 통역은 클라우드 없이도 되어야 합니다.'},
  {id:'w2',at:3.75, step:.19,en:'And your words should stay yours.',           ko:'그리고 당신의 말은 당신의 것이어야 합니다.'},
  {id:'a', at:13.0, step:.22,en:'Good evening, everyone.',                      ko:'여러분, 안녕하세요.'},
  {id:'b', at:14.3, step:.19,en:'Each sentence appears when it is ready.',      ko:'각 문장은 준비되면 나타납니다.'},
  {id:'c', at:16.3, step:.19,en:'Your words stay on this Mac.',                 ko:'당신의 말은 이 Mac에 남습니다.'},
].map(s=>{const words=s.en.split(' '); const wordTimes=words.map((_,i)=>+(s.at+i*s.step).toFixed(3));
  return {...s,words,wordTimes,print:+(wordTimes.at(-1)+.36).toFixed(3)};});
fs.writeFileSync('timeline.json',JSON.stringify(S,null,1)); fs.writeFileSync('timeline.js','window.TL='+JSON.stringify(S)+';');
S.forEach(s=>console.log(s.id,s.at,'print',s.print));
