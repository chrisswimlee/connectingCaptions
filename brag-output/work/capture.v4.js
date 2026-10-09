const { chromium } = require('playwright-core');
const fs=require('fs');
(async()=>{
  const exe=require('child_process').execSync('ls -d ~/Library/Caches/ms-playwright/chromium_headless_shell-1243/*/chrome-headless-shell',{shell:'/bin/zsh'}).toString().trim();
  const b=await chromium.launch({executablePath:exe});
  const pg=await b.newPage({viewport:{width:1920,height:1080}});
  await pg.goto('file://'+__dirname+'/brag.html'); await pg.evaluate(()=>window.ready);
  const args=process.argv.slice(2);
  if(args[0]==='stills'){ fs.mkdirSync('stills',{recursive:true});
    for(const t of args.slice(1)){ await pg.evaluate(t=>render(+t+1.5),t); await pg.screenshot({path:`stills/t${t}.png`}); } }
  else { fs.mkdirSync('frames',{recursive:true}); const N=24*30;
    for(let f=0;f<N;f++){ await pg.evaluate(t=>render(t),1.5+f/30); await pg.screenshot({path:`frames/f${String(f).padStart(4,'0')}.jpg`,type:'jpeg',quality:95}); } }
  await b.close();
})();
