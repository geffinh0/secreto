// Records the real Atila's Client portal as one continuous screencast, synced to the narration.
// MODE=desktop (1536x864) or MODE=mobile (390x760 @2x, touch indicator).
import fs from 'fs';
import { chromium } from 'playwright';
import { semantics, find, nodes } from './lib.mjs';

const MODE = process.env.MODE || 'desktop';
const MOB = MODE === 'mobile';
const TAG = process.env.TAG || MODE;
const TIMING = JSON.parse(fs.readFileSync(`/tmp/claude-0/hf/build/timing_${TAG}.json`, 'utf8'));
const LEAD = 0.5, TAIL = 0.8;
const OUT = `/tmp/claude-0/demo/frames_${TAG}`;
fs.rmSync(OUT, { recursive: true, force: true }); fs.mkdirSync(OUT, { recursive: true });
const post = (k, body) => fetch('http://127.0.0.1:9101/' + k, { method: 'POST', body: JSON.stringify(body) });

const VW = MOB ? 390 : 1536, VH = MOB ? +(process.env.VH || 720) : 864;
const b = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium', proxy: { server: process.env.HTTPS_PROXY, bypass: 'localhost,127.0.0.1' }, args: ['--ignore-certificate-errors', ...(MOB ? ['--force-device-scale-factor=2'] : [])] });
const ctx = await b.newContext(MOB
  ? { viewport: { width: VW, height: VH }, deviceScaleFactor: 2, isMobile: true, hasTouch: true }
  : { viewport: { width: VW, height: VH } });
const p = await ctx.newPage();

await p.addInitScript((mob) => {
  const install = () => {
    if (document.getElementById('__cur')) return;
    const c = document.createElement('div');
    c.id = '__cur';
    if (mob) {
      c.style.cssText = 'position:fixed;left:0;top:0;width:34px;height:34px;margin:-17px 0 0 -17px;border-radius:50%;background:rgba(255,255,255,.38);border:2px solid rgba(255,255,255,.85);box-shadow:0 2px 8px rgba(0,0,0,.45);z-index:2147483647;pointer-events:none;transform:translate(-200px,-200px)';
    } else {
      c.style.cssText = 'position:fixed;left:0;top:0;width:30px;height:30px;z-index:2147483647;pointer-events:none;transform:translate(-200px,-200px);filter:drop-shadow(0 2px 4px rgba(0,0,0,.55))';
      c.innerHTML = '<svg width="30" height="30" viewBox="0 0 24 24"><path d="M4 2 L4 19 L8.5 14.8 L11.4 21.4 L14.3 20.1 L11.5 13.6 L17.6 13.6 Z" fill="#fff" stroke="#1b140f" stroke-width="1.4" stroke-linejoin="round"/></svg>';
    }
    document.documentElement.appendChild(c);
    const move = e => { c.style.transform = mob ? `translate(${e.clientX}px,${e.clientY}px)` : `translate(${e.clientX - 4}px,${e.clientY - 2}px)`; };
    window.addEventListener('pointermove', move, true);
    window.addEventListener('mousemove', move, true);
    window.addEventListener('pointerdown', e => {
      const r = document.createElement('div');
      r.style.cssText = `position:fixed;left:${e.clientX - 22}px;top:${e.clientY - 22}px;width:44px;height:44px;border-radius:50%;border:3px solid #E07B39;background:rgba(224,123,57,.25);z-index:2147483646;pointer-events:none;transition:transform .45s ease-out,opacity .45s ease-out;transform:scale(.3);opacity:1`;
      document.documentElement.appendChild(r);
      requestAnimationFrame(() => { r.style.transform = 'scale(1.4)'; r.style.opacity = '0'; });
      setTimeout(() => r.remove(), 600);
    }, true);
  };
  document.addEventListener('DOMContentLoaded', install);
  setInterval(install, 500);
}, MOB);

// ── screencast ─────────────────────────────────────────────────────────────
const cdp = await ctx.newCDPSession(p);
const frames = [];
let n = 0;
cdp.on('Page.screencastFrame', async f => {
  const file = `${OUT}/f${String(n++).padStart(6, '0')}.jpg`;
  fs.writeFileSync(file, Buffer.from(f.data, 'base64'));
  frames.push({ t: f.metadata.timestamp, file });
  try { await cdp.send('Page.screencastFrameAck', { sessionId: f.sessionId }); } catch {}
});

