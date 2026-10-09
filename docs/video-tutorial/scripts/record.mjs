// Records the real Atila's Client portal (Flutter build + FastAPI backend + mock SuperLive)
// as one continuous screencast, with scene marks synced to the narration timing.
import fs from 'fs';
import { launch, semantics, find, nodes } from './lib.mjs';

const TIMING = JSON.parse(fs.readFileSync('/tmp/claude-0/hf/build/timing.json', 'utf8'));
const LEAD = 0.5, TAIL = 0.8;
const OUT = '/tmp/claude-0/demo/frames';
fs.rmSync(OUT, { recursive: true, force: true }); fs.mkdirSync(OUT, { recursive: true });
const post = (k, body) => fetch('http://127.0.0.1:9101/' + k, { method: 'POST', body: JSON.stringify(body) });

const { b, ctx, p } = await launch(1536, 864);
await p.addInitScript(() => {
  const install = () => {
    if (document.getElementById('__cur')) return;
    const c = document.createElement('div');
    c.id = '__cur';
    c.style.cssText = 'position:fixed;left:0;top:0;width:30px;height:30px;z-index:2147483647;pointer-events:none;transform:translate(-200px,-200px);filter:drop-shadow(0 2px 4px rgba(0,0,0,.55))';
    c.innerHTML = '<svg width="30" height="30" viewBox="0 0 24 24"><path d="M4 2 L4 19 L8.5 14.8 L11.4 21.4 L14.3 20.1 L11.5 13.6 L17.6 13.6 Z" fill="#fff" stroke="#1b140f" stroke-width="1.4" stroke-linejoin="round"/></svg>';
    document.documentElement.appendChild(c);
    const move = e => { c.style.transform = `translate(${e.clientX - 4}px,${e.clientY - 2}px)`; };
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
});

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
let cur = [768, 600];
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
async function clickAt(x, y, ms) { await moveTo(x, y, ms); await p.waitForTimeout(120); await p.mouse.down(); await p.waitForTimeout(60); await p.mouse.up(); }
async function clickL(label, opts = {}, ms) { const nd = await find(p, label, opts); await clickAt(nd.x + (opts.dx || 0), nd.y + (opts.dy || 0), ms); return nd; }
async function typeInto(label, text, opts = {}) { await clickL(label, { tag: opts.tag || 'input', ...opts }); await p.waitForTimeout(250); await p.keyboard.type(text, { delay: opts.delay || 75 }); }
async function hover(label, opts = {}, ms = 600) { const nd = await find(p, label, opts); await moveTo(nd.x + (opts.dx || 0), nd.y + (opts.dy || 0), ms); return nd; }
async function smoothScroll(dy, ms = 900) { const steps = 30; for (let i = 0; i < steps; i++) { await p.mouse.wheel(0, dy / steps); await p.waitForTimeout(ms / steps); } }
const NAV = { 'Dashboard': [92, 174], 'Moderação': [92, 219], 'Mensagens': [93, 263], 'Robô': [73, 307], 'Configurações': [102, 351] };

const marks = {};
let sceneStart = 0;
async function scene(id, fn) {
  const nowCdp = await p.evaluate(() => Date.now()) / 1000;
  sceneStart = Date.now();
  marks[id] = { wall: sceneStart / 1000, page: nowCdp, dur: TIMING[id].duration + LEAD + TAIL };
  console.log('scene', id, new Date().toISOString());
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
await cdp.send('Page.startScreencast', { format: 'jpeg', quality: 92, maxWidth: 1536, maxHeight: 864, everyNthFrame: 1 });
await p.waitForTimeout(1500);

await scene('conta', async () => {
  await until(cap('conta', 0) + 0.6);
  await clickL('Criar agora', {}, 900);
  await p.waitForTimeout(900);
  await until(cap('conta', 1));
  await typeInto('Nome de exibição', 'Geff Studio', { delay: 60 });
  await typeInto('Usuário', 'geffstudio', { delay: 60 });
  await typeInto('E-mail', 'contato@geffstudio.com', { delay: 40 });
  await until(cap('conta', 2));
  await typeInto('Senha', 'minhasenha123', { delay: 50 });
  await typeInto('Confirmar senha', 'minhasenha123', { delay: 50 });
  await p.waitForTimeout(300);
  await clickL('Criar conta', { role: 'button' });
});

await scene('dash', async () => {
  await p.waitForTimeout(400);
  await semantics(p);
  await until(cap('dash', 1));
  await moveTo(120, 113, 800);          // status do robô
  await p.waitForTimeout(1300);
  await hover('regras ativas', {}, 800);
  await p.waitForTimeout(900);
  await hover('mensagens na fila', {}, 500);
  await p.waitForTimeout(900);
  await hover('ações no total', {}, 500);
  await until(cap('dash', 2) + 0.9);
  for (const k of ['Moderação', 'Mensagens', 'Robô', 'Configurações']) { await moveTo(NAV[k][0] + 10, NAV[k][1], 500); await p.waitForTimeout(450); }
});

await scene('silenciar', async () => {
  await until(cap('silenciar', 0) + 1.3);
  await clickAt(...NAV['Moderação'], 700);
  await p.waitForTimeout(900);
  await until(cap('silenciar', 1) + 0.8);
  await typeInto('Ex: xingamento', 'zap', { delay: 110 });
  await clickL('Adicionar', { role: 'button', exact: true });
  await until(cap('silenciar', 3) + 0.4);
  await typeInto('Ex: xingamento', 'passa zap', { delay: 90 });
  await clickL('Adicionar', { role: 'button', exact: true });
});

await scene('regras', async () => {
  await moveTo(900, 760, 1200);
});

await scene('banir', async () => {
  await until(cap('banir', 0) + 0.5);
  await clickL('Banir (', { role: 'tab' }, 800);
  await until(cap('banir', 1));
  await typeInto('Ex: spam', 'golpe', { delay: 100 });
  await clickL('Adicionar', { role: 'button', exact: true });
  await p.waitForTimeout(500);
  await typeInto('Ex: spam', 'divulg*', { delay: 100 });
  await clickL('Adicionar', { role: 'button', exact: true });
  await until(cap('banir', 2) + 0.8);
  await hover('Moderação automática', { role: 'switch', dx: -440 }, 800);
  await p.waitForTimeout(1500);
  await hover('Banimento permanente', { role: 'switch', dx: -440 }, 600);
  await p.waitForTimeout(1500);
  await hover('Imunidade por diamantes', { role: 'switch', dx: -420 }, 600);
});

await scene('mensagens', async () => {
  await until(cap('mensagens', 0) + 1.8);
  await clickAt(...NAV['Mensagens'], 700);
  await p.waitForTimeout(900);
  await until(cap('mensagens', 1));
  await typeInto('Ex: Divulguem', 'Sigam o perfil e ativem as notificações!', { tag: 'textarea', delay: 35 });
  await clickL('Adicionar à fila', { role: 'button' });
  await p.waitForTimeout(500);
  await typeInto('Ex: Divulguem', 'Obrigada por assistir! Deixe seu like.', { tag: 'textarea', delay: 35 });
  await clickL('Adicionar à fila', { role: 'button' });
  await until(cap('mensagens', 2) + 0.6);
  await clickL('30s', { role: 'button', exact: true }, 800);
  await p.waitForTimeout(700);
  const sw = (await nodes(p)).find(x => x.role === 'switch');
  await clickAt(sw.x, sw.y, 700);
  await p.waitForTimeout(700);
  await clickL('Salvar configurações', { role: 'button' }, 700);
});

await scene('robo', async () => {
  await until(cap('robo', 0) + 1.2);
  await clickAt(...NAV['Robô'], 700);
  await p.waitForTimeout(800);
  await until(cap('robo', 1) + 2.0);
  await hover('E-mail e senha', { role: 'button' }, 600);
  await p.waitForTimeout(700);
  await clickL('Celular', { role: 'button' }, 500);
  await p.waitForTimeout(900);
  await clickL('Colar token', { role: 'button' }, 500);
  await p.waitForTimeout(900);
  await clickL('E-mail e senha', { role: 'button' }, 500);
  await until(cap('robo', 2));
  await typeInto('E-mail da conta do robô', 'robot@x.com', { delay: 55 });
  await typeInto('Senha', 'good', { delay: 90 });
  await clickL('Conectar Robô', { role: 'button' });
  await until(cap('robo', 3) + 0.4);
  await moveTo(330, 140, 700);
});

await scene('moderador', async () => {
  await hover('Para silenciar e banir', {}, 900);
});

await scene('favoritar', async () => {
  await until(cap('favoritar', 1) + 0.4);
  await typeInto('ID público da streamer', '555100', { delay: 120 });
  await p.waitForTimeout(250);
  await clickAt(1454, 431, 600);
  await until(cap('favoritar', 2) + 1.0);
  await hover('ao vivo agora', {}, 700);
  await p.waitForTimeout(800);
  await hover('ID da Live', { tag: 'input' }, 700);
  await until(cap('favoritar', 3) + 0.9);
  await clickL('Favoritar', { role: 'button' }, 800);
  await p.waitForTimeout(1200);
  await moveTo(560, 420, 800);
});

await scene('aovivo', async () => {
  await moveTo(900, 600, 500);
  await smoothScroll(520, 1000);
  await p.waitForTimeout(300);
  await post('chat', { user_id: 21, name: 'Ana', text: 'Boa noite, Geff! Cheguei!' });
  await p.waitForTimeout(1300);
  await post('chat', { user_id: 22, name: 'Bia.rs', text: 'amei a live de hoje' });
  await until(cap('aovivo', 1));
  await post('chat', { user_id: 23, name: 'Carlos_88', text: 'me passa o zap?' });
  await p.waitForTimeout(2200);
  await post('chat', { user_id: 24, name: 'Promo_Fake', text: 'ganhe dinheiro rapido, nao e golpe' });
  await p.waitForTimeout(1300);
  await post('chat', { user_id: 25, name: 'Marina', text: 'que voz linda' });
  await until(cap('aovivo', 2) - 0.6);
  await post('chat', { user_id: 26, name: 'Lucas', text: 'divulguem meu canal' });
  await p.waitForTimeout(500);
  await moveTo(900, 700, 400);
  await smoothScroll(420, 900);
});

await scene('painel', async () => {
  await until(cap('painel', 0) + 0.4);
  await clickAt(...NAV['Dashboard'], 800);
  await p.waitForTimeout(1200);
  await hover('ações no total', {}, 700);
  await until(cap('painel', 1));
  await clickL('Estatísticas', { role: 'button' }, 800);
  await p.waitForTimeout(1200);
  await hover('Palavras mais acionadas', {}, 800);
  await p.waitForTimeout(1400);
  await hover('Lives recentes', {}, 700);
  await until(cap('painel', 2) + 0.6);
  await clickAt(...NAV['Configurações'], 800);
  await p.waitForTimeout(1300);
  await hover('Atividade da conta', {}, 700);
});

await scene('final', async () => {
  await until(cap('final', 0) + 1.4);
  await clickAt(...NAV['Robô'], 700);
  await p.waitForTimeout(1200);
  const stop = await find(p, 'Parar', { role: 'button', exact: true });
  if (stop.y > 830) { await moveTo(900, 500, 400); await smoothScroll(stop.y - 450, 700); }
  await clickL('Parar', { role: 'button', exact: true }, 700);
  await p.waitForTimeout(900);
  try { const all = (await nodes(p)).filter(x => x.role === 'button' && x.label === 'Parar'); if (all.length) { const d = all[all.length - 1]; await clickAt(d.x, d.y, 600); } } catch {}
});

await cdp.send('Page.stopScreencast');
await p.waitForTimeout(500);
fs.writeFileSync('/tmp/claude-0/demo/frames.json', JSON.stringify({ frames, marks }, null, 0));
console.log('frames', frames.length);
await b.close();
