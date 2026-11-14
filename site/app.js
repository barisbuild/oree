import { icons } from "./icons.js";

const still = matchMedia("(prefers-reduced-motion: reduce)").matches;
const narrow = matchMedia("(max-width: 860px)");
const clamp = (value, low = 0, high = 1) => Math.min(high, Math.max(low, value));
/** How far `value` is between `from` and `to`, 0 to 1. */
const span = (value, from, to) => clamp((value - from) / (to - from));
const ease = (t) => t * t * (3 - 2 * t);
const wait = (ms) => new Promise((done) => setTimeout(done, ms));
const $ = (selector, root = document) => root.querySelector(selector);
const $$ = (selector, root = document) => [...root.querySelectorAll(selector)];

const icon = (name) => `<svg data-icon="${name}"></svg>`;
function drawIcons(root = document) {
  for (const svg of $$("svg[data-icon]", root)) {
    svg.setAttribute("viewBox", "0 0 24 24");
    svg.setAttribute("fill", "none");
    svg.setAttribute("aria-hidden", "true");
    svg.innerHTML = icons[svg.dataset.icon] ?? "";
  }
}

// ---- The eight widgets, written once and shown twice: small on the Mac's
// screen, and one at a time further down.

const widgets = [
  {
    key: "files", icon: "folder", name: "Files", line: "Your Desktop and pinned folders, opened in place.",
    html: `<h3>${icon("folder")}Files<a>Show all folders</a></h3>
      <ul class="rows"><li><b class="fold"></b>Desktop<i>38</i></li><li><b class="fold"></b>Documents<i>29</i></li>
      <li><b class="fold"></b>Downloads<i>14</i></li><li><b class="fold"></b>Pictures<i>6</i></li></ul>`,
  },
  {
    key: "calendar", icon: "calendar", name: "Calendar", line: "Today and tomorrow, in your calendars' colours.",
    html: `<h3>${icon("calendar")}Calendar<em>3</em></h3>
      <ul class="rows events"><li><b style="--c:#ff9f0a"></b>Design review<i>10:30</i></li>
      <li><b style="--c:#6c93ff"></b>Lunch at the harbour<i>13:00</i></li>
      <li><b style="--c:#30d158"></b>Flight to Lisbon<i>Tomorrow · 07:15</i></li></ul>`,
  },
  {
    key: "reminders", icon: "checklist", name: "Reminders", line: "What is still open. Tick one off right here.",
    html: `<h3>${icon("checklist")}Reminders<em>3</em></h3>
      <ul class="rows todo"><li><b></b>Renew the passport<i>18 Nov</i></li><li><b></b>Send the invoice<i>20 Nov</i></li>
      <li><b></b>Water the plants</li></ul>`,
  },
  {
    key: "mail", icon: "mail", name: "Mail", line: "The newest messages from every inbox.",
    html: `<h3>${icon("mail")}Mail<em>2</em></h3>
      <ul class="rows mail"><li class="unread"><b></b>Your tickets for Friday<i>Box office</i></li>
      <li class="unread"><b></b>Invoice 0142 is paid<i>Billing</i></li><li><b></b>Notes from Tuesday<i>Studio</i></li>
      <li><b></b>The week in type<i>Newsletter</i></li></ul>`,
  },
  {
    key: "playing", icon: "music", name: "Now playing", line: "Whatever is playing in any app, with controls.",
    html: `<h3>${icon("music")}Now playing</h3>
      <div class="playing"><span class="cover"></span><div><strong>Low Tide</strong><small>Halden · Music</small><u></u>
      <span class="controls">${icon("arrowLeft")}<b>${icon("pause")}</b>${icon("arrowRight")}</span></div></div>`,
  },
  {
    key: "weather", icon: "sunCloud", name: "Weather", line: "Now, and the next four days, where you are.",
    html: `<h3>${icon("sunCloud")}Lisbon</h3>
      <div class="weather"><div class="now"><span><strong>18°</strong><small>Partly cloudy <i>H 20° L 14°</i></small></span><b>${icon("sunCloud")}</b></div>
      <ol><li>Today${icon("sunCloud")}<i>20° 14°</i></li><li>Sun${icon("sun")}<i>23° 15°</i></li>
      <li>Mon${icon("rain")}<i>19° 13°</i></li><li>Tue${icon("cloud")}<i>18° 12°</i></li></ol></div>`,
  },
  {
    key: "batteries", icon: "battery", name: "Batteries", line: "This Mac, your earbuds and their case, your keyboard.",
    html: `<h3>${icon("battery")}Batteries</h3>
      <div class="rings"><span class="ring charging" style="--level:71">${icon("laptop")}${icon("bolt")}</span>
      <span class="ring" style="--level:92">${icon("earbuds")}</span><span class="ring" style="--level:64">${icon("earbudsCase")}</span>
      <span class="ring" style="--level:38">${icon("keyboard")}</span></div>`,
  },
  {
    key: "focus", icon: "timer", name: "Focus", line: "Twenty-five minutes, one button. Try it.",
    html: `<h3>${icon("timer")}Focus</h3>
      <div class="focus"><strong data-clock>25:00</strong>
      <button type="button" data-focus aria-label="Start the focus timer">${icon("play")}</button>
      <span class="bar"><i data-bar></i></span></div>`,
  },
];

