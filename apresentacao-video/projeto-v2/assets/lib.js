/* helpers globais (seguros para seek): HF.rise, HF.pop, HF.draw */
window.HF = {
  E: { leaf:"power3.out", stem:"sine.inOut", press:"power2.inOut", rest:"back.out(1.2)", cut:"power2.in" },
  rise(tl, sel, t, o={}) { return tl.fromTo(sel, { opacity:0, y:o.y??60 }, { opacity:1, y:0, duration:o.d??0.7, ease:o.e??"power3.out" }, t); },
  pop(tl, sel, t, o={}) { return tl.fromTo(sel, { opacity:0, scale:o.s??0.86, y:o.y??24, transformOrigin:o.origin??"50% 50%" }, { opacity:1, scale:1, y:0, duration:o.d??0.6, ease:"back.out(1.2)" }, t); },
  fade(tl, sel, t, to=0, d=0.35) { return tl.to(sel, { opacity:to, duration:d, ease:"power1.inOut" }, t); },
  draw(tl, sel, t, d=1.6, e="sine.inOut") { return tl.fromTo(sel, { strokeDasharray:2000, strokeDashoffset:2000 }, { strokeDashoffset:0, duration:d, ease:e }, t); }
};