// ── helpers ────────────────────────────────────────────────────────────────
let cur = MOB ? [300, 600] : [768, 600];
const ease = t => (t < .5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2);
async function moveTo(x, y, ms = 650) {
  const steps = Math.max(10, Math.round(ms / 18));
  const [sx, sy] = cur;
  for (let i = 1; i <= steps; i++) {
    const e = ease(i / steps);
    await p.mouse.move(sx + (x - sx) * e, sy + (y - sy) * e);
    await p.waitForTimeout(ms / steps * 0.6);
  }
  cur = [x, y];
}
let WHEEL = MOB ? 2 : 1;   // Flutter on a touch device scrolls ~1/4 of the wheel delta
async function smoothScroll(dy, ms = 800) { const steps = 24; for (let i = 0; i < steps; i++) { await p.mouse.wheel(0, dy * WHEEL / steps); await p.waitForTimeout(ms / steps); } await p.waitForTimeout(250); }
// Scroll the page so that the node is comfortably on screen, then return its fresh position.
const TOP = MOB ? 90 : 80, BOT = MOB ? VH - 110 : VH - 40;
async function visible(label, opts = {}) {
  let nd = await find(p, label, opts);
  for (let i = 0; i < 4 && (nd.y < TOP || nd.y > BOT); i++) {
    if (i === 0) await moveTo(VW / 2, VH / 2, 350);
    const want = nd.y - VH * 0.45;
    await smoothScroll(want, i === 0 ? 700 : 350);
    const after = await find(p, label, opts);
    const moved = nd.y - after.y;
    if (Math.abs(moved) > 20 && Math.abs(want) > 20) WHEEL = Math.min(8, Math.max(0.5, WHEEL * want / moved));
    nd = after;
  }
  return nd;
}
async function scrollTo(label, targetY) {
  let nd = await find(p, label);
  for (let i = 0; i < 4; i++) {
    if (Math.abs(nd.y - targetY) < 40) break;
    const want = nd.y - targetY;
    await smoothScroll(want, i === 0 ? 900 : 400);
    const after = await find(p, label);
    const moved = nd.y - after.y;
    console.log('scrollTo', label, Math.round(nd.y), '->', Math.round(after.y), 'wheel', WHEEL.toFixed(2));
    if (Math.abs(moved) < 5) break;
    if (Math.abs(want) > 20) WHEEL = Math.min(8, Math.max(0.5, WHEEL * want / moved));
    nd = after;
  }
  return nd;
}
async function clickAt(x, y, ms) { await moveTo(x, y, ms); await p.waitForTimeout(120); await p.mouse.down(); await p.waitForTimeout(60); await p.mouse.up(); }
async function clickL(label, opts = {}, ms) { const nd = await visible(label, opts); await clickAt(nd.x + (opts.dx || 0), nd.y + (opts.dy || 0), ms); return nd; }
async function typeInto(label, text, opts = {}) { await clickL(label, { tag: opts.tag || 'input', ...opts }); await p.waitForTimeout(220); await p.keyboard.type(text, { delay: opts.delay || 60 }); }
async function hover(label, opts = {}, ms = 600) { try { const nd = await visible(label, opts); await moveTo(nd.x + (opts.dx || 0), nd.y + (opts.dy || 0), ms); return nd; } catch (e) { console.log('skip hover', label); } }
const NAV = MOB
  ? { 'Dashboard': [39, VH - 28], 'Moderação': [117, VH - 28], 'Mensagens': [195, VH - 28], 'Robô': [273, VH - 28], 'Configurações': [351, VH - 28] }
  : { 'Dashboard': [92, 174], 'Moderação': [92, 219], 'Mensagens': [93, 263], 'Robô': [73, 307], 'Configurações': [102, 351] };
const nav = async (k, ms = 700) => { await clickAt(...NAV[k], ms); await p.waitForTimeout(900); };
const SW_DX = MOB ? 0 : -440;   // where to point on a settings switch row (label side on desktop)

const marks = {};
let sceneStart = 0;
async function scene(id, fn) {
  const nowPage = await p.evaluate(() => Date.now()) / 1000;
  sceneStart = Date.now();
  marks[id] = { page: nowPage, dur: TIMING[id].duration + LEAD + TAIL };
  console.log('scene', id, ((Date.now() - t0) / 1000).toFixed(1));
  await fn();
  await until(TIMING[id].duration + LEAD + TAIL);
}
const cap = (id, i) => LEAD + TIMING[id].captions[i].start;
async function until(t) { const d = sceneStart + t * 1000 - Date.now(); if (d > 0) await p.waitForTimeout(d); }