function card(widget, index) {
  const element = document.createElement("article");
  element.className = "w";
  element.style.setProperty("--i", index);
  element.innerHTML = widget.html;
  $$(".rows li", element).forEach((row, n) => row.style.setProperty("--n", n));
  return element;
}

$("[data-grid]").append(...widgets.map(card));

// ---- The Mac's own furniture: a month of calendar, files left on the desktop

$("[data-month]").innerHTML = Array.from({ length: 35 }, (_, cell) => {
  const day = ((cell + 26) % 30) + 1;
  const event = { 9: "#dfe3ff", 11: "#ffe2c2", 16: "#d6f5df", 18: "#dfe3ff", 24: "#ffe2c2" }[cell];
  return `<i>${day}${event ? `<u style="--c:${event}"></u>` : ""}</i>`;
}).join("");

$("[data-loose]").innerHTML = [
  ["Brand", "", 91, 12], ["Invoice", "doc", 96.4, 12], ["Harbour", "pic", 91, 24], ["Notes", "doc", 96.4, 24],
  ["Trip", "", 91, 36], ["Poster", "pic", 96.4, 36], ["Budget", "doc", 96.4, 48], ["Archive", "", 91, 48],
].map(([name, kind, x, y], index) =>
  `<i class="${kind}" style="--sx:${x}%;--sy:${y}%;--d:${(index * 0.055).toFixed(3)};--spin:${index % 2 ? 14 : -18}">${name}</i>`
).join("");

// ---- Widgets, one at a time

const tabs = $("[data-tabs]");
const showcase = $("[data-showcase]");
tabs.innerHTML = widgets.map((widget) =>
  `<li tabindex="0" role="button">${icon(widget.icon)}<strong>${widget.name}</strong><small>${widget.line}</small></li>`
).join("");
showcase.append(...widgets.map(card));
const tabItems = [...tabs.children];
const showItems = [...showcase.children];
let shown = -1;
let watching = false;

function show(index) {
  if (index === shown) return;
  showItems[shown]?.classList.add("gone");
  showItems[shown]?.classList.remove("on");
  shown = index;
  tabItems.forEach((tab, each) => {
    tab.classList.toggle("on", each === index);
    tab.classList.remove("timed");
  });
  const next = showItems[index];
  next.classList.remove("gone");
  // Let the browser see it out of place first, so it travels in.
  void next.offsetWidth;
  next.classList.add("on");
  if (watching && !still) {
    void tabItems[index].offsetWidth;
    tabItems[index].classList.add("timed");
  }
}

tabItems.forEach((tab, index) => {
  tab.addEventListener("click", () => show(index));
  tab.addEventListener("keydown", (event) => {
    if (event.key === "Enter" || event.key === " ") {
      event.preventDefault();
      show(index);
    }
  });
  // Its time is up when the line under it has run its length.
  tab.addEventListener("animationend", () => show((index + 1) % widgets.length));
});
show(0);

drawIcons();

// ---- The story in the hero, driven by how far the page has scrolled

const hero = $("[data-hero]");
const scene = $("[data-scene-root]");
const asked = $("[data-ask]");
const REQUEST = "Tidy my Downloads into folders by month";
const PLACEHOLDER = asked.textContent;
const fixed = () => still || narrow.matches;

