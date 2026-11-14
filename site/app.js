import { icons } from "./icons.js";

const still = matchMedia("(prefers-reduced-motion: reduce)").matches;
const clamp = (value, low = 0, high = 1) => Math.min(high, Math.max(low, value));

// ---- Icons

for (const svg of document.querySelectorAll("svg[data-icon]")) {
  svg.setAttribute("viewBox", "0 0 24 24");
  svg.setAttribute("fill", "none");
  svg.setAttribute("aria-hidden", "true");
  svg.innerHTML = icons[svg.dataset.icon] ?? "";
}

// ---- Pictures: a scene drawn small, then printed as dots that thin out
// toward the foot, the way the app prints the picture you choose.

/** What a picture sinks into: the dark app, or the light page. */
const GROUNDS = { dark: [19, 19, 20], light: [244, 244, 245] };
const scenes = {
  dusk: { sky: ["#2b2440", "#c9785a", "#f0c08a"], sun: [0.68, 0.5, "#ffe2b0"], land: ["#6b4a5a", "#3f2f45", "#241d2e"] },
  fjord: { sky: ["#1d2b44", "#5f86a8", "#cfe0e6"], sun: [0.3, 0.42, "#f4fbff"], land: ["#4c6a82", "#2c435a", "#18283a"] },
  dune: { sky: ["#3a2a20", "#d39a5c", "#f3d9a8"], sun: [0.5, 0.55, "#fff0cc"], land: ["#c98d54", "#96603a", "#5b3a26"] },
  mono: { sky: ["#2a2a2c", "#8e8e90", "#d6d6d4"], sun: [0.6, 0.46, "#ffffff"], land: ["#6c6c6e", "#434345", "#262628"] },
};
let scene = "dusk";

/** The 8×8 ordered-dither threshold at a dot, in 0..1. */
function threshold(x, y) {
  const xc = (x ^ y) & 7;
  const yc = y & 7;
  let value = 0;
  let bit = 0;
  for (let mask = 2; mask >= 0; mask--) {
    value |= ((yc >> mask) & 1) << bit++;
    value |= ((xc >> mask) & 1) << bit++;
  }
  return (value + 0.5) / 64;
}

const ease = (from, to, value) => {
  const t = clamp((value - from) / (to - from));
  return t * t * (3 - 2 * t);
};

function drawScene(context, width, height, look) {
  const sky = context.createLinearGradient(0, 0, 0, height * 0.72);
  look.sky.forEach((colour, index) => sky.addColorStop(index / (look.sky.length - 1), colour));
  context.fillStyle = sky;
  context.fillRect(0, 0, width, height);

  const [sunX, sunY, sunColour] = look.sun;
  const glow = context.createRadialGradient(width * sunX, height * sunY, 0, width * sunX, height * sunY, height * 0.5);
  glow.addColorStop(0, sunColour);
  glow.addColorStop(0.09, sunColour);
  glow.addColorStop(0.11, sunColour + "66");
  glow.addColorStop(1, sunColour + "00");
  context.fillStyle = glow;
  context.fillRect(0, 0, width, height);

  // Three ranges of hills, nearer ones lower, darker and slower to roll.
  look.land.forEach((colour, layer) => {
    const base = height * (0.56 + layer * 0.1);
    const swell = height * (0.07 - layer * 0.012);
    context.fillStyle = colour;
    context.beginPath();
    context.moveTo(0, height);
    for (let x = 0; x <= width; x++) {
      const t = x / width;
      const y = base
        + Math.sin(t * (5.2 - layer) + layer * 2.1) * swell
        + Math.sin(t * (13 - layer * 3) + layer * 4.7) * swell * 0.35;
      context.lineTo(x, y);
    }
    context.lineTo(width, height);
    context.fill();
  });
}

