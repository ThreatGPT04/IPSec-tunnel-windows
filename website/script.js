(() => {
  const reduce = matchMedia("(prefers-reduced-motion: reduce)").matches;
  const finePointer = matchMedia("(hover: hover) and (pointer: fine)").matches;
  const $ = (s, r = document) => r.querySelector(s);
  const $$ = (s, r = document) => [...r.querySelectorAll(s)];

  /* ---------- loader ---------- */
  document.body.classList.add("loading");
  const loader = $("#loader"), pct = $("#loaderPct");
  let p = 0;
  const tick = () => {
    p = Math.min(100, p + Math.ceil(Math.random() * (reduce ? 100 : 9)));
    pct.textContent = String(p).padStart(3, "0");
    if (p < 100) return setTimeout(tick, 40);
    pct.parentElement.textContent = "CHILD_SA ESTABLISHED";
    setTimeout(() => {
      loader.classList.add("done");
      document.body.classList.remove("loading");
      document.body.classList.add("ready");
      setTimeout(() => loader.remove(), 1100);
    }, 280);
  };
  tick();

  /* ---------- custom cursor ---------- */
  const cursor = $("#cursor"), label = $("#cursorLabel");
  const mouse = { x: innerWidth / 2, y: innerHeight / 2, active: false };
  if (finePointer) {
    let cx = mouse.x, cy = mouse.y;
    addEventListener("mousemove", e => { mouse.x = e.clientX; mouse.y = e.clientY; mouse.active = true; });
    const loop = () => {
      cx += (mouse.x - cx) * 0.22; cy += (mouse.y - cy) * 0.22;
      cursor.style.transform = `translate(${cx}px, ${cy}px)`;
      requestAnimationFrame(loop);
    };
    loop();
    $$("[data-cursor]").forEach(el => {
      el.addEventListener("mouseenter", () => { label.textContent = el.dataset.cursor; cursor.classList.add("big"); });
      el.addEventListener("mouseleave", () => cursor.classList.remove("big"));
    });
  }

  /* ---------- hero: honeycomb field with packets ---------- */
  const canvas = $("#hive"), ctx = canvas.getContext("2d");
  let W, H, dpr, cells = [], packets = [];
  const R = 34; // hex radius
  const build = () => {
    dpr = Math.min(devicePixelRatio || 1, 2);
    W = canvas.clientWidth; H = canvas.clientHeight;
    canvas.width = W * dpr; canvas.height = H * dpr;
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    cells = [];
    const w = Math.sqrt(3) * R, h = 1.5 * R;
    for (let row = -1, y = 0; y < H + R * 2; row++, y = row * h)
      for (let col = -1; col * w < W + w; col++)
        cells.push({ x: col * w + (row & 1 ? w / 2 : 0), y, glow: 0 });
    packets = [];
  };
  const hex = (x, y, r) => {
    ctx.beginPath();
    for (let i = 0; i < 6; i++) {
      const a = Math.PI / 180 * (60 * i - 30);
      ctx.lineTo(x + r * Math.cos(a), y + r * Math.sin(a));
    }
    ctx.closePath();
  };
  const spawn = () => {
    const y = H * (0.3 + Math.random() * 0.5);
    packets.push({ x: -40, y, v: 2 + Math.random() * 4, len: 60 + Math.random() * 140 });
  };
  let heroVisible = true;
  new IntersectionObserver(([e]) => (heroVisible = e.isIntersecting)).observe(canvas);
  const draw = () => {
    if (heroVisible) {
      ctx.clearRect(0, 0, W, H);
      const rect = canvas.getBoundingClientRect();
      const mx = mouse.x - rect.left, my = mouse.y - rect.top;
      for (const c of cells) {
        const d = Math.hypot(c.x - mx, c.y - my);
        const target = mouse.active ? Math.max(0, 1 - d / 220) : 0;
        c.glow += (target - c.glow) * 0.12;
        for (const pk of packets) if (Math.abs(c.y - pk.y) < R && c.x < pk.x && c.x > pk.x - pk.len) c.glow = Math.max(c.glow, 0.55);
        hex(c.x, c.y, R - 3);
        if (c.glow > 0.02) {
          ctx.fillStyle = `rgba(255,184,28,${c.glow * 0.85})`;
          ctx.fill();
        }
        ctx.strokeStyle = `rgba(243,236,220,${0.05 + c.glow * 0.4})`;
        ctx.lineWidth = 1;
        ctx.stroke();
      }
      packets.forEach(pk => (pk.x += pk.v));
      packets = packets.filter(pk => pk.x - pk.len < W + 40);
      if (!reduce && Math.random() < 0.02 && packets.length < 4) spawn();
    }
    if (!reduce || mouse.active) requestAnimationFrame(draw);
  };
  build(); draw();
  addEventListener("resize", () => { build(); if (reduce) draw(); });

  /* ---------- hero status cycle ---------- */
  $$("[data-cycle]").forEach(el => {
    const vals = el.dataset.cycle.split("|"); let i = 0;
    if (!reduce) setInterval(() => { i = (i + 1) % vals.length; el.textContent = vals[i]; }, 1400);
  });

  /* ---------- manifesto: word-by-word light-up ---------- */
  const mt = $("#manifestoText");
  const hot = /DHGroup2|AES128|SHA1|RRAS|IKEv2|custom/i;
  mt.innerHTML = mt.textContent.trim().split(/\s+/)
    .map(w => `<span class="w${hot.test(w) ? " is-hot" : ""}">${w}</span>`).join(" ");
  const words = $$(".w", mt);

  /* ---------- reveals ---------- */
  const io = new IntersectionObserver(es => es.forEach(e => e.isIntersecting && e.target.classList.add("in")), { threshold: 0.3 });
  $$(".reveal").forEach(el => io.observe(el));

  /* ---------- scroll-driven bits ---------- */
  const buildSec = $("#build"), track = $("#buildTrack"), bar = $("#buildBar");
  const cards = $$(".card");
  const isMobile = () => innerWidth <= 760;
  const sizeBuild = () => {
    if (isMobile()) { buildSec.style.height = ""; return; }
    const extra = track.scrollWidth - innerWidth;
    buildSec.style.height = `${innerHeight + Math.max(0, extra)}px`;
  };
  const onScroll = () => {
    // manifesto
    const r = mt.getBoundingClientRect();
    const prog = Math.min(1, Math.max(0, (innerHeight * 0.85 - r.top) / (r.height + innerHeight * 0.35)));
    const n = Math.floor(prog * words.length);
    words.forEach((w, i) => {
      w.classList.toggle("lit", i < n);
      w.classList.toggle("hot", i < n && w.classList.contains("is-hot"));
    });
    // horizontal build
    if (!isMobile()) {
      const br = buildSec.getBoundingClientRect();
      const total = buildSec.offsetHeight - innerHeight;
      const t = Math.min(1, Math.max(0, -br.top / total));
      const extra = track.scrollWidth - innerWidth;
      track.style.transform = `translateX(${-t * Math.max(0, extra)}px)`;
      bar.style.width = `${t * 100}%`;
    }
    // stacking cards shrink as next card covers them
    cards.forEach((c, i) => {
      const next = cards[i + 1];
      if (!next) return;
      const nr = next.getBoundingClientRect(), cr = c.getBoundingClientRect();
      const cover = Math.min(1, Math.max(0, 1 - (nr.top - cr.top) / cr.height));
      c.style.transform = reduce ? "" : `scale(${1 - cover * 0.06})`;
      c.style.filter = `brightness(${1 - cover * 0.35})`;
    });
  };
  sizeBuild(); onScroll();
  addEventListener("scroll", onScroll, { passive: true });
  addEventListener("resize", () => { sizeBuild(); onScroll(); });
  addEventListener("load", () => { sizeBuild(); onScroll(); });

  /* ---------- errors accordion ---------- */
  $$(".err__row").forEach(b => b.addEventListener("click", () => {
    const li = b.parentElement, open = !li.classList.contains("open");
    $$(".err.open").forEach(x => x.classList.remove("open"));
    li.classList.toggle("open", open);
    b.setAttribute("aria-expanded", open);
  }));

  /* ---------- tunnel forge ---------- */
  const form = $("#forgeForm"), out = $("#forgeOut");
  const esc = s => s.replace(/[&<>]/g, c => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;" }[c]));
  const clean = s => s.replace(/["`$]/g, "");
  const chip = n => $(`.chips[data-name="${n}"] .on`, form).textContent;
  const render = () => {
    const f = Object.fromEntries(new FormData(form));
    for (const k in f) f[k] = clean(f[k].trim());
    const s = v => `<span class="c-str">"${esc(v)}"</span>`;
    const k = v => `<span class="c-key">${v}</span>`;
    const d = v => `<span class="c-dim">${v}</span>`;
    out.innerHTML =
`${d("# 0. Kill native IPsec leftovers (they speak IKEv1)")}
Get-NetIPsecRule | Remove-NetIPsecRule -ErrorAction SilentlyContinue
Get-NetIPsecMainModeRule | Remove-NetIPsecMainModeRule -ErrorAction SilentlyContinue

${d("# 1. PSK comes from the environment. Never hardcode it.")}
if (-not $env:VPN_PSK) { throw ${s("Set $env:VPN_PSK first")} }

${d("# 2. Create the IKEv2 S2S interface")}
Add-VpnS2SInterface \`
    ${k("-Name")} ${s(f.name)} \`
    ${k("-Destination")} ${s(f.gw)} \`
    ${k("-Protocol")} Ikev2 \`
    ${k("-AuthenticationMethod")} PSKOnly \`
    ${k("-SharedSecret")} $env:VPN_PSK \`
    ${k("-EncryptionType")} MaximumEncryption \`
    ${k("-IPv4Subnet")} ${s(f.subnet + ":10")} \`
    ${k("-SALifeTime")} 28800 \`
    ${k("-MMSALifeTime")} 86400 \`
    ${k("-SourceIpAddress")} ${s(f.local)} \`
    ${k("-ResponderAuthenticationMethod")} PSKOnly

${d("# 3. Custom policy: the part native IPsec ignores")}
Set-VpnS2SInterface ${k("-Name")} ${s(f.name)} -CustomPolicy \`
    ${k("-EncryptionMethod")} ${chip("p1e")} \`
    ${k("-IntegrityCheckMethod")} ${chip("p1i")} \`
    ${k("-DHGroup")} ${chip("p1d")} \`
    ${k("-CipherTransformConstants")} ${chip("p2e")} \`
    ${k("-AuthenticationTransformConstants")} ${chip("p2i")} \`
    ${k("-PfsGroup")} ${chip("p2p")}

${d("# 4. Explicit traffic selectors (no 0.0.0.0/0)")}
$tsL = New-VpnTrafficSelector -TSPayloadId 0 -Type IPv4 \`
    -IPAddressRange ${s(f.local)}, ${s(f.local)} -PortRange 0, 65535 -ProtocolId 0
$tsR = New-VpnTrafficSelector -TSPayloadId 0 -Type IPv4 \`
    -IPAddressRange ${s(f.rs)}, ${s(f.re)} -PortRange 0, 65535 -ProtocolId 0
Set-VpnS2SInterface ${k("-Name")} ${s(f.name)} \`
    -LocalVpnTrafficSelector $tsL -RemoteVpnTrafficSelector $tsR

${d("# 5. Bring it up")}
Connect-VpnS2SInterface ${k("-Name")} ${s(f.name)}
Get-VpnS2SInterface ${k("-Name")} ${s(f.name)} | Select Name, ConnectionState, LastError`;
    out.classList.remove("flash"); void out.offsetWidth; out.classList.add("flash");
  };
  form.addEventListener("input", render);
  $$(".chips", form).forEach(group => group.addEventListener("click", e => {
    const b = e.target.closest("button"); if (!b) return;
    $$("button", group).forEach(x => x.classList.toggle("on", x === b));
    render();
  }));
  render();

  const copyBtn = $("#copyBtn");
  copyBtn.addEventListener("click", async () => {
    try { await navigator.clipboard.writeText(out.textContent); copyBtn.textContent = "copied ✓"; }
    catch { copyBtn.textContent = "select + ⌘C"; }
    setTimeout(() => (copyBtn.textContent = "copy"), 1600);
  });
})();