// ── go ─────────────────────────────────────────────────────────────────────
await p.goto('http://localhost:3000/');
await p.waitForTimeout(6000);
await semantics(p);
await p.mouse.move(...cur);
await cdp.send('Page.startScreencast', { format: 'jpeg', quality: 92, maxWidth: VW * (MOB ? 2 : 1), maxHeight: VH * (MOB ? 2 : 1), everyNthFrame: 1 });
await p.waitForTimeout(1500);
const t0 = Date.now();

await scene('conta', async () => {
  await until(cap('conta', 0) + 0.5);
  await clickL('Criar agora', {}, 800);
  await p.waitForTimeout(800);
  await until(cap('conta', 1));
  await typeInto('Nome de exibição', 'Geff Studio', { delay: 45 });
  await typeInto('Usuário', 'geffstudio', { delay: 45 });
  await typeInto('E-mail', 'contato@geffstudio.com', { delay: 28 });
  await until(cap('conta', 2));
  await typeInto('Senha', 'minhasenha123', { delay: 35 });
  await typeInto('Confirmar senha', 'minhasenha123', { delay: 35 });
  await p.waitForTimeout(200);
  await clickL('Criar conta', { role: 'button' }, 500);
});

await scene('dash', async () => {
  await p.waitForTimeout(400);
  await semantics(p);
  await until(cap('dash', 1) + 0.8);
  if (MOB) await hover('Offline', {}, 700); else await moveTo(120, 113, 700);
  await p.waitForTimeout(1200);
  await hover('regras ativas', {}, 700);
  await p.waitForTimeout(800);
  await hover('mensagens na fila', {}, 500);
  await p.waitForTimeout(800);
  await hover('ações no total', {}, 500);
  await until(cap('dash', 2) + 0.9);
  for (const k of ['Moderação', 'Mensagens', 'Robô', 'Configurações']) { await moveTo(NAV[k][0] + (MOB ? 0 : 10), NAV[k][1], 450); await p.waitForTimeout(400); }
});

await scene('silenciar', async () => {
  await until(cap('silenciar', 0) + 1.4);
  await nav('Moderação');
  await until(cap('silenciar', 1) + 0.6);
  await typeInto('Ex: xingamento', 'zap', { delay: 100 });
  await clickL('Adicionar', { role: 'button', exact: true }, 500);
  await until(cap('silenciar', 3) + 0.3);
  await typeInto('Ex: xingamento', 'passa zap', { delay: 80 });
  await clickL('Adicionar', { role: 'button', exact: true }, 500);
});

await scene('regras', async () => { await moveTo(VW / 2, VH * 0.85, 1000); });

await scene('banir', async () => {
  await moveTo(VW / 2, VH / 2, 300);
  await smoothScroll(-1500, 500);
  await until(cap('banir', 0) + 0.5);
  await clickL('Banir (', { role: 'tab' }, 800);
  await until(cap('banir', 1));
  await typeInto('Ex: spam', 'golpe', { delay: 90 });
  await clickL('Adicionar', { role: 'button', exact: true }, 450);
  await p.waitForTimeout(400);
  await typeInto('Ex: spam', 'divulg*', { delay: 90 });
  await clickL('Adicionar', { role: 'button', exact: true }, 450);
  await until(cap('banir', 2) + 0.8);
  await hover('Moderação automática', { role: 'switch', dx: SW_DX }, 800);
  await p.waitForTimeout(1300);
  await hover('Banimento permanente', { role: 'switch', dx: SW_DX }, 600);
  await p.waitForTimeout(1300);
  await hover('Imunidade por diamantes', { role: 'switch', dx: SW_DX }, 600);
});

await scene('mensagens', async () => {
  await until(cap('mensagens', 0) + 1.6);
  await nav('Mensagens');
  await until(cap('mensagens', 1));
  await typeInto('Ex: Divulguem', 'Sigam o perfil e ativem o sininho!', { tag: 'textarea', delay: 16 });
  await clickL('Adicionar à fila', { role: 'button' }, 450);
  await p.waitForTimeout(350);
  await typeInto('Ex: Divulguem', 'Deixa seu like!', { tag: 'textarea', delay: 20 });
  await clickL('Adicionar à fila', { role: 'button' }, 450);
  await until(cap('mensagens', 2) + 0.3);
  await clickL('30s', { role: 'button', exact: true }, 700);
  await p.waitForTimeout(500);
  const lbl = await visible('Envio automático de mensagens');
  const sw = (await nodes(p)).filter(x => x.role === 'switch').sort((a, b) => Math.abs(a.y - lbl.y) - Math.abs(b.y - lbl.y))[0];
  await clickAt(sw.x, sw.y, 600);
  await p.waitForTimeout(600);
  await clickL('Salvar configurações', { role: 'button' }, 600);
});