function print(canvas) {
  const cell = 3;
  const columns = Math.max(8, Math.round(canvas.clientWidth / cell));
  const rows = Math.max(8, Math.round(canvas.clientHeight / cell));
  if (!canvas.clientWidth) return;
  canvas.width = columns;
  canvas.height = rows;
  const context = canvas.getContext("2d", { willReadFrequently: true });
  drawScene(context, columns, rows, scenes[scene]);

  // A tall picture keeps more of itself before it starts to thin.
  const thinFrom = "tall" in canvas.dataset ? 0.66 : 0.46;
  const shadeFrom = "tall" in canvas.dataset ? 0.5 : 0.3;
  const GROUND = GROUNDS[canvas.dataset.ground ?? "dark"];
  const image = context.getImageData(0, 0, columns, rows);
  const pixels = image.data;
  for (let y = 0; y < rows; y++) {
    const down = y / (rows - 1);
    for (let x = 0; x < columns; x++) {
      const across = x / (columns - 1);
      const at = (y * columns + x) * 4;
      const limit = threshold(x, y);
      // The foot is not a straight line: it rolls a little.
      const level = down + 0.03 * Math.sin(across * 8.5) + 0.018 * Math.sin(across * 21 + 1.7);
      if (Math.pow(ease(thinFrom, 1, level), 1.35) >= limit) {
        pixels[at + 3] = 0;
        continue;
      }
      let r = pixels[at] / 255 * 0.86;
      let g = pixels[at + 1] / 255 * 0.86;
      let b = pixels[at + 2] / 255 * 0.86;
      // Only brightness is rounded to a few shades; the colour is left alone.
      const light = Math.max(0.001, r * 0.299 + g * 0.587 + b * 0.114);
      const grain = 1 + (Math.floor(light * 5 + limit) / 5 / light - 1) * 0.5;
      const side = Math.abs(across - 0.5) * 2;
      const shade = Math.min(1, ease(shadeFrom, 1.08, level) * 0.9 + side * side * 0.25 * down);
      r = r * grain; g = g * grain; b = b * grain;
      pixels[at] = 255 * (r + (GROUND[0] / 255 - r) * shade);
      pixels[at + 1] = 255 * (g + (GROUND[1] / 255 - g) * shade);
      pixels[at + 2] = 255 * (b + (GROUND[2] / 255 - b) * shade);
    }
  }
  context.putImageData(image, 0, 0);
}

const pictures = [...document.querySelectorAll("[data-picture]")];
const printAll = () => pictures.forEach(print);
let resizing;
addEventListener("resize", () => {
  clearTimeout(resizing);
  resizing = setTimeout(printAll, 150);
});
printAll();

for (const button of document.querySelectorAll("[data-scene]")) {
  button.addEventListener("click", () => {
    scene = button.dataset.scene;
    for (const other of document.querySelectorAll("[data-scene]")) {
      other.setAttribute("aria-pressed", String(other === button));
    }
    printAll();
  });
}

// ---- Focus: a real timer

const clock = document.querySelector("[data-clock]");
const bar = document.querySelector("[data-bar]");
const focusButton = document.querySelector("[data-focus]");
const LENGTH = 25 * 60;
let remaining = LENGTH;
let ticking;

function showClock() {
  const seconds = Math.ceil(remaining);
  clock.textContent = `${String(Math.floor(seconds / 60)).padStart(2, "0")}:${String(seconds % 60).padStart(2, "0")}`;
  bar.style.width = `${(1 - remaining / LENGTH) * 100}%`;
}

focusButton.addEventListener("click", () => {
  const running = Boolean(ticking);
  clearInterval(ticking);
  ticking = undefined;
  if (!running) {
    const ends = Date.now() + remaining * 1000;
    ticking = setInterval(() => {
      remaining = Math.max(0, (ends - Date.now()) / 1000);
      if (remaining === 0) {
        clearInterval(ticking);
        ticking = undefined;
        remaining = LENGTH;
      }
      showClock();
    }, 250);
  }
  focusButton.querySelector("svg").innerHTML = icons[running ? "play" : "pause"];
  focusButton.setAttribute("aria-label", running ? "Start the focus timer" : "Pause the focus timer");
});

// ---- Files: drag a rectangle across the icons, as on any desktop

const files = document.querySelector("[data-files]");
const iconGrid = files.querySelector("[data-icons]");
const sweep = files.querySelector("[data-sweep]");
const count = files.querySelector("[data-count]");
const names = [
  ["Brand", ""], ["Invoices", ""], ["Trip notes", "doc"], ["Harbour.jpg", "pic"], ["Contract.pdf", "doc"],
  ["Sketches", ""], ["Dunes.jpg", "pic"], ["Budget", "doc"], ["Archive", ""], ["Morning.jpg", "pic"],
  ["Letter", "doc"], ["Site photos", ""], ["Receipts", ""], ["Poster.jpg", "pic"], ["Notes", "doc"],
];
for (const [name, kind] of names) {
  const icon = document.createElement("div");
  icon.className = `icon ${kind}`;
  icon.innerHTML = `<b></b><span>${name}</span>`;
  iconGrid.append(icon);
}
const fileIcons = [...iconGrid.children];

function pick(area, keep = new Set()) {
  const box = files.getBoundingClientRect();
  let picked = 0;
  for (const icon of fileIcons) {
    const at = icon.getBoundingClientRect();
    const inside = area
      && at.left - box.left < area.x + area.width && at.right - box.left > area.x
      && at.top - box.top < area.y + area.height && at.bottom - box.top > area.y;
    const on = inside || keep.has(icon);
    icon.classList.toggle("picked", on);
    picked += on ? 1 : 0;
  }
  count.textContent = picked ? `${picked} selected` : "Drag to select";
}