let queued = false;
function tell() {
  queued = false;
  if (fixed()) {
    // No story: the finished desktop, as the stylesheet sets it.
    for (const name of ["--t1", "--t2", "--t3", "--t4", "--t5", "--lead"]) scene.style.removeProperty(name);
    scene.dataset.act = "0";
    return;
  }
  const p = clamp(scrollY / (hero.offsetHeight - innerHeight));
  const typed = span(p, 0.74, 0.97);
  const parts = {
    "--lead": 1 - ease(span(p, 0.035, 0.115)),
    "--t1": ease(span(p, 0.24, 0.41)),
    "--t2": ease(span(p, 0.32, 0.5)),
    "--t3": ease(span(p, 0.38, 0.56)),
    "--t4": ease(span(p, 0.48, 0.7)),
    "--t5": typed,
  };
  for (const [name, value] of Object.entries(parts)) scene.style.setProperty(name, value.toFixed(4));
  scene.dataset.act = p < 0.07 ? "0" : p < 0.28 ? "1" : p < 0.5 ? "2" : p < 0.73 ? "3" : "4";

  // The request is typed a letter at a time as the page moves.
  const letters = Math.round(REQUEST.length * span(typed, 0.04, 0.4));
  asked.textContent = letters ? REQUEST.slice(0, letters) : PLACEHOLDER;
  asked.parentElement.classList.toggle("typed", letters > 0);
}
function queueTell() {
  if (!queued) {
    queued = true;
    requestAnimationFrame(tell);
  }
}
addEventListener("scroll", queueTell, { passive: true });
addEventListener("resize", queueTell);
narrow.addEventListener("change", queueTell);
tell();

// ---- Pictures: an image drawn small, then printed as dots that thin out
// toward the foot, the way the app prints the picture you choose.

const GROUND = [16, 16, 20];
const scenes = {
  dusk: { sky: ["#2b2440", "#c9785a", "#f0c08a"], sun: [0.68, 0.5, "#ffe2b0"], land: ["#6b4a5a", "#3f2f45", "#241d2e"] },
  fjord: { sky: ["#1d2b44", "#5f86a8", "#cfe0e6"], sun: [0.3, 0.42, "#f4fbff"], land: ["#4c6a82", "#2c435a", "#18283a"] },
  dune: { sky: ["#3a2a20", "#d39a5c", "#f3d9a8"], sun: [0.5, 0.55, "#fff0cc"], land: ["#c98d54", "#96603a", "#5b3a26"] },
  mono: { sky: ["#2a2a2c", "#8e8e90", "#d6d6d4"], sun: [0.6, 0.46, "#ffffff"], land: ["#6c6c6e", "#434345", "#262628"] },
};
let look = "photo";
let photo;

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

function drawScene(context, width, height, colours) {
  const sky = context.createLinearGradient(0, 0, 0, height * 0.72);
  colours.sky.forEach((colour, index) => sky.addColorStop(index / (colours.sky.length - 1), colour));
  context.fillStyle = sky;
  context.fillRect(0, 0, width, height);

  const [sunX, sunY, sunColour] = colours.sun;
  const glow = context.createRadialGradient(width * sunX, height * sunY, 0, width * sunX, height * sunY, height * 0.5);
  glow.addColorStop(0, sunColour);
  glow.addColorStop(0.09, sunColour);
  glow.addColorStop(0.11, sunColour + "66");
  glow.addColorStop(1, sunColour + "00");
  context.fillStyle = glow;
  context.fillRect(0, 0, width, height);

  // Three ranges of hills, nearer ones lower, darker and slower to roll.
  colours.land.forEach((colour, layer) => {
    const base = height * (0.56 + layer * 0.1);
    const swell = height * (0.07 - layer * 0.012);
    context.fillStyle = colour;
    context.beginPath();
    context.moveTo(0, height);
    for (let x = 0; x <= width; x++) {
      const t = x / width;
      context.lineTo(x, base + Math.sin(t * (5.2 - layer) + layer * 2.1) * swell + Math.sin(t * (13 - layer * 3) + layer * 4.7) * swell * 0.35);
    }
    context.lineTo(width, height);
    context.fill();
  });
}

/** Fill the canvas with the photograph, cropped to cover it. */
function drawPhoto(context, width, height) {
  const scale = Math.max(width / photo.naturalWidth, height / photo.naturalHeight);
  const w = photo.naturalWidth * scale;
  const h = photo.naturalHeight * scale;
  context.imageSmoothingQuality = "high";
  context.drawImage(photo, (width - w) / 2, (height - h) * 0.3, w, h);
}

