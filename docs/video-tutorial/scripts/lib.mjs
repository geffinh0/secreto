import { chromium } from 'playwright';
export async function launch(w=1536,h=864){
  const b = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium', proxy: { server: process.env.HTTPS_PROXY, bypass: 'localhost,127.0.0.1' }, args:['--ignore-certificate-errors'] });
  const ctx = await b.newContext({ viewport: { width: w, height: h } });
  const p = await ctx.newPage();
  return { b, ctx, p };
}
export async function semantics(p){
  await p.evaluate(() => document.querySelector('flt-semantics-placeholder')?.click());
  await p.waitForTimeout(600);
}
export async function nodes(p){
  return p.evaluate(() => [...document.querySelectorAll('flt-semantics, input, textarea')].map(e => { const r=e.getBoundingClientRect(); return {tag:e.tagName.toLowerCase(), role:e.getAttribute('role')||'', label:(e.getAttribute('aria-label')||e.placeholder||e.textContent||'').trim().replace(/\s+/g,' ').slice(0,60), x:r.x+r.width/2, y:r.y+r.height/2, w:r.width, h:r.height, checked:e.getAttribute('aria-checked')}}).filter(n=>n.w>0 && n.w<1500));
}
export async function dump(p){
  for (const n of await nodes(p)) console.log(`${n.tag}|${n.role}|${n.label}|${Math.round(n.x)},${Math.round(n.y)} ${Math.round(n.w)}x${Math.round(n.h)}${n.checked?' chk='+n.checked:''}`);
}
export async function find(p, label, {role, exact=false, nth=0, tag}={}){
  for (let i=0;i<16;i++){
    const ns = (await nodes(p)).filter(n => (exact? n.label===label : n.label.includes(label)) && (!role||n.role===role) && (!tag||n.tag===tag));
    if (ns.length>nth) return ns[nth];
    await p.waitForTimeout(250);
  }
  throw new Error('not found: '+label);
}
export async function fill(p, label, text, delay=30){ const n = await find(p,label,{tag:'input'}); await p.mouse.click(n.x,n.y); await p.waitForTimeout(200); await p.keyboard.type(text,{delay}); }
export async function click(p, label, opts){ const n = await find(p,label,opts); await p.mouse.click(n.x,n.y); return n; }
export async function login(p, u, pw){ await p.goto('http://localhost:3000/'); await p.waitForTimeout(5000); await semantics(p); await fill(p,'Usuário',u); await fill(p,'Senha',pw); await click(p,'Entrar',{role:'button'}); await p.waitForTimeout(2500); await semantics(p); }
export const NAV = { 'Dashboard':[92,174], 'Moderação':[92,219], 'Mensagens':[93,263], 'Robô':[73,307], 'Configurações':[102,351] };