function showSweep(area) {
  sweep.style.display = area ? "block" : "none";
  if (area) {
    Object.assign(sweep.style, { left: `${area.x}px`, top: `${area.y}px`, width: `${area.width}px`, height: `${area.height}px` });
  }
}

let touched = false;
files.addEventListener("pointerdown", (down) => {
  touched = true;
  const box = files.getBoundingClientRect();
  const start = { x: down.clientX - box.left, y: down.clientY - box.top };
  const keep = new Set(down.metaKey ? fileIcons.filter((icon) => icon.classList.contains("picked")) : []);
  const onIcon = down.target.closest(".icon");
  let moved = false;
  files.setPointerCapture(down.pointerId);

  const move = (event) => {
    const x = clamp(event.clientX - box.left, 0, box.width);
    const y = clamp(event.clientY - box.top, 0, box.height);
    if (Math.hypot(x - start.x, y - start.y) < 4 && !moved) return;
    moved = true;
    const area = { x: Math.min(start.x, x), y: Math.min(start.y, y), width: Math.abs(x - start.x), height: Math.abs(y - start.y) };
    showSweep(area);
    pick(area, keep);
  };
  const up = () => {
    files.removeEventListener("pointermove", move);
    showSweep(null);
    if (!moved) {
      // A click: on an icon it picks that one, on empty space it lets go.
      if (onIcon) {
        if (down.metaKey && keep.has(onIcon)) keep.delete(onIcon); else keep.add(onIcon);
      }
      pick(null, onIcon ? keep : new Set());
    }
  };
  files.addEventListener("pointermove", move);
  files.addEventListener("pointerup", up, { once: true });
  files.addEventListener("pointercancel", up, { once: true });
});

// Until someone tries it, show what a sweep looks like, once.
function demonstrate() {
  if (touched || still) return;
  const box = files.getBoundingClientRect();
  const from = { x: box.width * 0.04, y: 52 };
  const to = { x: box.width * 0.7, y: box.height * 0.6 };
  const began = performance.now();
  const step = (now) => {
    if (touched) return showSweep(null);
    const t = ease(0, 1, clamp((now - began) / 1300));
    const area = { x: from.x, y: from.y, width: (to.x - from.x) * t, height: (to.y - from.y) * t };
    showSweep(area);
    pick(area);
    if (t < 1) requestAnimationFrame(step);
    else setTimeout(() => !touched && showSweep(null), 500);
  };
  requestAnimationFrame(step);
}

// ---- Assistant: one short conversation, played while it is in view

const thread = document.querySelector("[data-thread]");
const typing = document.querySelector("[data-typing]");
const wait = (ms) => new Promise((done) => setTimeout(done, ms));
const say = (kind, html) => {
  const line = document.createElement("p");
  line.className = kind;
  line.innerHTML = html;
  thread.append(line);
  requestAnimationFrame(() => line.classList.add("in"));
  return line;
};

const REQUEST = "Tidy my Downloads into folders by month";
let playing = false;

async function converse() {
  if (playing) return;
  playing = true;
  while (playing) {
    thread.replaceChildren();
    typing.textContent = "";
    await wait(700);
    for (const letter of REQUEST) {
      typing.textContent += letter;
      await wait(26 + Math.random() * 40);
    }
    await wait(350);
    typing.textContent = "";
    say("you", REQUEST);
    await wait(900);
    say("tool", "Bash: ls -lt ~/Downloads");
    await wait(1100);
    const ask = say("ask", "mv ~/Downloads/*.pdf ~/Downloads/2026-11/ <i>Don’t allow</i><b>Allow</b>");
    await wait(1900);
    ask.className = "tool in";
    ask.textContent = "Allowed · mv ~/Downloads/*.pdf ~/Downloads/2026-11/";
    await wait(1000);
    say("", "Done. 46 files are now in five folders, one for each month. Nothing was deleted.");
    await wait(5200);
  }
}

function showConversation() {
  thread.replaceChildren();
  for (const [kind, text] of [
    ["you", REQUEST],
    ["tool", "Bash: ls -lt ~/Downloads"],
    ["tool", "Allowed · mv ~/Downloads/*.pdf ~/Downloads/2026-11/"],
    ["", "Done. 46 files are now in five folders, one for each month. Nothing was deleted."],
  ]) say(kind, text);
}

new IntersectionObserver((entries) => {
  for (const entry of entries) {
    if (entry.target === files && entry.isIntersecting) {
      demonstrate();
    } else if (entry.target === thread.parentElement) {
      if (still) showConversation();
      else if (entry.isIntersecting) converse();
      else playing = false;
    }
  }
}, { threshold: 0.45 }).observe(files);

const chatWatcher = new IntersectionObserver((entries) => {
  for (const entry of entries) {
    if (still) showConversation();
    else if (entry.isIntersecting) converse();
    else playing = false;
  }
}, { threshold: 0.3 });
chatWatcher.observe(thread.parentElement);