function print(canvas, cell = 3) {
  if (!canvas.clientWidth) return;
  const columns = Math.max(8, Math.round(canvas.clientWidth / cell));
  const rows = Math.max(8, Math.round(canvas.clientHeight / cell));
  canvas.width = columns;
  canvas.height = rows;
  const context = canvas.getContext("2d", { willReadFrequently: true });
  if (look === "photo" && photo) drawPhoto(context, columns, rows);
  else drawScene(context, columns, rows, scenes[look === "photo" ? "fjord" : look]);

  // The plate shows the whole picture, so it keeps more before it thins.
  const whole = "resolve" in canvas.dataset;
  const thinFrom = whole ? 0.74 : 0.5;
  const shadeFrom = whole ? 0.58 : 0.34;
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
      if (Math.pow(ease(span(level, thinFrom, 1)), 1.35) >= limit) {
        pixels[at + 3] = 0;
        continue;
      }
      let r = pixels[at] / 255;
      let g = pixels[at + 1] / 255;
      let b = pixels[at + 2] / 255;
      // Only brightness is rounded to a few shades; the colour is left alone.
      const light = Math.max(0.001, r * 0.299 + g * 0.587 + b * 0.114);
      const grain = 1 + (Math.floor(light * 6 + limit) / 6 / light - 1) * 0.55;
      const side = Math.abs(across - 0.5) * 2;
      const shade = Math.min(1, ease(span(level, shadeFrom, 1.08)) * 0.9 + side * side * 0.22 * down);
      r *= grain; g *= grain; b *= grain;
      pixels[at] = 255 * (r + (GROUND[0] / 255 - r) * shade);
      pixels[at + 1] = 255 * (g + (GROUND[1] / 255 - g) * shade);
      pixels[at + 2] = 255 * (b + (GROUND[2] / 255 - b) * shade);
    }
  }
  context.putImageData(image, 0, 0);
}

const pictures = $$("[data-picture]");
const plate = $("[data-resolve]");
const printAll = () => pictures.forEach((canvas) => print(canvas));

/** Print the plate coarse, then finer and finer, as if coming into focus. */
async function resolve() {
  if (still) return print(plate);
  const run = (resolve.run = (resolve.run ?? 0) + 1);
  for (const cell of [34, 24, 16, 11, 7, 5, 3]) {
    if (resolve.run !== run) return;
    print(plate, cell);
    await wait(85);
  }
}

let resizing;
addEventListener("resize", () => {
  clearTimeout(resizing);
  resizing = setTimeout(printAll, 150);
});
printAll();

const loading = new Image();
loading.onload = () => {
  photo = loading;
  printAll();
};
loading.src = "hero.jpg";

for (const button of $$("[data-look]")) {
  button.addEventListener("click", () => {
    look = button.dataset.look;
    for (const other of $$("[data-look]")) other.setAttribute("aria-pressed", String(other === button));
    pictures.filter((canvas) => canvas !== plate).forEach((canvas) => print(canvas));
    resolve();
  });
}

// ---- Focus: a real timer, wherever a Focus widget is showing

const LENGTH = 25 * 60;
let remaining = LENGTH;
let ticking;

function showClock() {
  const seconds = Math.ceil(remaining);
  const text = `${String(Math.floor(seconds / 60)).padStart(2, "0")}:${String(seconds % 60).padStart(2, "0")}`;
  for (const clock of $$("[data-clock]")) clock.textContent = text;
  for (const bar of $$("[data-bar]")) bar.style.width = `${(1 - remaining / LENGTH) * 100}%`;
}

function toggleFocus() {
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
  for (const button of $$("[data-focus]")) {
    $("svg", button).innerHTML = icons[running ? "play" : "pause"];
    button.setAttribute("aria-label", running ? "Start the focus timer" : "Pause the focus timer");
  }
}
for (const button of $$("[data-focus]")) button.addEventListener("click", toggleFocus);

// Reminders can be ticked off, as they can in the app.
for (const row of $$(".todo li")) row.addEventListener("click", () => row.classList.toggle("done"));

// ---- Files: drag a rectangle across the icons, as on any desktop

const files = $("[data-files]");
const iconGrid = $("[data-icons]", files);
const sweep = $("[data-sweep]", files);
const pointer = $("[data-pointer]", files);
const count = $("[data-count]", files);
iconGrid.innerHTML = [
  ["Brand", ""], ["Invoices", ""], ["Trip notes", "doc"], ["Harbour.jpg", "pic"], ["Contract.pdf", "doc"],
  ["Sketches", ""], ["Dunes.jpg", "pic"], ["Budget", "doc"], ["Archive", ""], ["Morning.jpg", "pic"],
  ["Letter", "doc"], ["Site photos", ""], ["Receipts", ""], ["Poster.jpg", "pic"], ["Notes", "doc"],
].map(([name, kind]) => `<div class="icon ${kind}"><b></b><span>${name}</span></div>`).join("");
const fileIcons = [...iconGrid.children];