await scene('robo', async () => {
  await until(cap('robo', 0) + 1.4);
  await nav('Robô');
  await until(cap('robo', 1) + 1.8);
  await hover('E-mail e senha', { role: 'button' }, 600);
  await p.waitForTimeout(600);
  await clickL('Celular', { role: 'button' }, 500);
  await p.waitForTimeout(900);
  await clickL('Colar token', { role: 'button' }, 500);
  await p.waitForTimeout(900);
  await clickL('E-mail e senha', { role: 'button' }, 500);
  await until(cap('robo', 2));
  await typeInto('E-mail da conta do robô', 'robot@x.com', { delay: 45 });
  await typeInto('Senha', 'good', { delay: 80 });
  await clickL('Conectar Robô', { role: 'button' }, 500);
  await until(cap('robo', 3) + 0.3);
  await hover('RoboMod', {}, 700);
});

await scene('moderador', async () => { await hover('Para silenciar e banir', {}, 900); });

await scene('favoritar', async () => {
  await until(cap('favoritar', 1) + 0.3);
  const inp = await visible('ID público da streamer', { tag: 'input' });
  await typeInto('ID público da streamer', '555100', { delay: 110 });
  await p.waitForTimeout(250);
  const fresh = await find(p, 'ID público da streamer', { tag: 'input' });
  const lupa = (await nodes(p)).filter(x => x.role === 'button' && !x.label && Math.abs(x.y - fresh.y) < 14 && x.x > fresh.x).pop();
  await clickAt(lupa.x, lupa.y, 600);
  await until(cap('favoritar', 2) + 0.8);
  await hover('ao vivo agora', {}, 700);
  await p.waitForTimeout(700);
  await until(cap('favoritar', 3) + 0.8);
  await clickL('Favoritar', { role: 'button' }, 800);
  await p.waitForTimeout(1500);
  await hover('Moderando ao vivo', {}, 800);
});

await scene('aovivo', async () => {
  await moveTo(VW / 2, VH / 2, 300);
  await scrollTo('Chat ao vivo', MOB ? 110 : 230);
  await moveTo(VW * 0.7, VH * 0.75, 400);
  await post('chat', { user_id: 21, name: 'Ana', text: 'Boa noite, Geff! Cheguei!' });
  await p.waitForTimeout(1200);
  await post('chat', { user_id: 22, name: 'Bia.rs', text: 'amei a live de hoje' });
  await until(cap('aovivo', 1) - 0.2);
  await post('chat', { user_id: 23, name: 'Carlos_88', text: 'me passa o zap?' });
  await p.waitForTimeout(1500);
  await post('chat', { user_id: 24, name: 'Promo_Fake', text: 'ganhe dinheiro rapido, nao e golpe' });
  await p.waitForTimeout(1300);
  await post('chat', { user_id: 25, name: 'Marina', text: 'que voz linda' });
  await p.waitForTimeout(500);
  await post('chat', { user_id: 26, name: 'Lucas', text: 'divulguem meu canal' });
  await until(cap('aovivo', 2));
  await scrollTo('Ações de moderação', MOB ? 110 : 330);
  await moveTo(VW * 0.4, MOB ? 250 : 520, 500);
});

await scene('painel', async () => {
  await until(cap('painel', 0) + 0.3);
  await nav('Dashboard');
  await hover('ações no total', {}, 600);
  await until(cap('painel', 1));
  await clickL('Estatísticas', { role: 'button' }, 700);
  await p.waitForTimeout(1100);
  await hover('Palavras mais acionadas', {}, 700);
  await p.waitForTimeout(1200);
  await hover('Lives recentes', {}, 700);
  await until(cap('painel', 2) + 0.5);
  await nav('Configurações');
  await hover('Atividade da conta', {}, 700);
});

await scene('final', async () => {
  await until(cap('final', 0) + 1.3);
  await nav('Robô');
  await p.waitForTimeout(300);
  await clickL('Parar', { role: 'button', exact: true }, 700);
  await p.waitForTimeout(900);
  try { const all = (await nodes(p)).filter(x => x.role === 'button' && x.label === 'Parar'); if (all.length) { const d = all[all.length - 1]; await clickAt(d.x, d.y, 500); } } catch {}
});

await cdp.send('Page.stopScreencast');
await p.waitForTimeout(500);
fs.writeFileSync(`/tmp/claude-0/demo/frames_${TAG}.json`, JSON.stringify({ frames, marks }));
console.log('frames', frames.length);
await b.close();
