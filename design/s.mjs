import { chromium } from 'playwright';
const b = await chromium.launch({executablePath:'/opt/pw-browsers/chromium-1194/chrome-linux/chrome'});
const p = await b.newPage({viewport:{width:720,height:420}, deviceScaleFactor:2});
await p.goto('file:///tmp/astra/design/cmp.html');
await p.waitForTimeout(500);
await p.screenshot({path:'cmp5.png'});
await b.close();