function pick(area, keep = new Set()) {
  const box = files.getBoundingClientRect();
  let picked = 0;
  for (const item of fileIcons) {
    const at = item.getBoundingClientRect();
    const inside = area
      && at.left - box.left < area.x + area.width && at.right - box.left > area.x
      && at.top - box.top < area.y + area.height && at.bottom - box.top > area.y;
    const on = inside || keep.has(item);
    item.classList.toggle("picked", on);
    picked += on ? 1 : 0;
  }
  count.textContent = picked ? `${picked} selected` : "Drag to select";
}

function showSweep(area) {
  sweep.style.display = area ? "block" : "none";
  if (area) Object.assign(sweep.style, { left: `${area.x}px`, top: `${area.y}px`, width: `${area.width}px`, height: `${area.height}px` });
}

let touched = false;
files.addEventListener("pointerdown", (down) => {
  touched = true;
  pointer.style.opacity = 0;
  const box = files.getBoundingClientRect();
  const start = { x: down.clientX - box.left, y: down.clientY - box.top };
  const keep = new Set(down.metaKey ? fileIcons.filter((item) => item.classList.contains("picked")) : []);
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

/** Until someone tries it, a pointer shows how: over and over, unhurried. */
async function demonstrate() {
  if (demonstrate.running || still) return;
  demonstrate.running = true;
  while (!touched && demonstrate.inView) {
    const box = files.getBoundingClientRect();
    const from = { x: box.width * 0.05, y: 54 };
    const to = { x: box.width * (0.5 + Math.random() * 0.4), y: box.height * (0.5 + Math.random() * 0.3) };
    pointer.style.opacity = 1;
    const began = performance.now();
    await new Promise((done) => {
      const step = (now) => {
        if (touched) return done();
        const t = ease(span(now - began, 0, 1500));
        const area = { x: from.x, y: from.y, width: (to.x - from.x) * t, height: (to.y - from.y) * t };
        pointer.style.transform = `translate(${from.x + area.width}px, ${from.y + area.height}px)`;
        showSweep(area);
        pick(area);
        if (t < 1) requestAnimationFrame(step); else done();
      };
      requestAnimationFrame(step);
    });
    await wait(900);
    if (touched) break;
    showSweep(null);
    await wait(1600);
    if (touched) break;
    pick(null);
    pointer.style.transform = `translate(${from.x}px, ${from.y}px)`;
    await wait(700);
  }
  showSweep(null);
  pointer.style.opacity = 0;
  demonstrate.running = false;
}

// ---- Assistant: one short conversation, played while it is in view

const thread = $("[data-thread]");
const typing = $("[data-typing]");
const say = (kind, html) => {
  const line = document.createElement("p");
  line.className = kind;
  line.innerHTML = html;
  thread.append(line);
  requestAnimationFrame(() => line.classList.add("in"));
  return line;
};
const ANSWER = "Done. 46 files are now in five folders, one for each month. Nothing was deleted.";
let conversing = false;

async function converse() {
  if (conversing) return;
  conversing = true;
  while (conversing) {
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
    await wait(2100);
    ask.className = "tool in";
    ask.textContent = "Allowed · mv ~/Downloads/*.pdf ~/Downloads/2026-11/";
    await wait(1000);
    say("", ANSWER);
    await wait(5200);
  }
}

function showConversation() {
  thread.replaceChildren();
  for (const [kind, text] of [["you", REQUEST], ["tool", "Bash: ls -lt ~/Downloads"], ["tool", "Allowed · mv ~/Downloads/*.pdf ~/Downloads/2026-11/"], ["", ANSWER]]) {
    say(kind, text);
  }
}

// ---- What happens as things scroll into view

function whenSeen(element, enter, leave, amount = 0.35) {
  new IntersectionObserver(([entry]) => (entry.isIntersecting ? enter() : leave?.()), { threshold: amount }).observe(element);
}

for (const element of $$("[data-reveal]")) {
  const watcher = new IntersectionObserver(([entry]) => {
    if (entry.isIntersecting) {
      element.classList.add("in");
      watcher.disconnect();
    }
  }, { threshold: 0.18 });
  watcher.observe(element);
}

whenSeen($(".spotlight"), () => {
  watching = true;
  if (!still) tabItems[shown].classList.add("timed");
}, () => {
  watching = false;
  tabItems[shown].classList.remove("timed");
});

whenSeen(files, () => {
  demonstrate.inView = true;
  demonstrate();
}, () => (demonstrate.inView = false));

whenSeen(thread.parentElement, () => (still ? showConversation() : converse()), () => (conversing = false), 0.3);

let printed = false;
whenSeen(plate, () => {
  if (!printed) {
    printed = true;
    resolve();
  }
});
