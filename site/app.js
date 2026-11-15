import { icons } from "./icons.js";

// Every load starts at the top, where the story plays.
history.scrollRestoration = "manual";
scrollTo(0, 0);

const still = matchMedia("(prefers-reduced-motion: reduce)").matches;
const narrow = matchMedia("(max-width: 860px)");
const clamp = (value, low = 0, high = 1) => Math.min(high, Math.max(low, value));
/** How far `value` is between `from` and `to`, 0 to 1. */
const span = (value, from, to) => clamp((value - from) / (to - from));
const ease = (t) => t * t * (3 - 2 * t);
const wait = (ms) => new Promise((done) => setTimeout(done, ms));
const $ = (selector, root = document) => root.querySelector(selector);
const $$ = (selector, root = document) => [...root.querySelectorAll(selector)];
/** Whether the page stands still: on a phone, or when motion is unwelcome. */
const fixed = () => still || narrow.matches;

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

function fortnight() {
  const today = new Date();
  const start = new Date(today);
  start.setDate(today.getDate() - ((today.getDay() + 6) % 7));
  const days = Array.from({ length: 14 }, (_, n) => new Date(start.getFullYear(), start.getMonth(), start.getDate() + n));
  const cell = (day) => `<i class="${day.toDateString() === today.toDateString() ? "today" : day < today ? "past" : ""}">${day.getDate()}</i>`;
  return `<div class="fortnight">${["M", "T", "W", "T", "F", "S", "S"].map((letter) => `<b>${letter}</b>`).join("")}${days.map(cell).join("")}</div>`;
}

const widgets = [
  {
    key: "files", icon: "folder", name: "Files", line: "Your Desktop and pinned folders, opened in place.",
    html: `<h3>${icon("folder")}Files<a>Show all folders</a></h3>
      <ul class="rows"><li><b class="fold"></b>Desktop<i>38</i></li><li><b class="fold"></b>Documents<i>29</i></li>
      <li><b class="fold"></b>Downloads<i>14</i></li><li><b class="fold"></b>Pictures<i>6</i></li></ul>`,
  },
  {
    key: "calendar", icon: "calendar", name: "Calendar", line: "Two weeks at a glance, and what is on today and tomorrow.",
    html: `<h3>${icon("calendar")}Calendar<em>2</em></h3>${fortnight()}<hr class="rule">
      <ul class="rows events"><li><b style="--c:#ff9f0a"></b>Design review<i>10:30</i></li>
      <li><b style="--c:#6c93ff"></b>Lunch at the harbour<i>13:00</i></li></ul>`,
  },
  {
    key: "reminders", icon: "checklist", name: "Reminders", line: "What is still open. Tick one off, or add one with +.",
    html: `<h3>${icon("checklist")}Reminders<em>3</em><a class="add" aria-hidden="true">${icon("plus")}</a></h3>
      <ul class="rows todo"><li><b></b>Renew the passport<i>18 Nov</i></li><li><b></b>Send the invoice<i>20 Nov</i></li>
      <li><b></b>Water the plants</li></ul>`,
  },
  {
    key: "mail", icon: "mail", name: "Mail", line: "The newest messages from every inbox.",
    html: `<h3>${icon("mail")}Mail<em>2</em></h3>
      <ul class="rows mail"><li class="unread">Your tickets for Friday<i>Box office</i><b></b></li>
      <li class="unread">Invoice 0142 is paid<i>Billing</i><b></b></li><li>Notes from Tuesday<i>Studio</i></li>
      <li>The week in type<i>Newsletter</i></li></ul>`,
  },
  {
    key: "playing", icon: "music", name: "Now playing", line: "Whatever is playing in any app: cover, progress and controls.",
    html: `<h3>${icon("music")}Now playing<span class="app" aria-hidden="true">${icon("music")}</span></h3>
      <div class="playing"><span class="cover"></span><div>
      <strong>Low Tide</strong><small>Halden — Shorelines</small>
      <span class="progress"><span class="bar"><i></i></span><span class="times"><i>1:25</i><i>-2:09</i></span></span>
      <span class="controls"><i>${icon("back")}</i><b>${icon("pause")}</b><i>${icon("forward")}</i></span></div></div>`,
  },
  {
    key: "weather", icon: "sunCloud", name: "Weather", line: "Now, and the next four days, where you are.",
    html: `<h3>${icon("sunCloud")}Weather</h3>
      <div class="weather"><div class="now"><div><small>Lisbon</small><strong>18°</strong></div>
      <span>${icon("sunCloud")}<small>Partly cloudy</small><i>H 20° L 14°</i></span></div>
      <ol><li>Today${icon("sunCloud")}<i><b>20°</b> 14°</i></li><li>Sun${icon("sun")}<i><b>23°</b> 15°</i></li>
      <li>Mon${icon("rain")}<i><b>19°</b> 13°</i></li><li>Tue${icon("cloud")}<i><b>18°</b> 12°</i></li></ol></div>`,
  },
  {
    key: "batteries", icon: "battery", name: "Batteries", line: "Every device your Mac tracks, charging shown as macOS shows it.",
    html: `<h3>${icon("battery")}Batteries</h3>
      <div class="rings"><span class="ring charging" style="--level:71">${icon("laptop")}<i class="bolt">${icon("bolt")}</i></span>
      <span class="ring" style="--level:92">${icon("earbuds")}</span><span class="ring" style="--level:64">${icon("earbudsCase")}</span>
      <span class="ring" style="--level:38">${icon("keyboard")}</span></div>`,
  },
  {
    key: "focus", icon: "timer", name: "Focus", line: "Drag the ruler to set the length, then press play. Try it.",
    html: `<h3>${icon("timer")}Focus</h3>
      <div class="focus"><strong data-clock>25:00</strong>
      <span class="keys"><button type="button" class="again" data-again aria-label="Start over" hidden>${icon("rotate")}</button>
      <button type="button" data-focus aria-label="Start the focus timer">${icon("play")}</button></span>
      <div class="ruler" data-ruler><div class="scale" data-scale></div><i class="needle"></i></div></div>`,
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


// ---- Widgets on a curve, turned by scrolling

const round = $("[data-round]");
const wheel = $("[data-wheel]");
const about = $("[data-about]");
wheel.append(...widgets.map(card));
const wheelCards = [...wheel.children];
let front = -1;
/** Degrees of the curve between one card and the next. */
const STEP = 26;

function turnWheel() {
  if (fixed()) return;
  const room = round.offsetHeight - innerHeight;
  const p = clamp((scrollY - round.offsetTop) / room);
  // The first card waits a moment in front, and so does the last.
  const turn = ease(span(p, 0.06, 0.94)) * STEP * (widgets.length - 1);
  wheel.style.setProperty("--turn", turn.toFixed(2));
  wheelCards.forEach((element, index) => {
    const away = Math.abs(index * STEP - turn);
    element.style.setProperty("--near", clamp(1.2 - away / 70).toFixed(3));
  });
  const nearest = Math.round(turn / STEP);
  if (nearest !== front) {
    front = nearest;
    $("strong", about).textContent = widgets[nearest].name;
    $("span", about).textContent = widgets[nearest].line;
    about.classList.remove("swap");
    void about.offsetWidth;
    about.classList.add("swap");
  }
}

drawIcons();

// ---- The hero: the clutter of a desktop gathers into Oree.
// Each moving part's place is worked out from how far the story has
// played, `p`, from 0.36 to END over PLAY_LENGTH:
//   0.36–0.46  the files gather, a small pile for each widget
//   0.44–0.72  each pile opens into its widget, one after another
// The picture, the words and the task box are there from the start.

const scene = $("[data-scene]");
const desk = $("[data-desk]");
const box = $("[data-box]");
const deck = $("[data-cards]");
const heroPicture = $("[data-hero-picture]");

/** Ease out with a little overshoot, for things settling into place. */
const settleInto = (t) => 1 + 2.2 * Math.pow(t - 1, 3) + 1.2 * Math.pow(t - 1, 2);
const mix = (from, to, t) => from + (to - from) * t;

deck.append(...widgets.map(card));
const cards = [...deck.children];

// Each file: its name, its kind, where it lies (% of the scene), and the
// widget it is gathered into.
const clutter = [
  ["Notes.txt", "note", 29, 15, 2], ["Brand", "", 11, 23, 0], ["Harbour.jpg", "pic", 70, 12, 0],
  ["Lunch.ics", "cal", 86, 21, 1], ["Screenshot.png", "pic", 8, 47, 0], ["Flight.ics", "cal", 92, 46, 1],
  ["Invoices", "", 18, 66, 0], ["Tickets.eml", "eml", 79, 70, 3], ["To do.txt", "note", 26, 86, 2],
  ["Low Tide.mp3", "mp3", 61, 86, 4], ["Groceries.txt", "note", 41, 89, 2], ["Invoice.eml", "eml", 90, 83, 3],
];
$("[data-items]").innerHTML = clutter.map(([name, kind], n) => {
  const drift = (seed) => ((((n + 3) * seed) % 11) - 5).toFixed(1);
  return `<div class="sw-item"><div class="icon ${kind}" style="--n:${n};--dur:${(7 + (n % 4) * 1.6).toFixed(1)}s;--delay:${(-n * 0.9).toFixed(1)}s;--dx:${drift(7)}px;--dy:${drift(5)}px;--tilt:${1 + (n % 3)}"><b></b><span>${name}</span></div></div>`;
}).join("");
const strewn = [...$("[data-items]").children].map((element, n) => ({
  element,
  icon: element.firstElementChild,
  x: clutter[n][2] / 100,
  y: clutter[n][3] / 100,
  target: clutter[n][4],
  // Its place in its pile, counted from the bottom.
  layer: clutter.slice(0, n).filter((other) => other[4] === clutter[n][4]).length,
}));

// The widgets just made get their icons.
drawIcons(deck);

let size = { w: 1, h: 1 };
let homes = [];
let piles = [];

/** Where things rest, in the scene's own pixels. */
function measure() {
  for (const element of cards) element.style.transform = "none";
  const sceneBox = scene.getBoundingClientRect();
  size = { w: sceneBox.width, h: sceneBox.height };
  homes = cards.map((element) => {
    const at = element.getBoundingClientRect();
    return { x: at.left - sceneBox.left + at.width / 2, y: at.top - sceneBox.top + at.height / 2 };
  });
  // The files lie strewn over the area the widgets will take.
  const all = deck.getBoundingClientRect();
  for (const file of strewn) {
    file.lies = {
      x: all.left - sceneBox.left + (file.x - 0.05) / 0.9 * all.width,
      y: all.top - sceneBox.top + (file.y - 0.1) / 0.82 * all.height,
    };
  }
  // Each pile forms between its strewn and the widget it will become.
  piles = cards.map((_, index) => {
    const own = strewn.filter((file) => file.target === index);
    if (!own.length) return null;
    const middle = own.reduce((sum, file) => ({ x: sum.x + file.lies.x / own.length, y: sum.y + file.lies.y / own.length }), { x: 0, y: 0 });
    return { x: mix(middle.x, homes[index].x, 0.45), y: mix(middle.y, homes[index].y, 0.45) };
  });
}

let heroPrinted = false;

let queued = false;
function tell() {
  queued = false;
  if (fixed()) {
    // No story: the finished desktop, as the stylesheet lays it out.
    for (const element of [...cards, box]) {
      element.style.transform = "";
      element.style.opacity = "";
    }
    deck.style.opacity = "";
    deck.style.filter = "";
    if (!heroPrinted) {
      heroPrinted = true;
      print(heroPicture);
    }
    turnWheel();
    return;
  }
  const p = heroP;

  // Each widget opens out of its pile, one after another.
  const opened = cards.map((_, index) => span(p, 0.44 + index * 0.022, 0.56 + index * 0.022));
  const gather = ease(span(p, 0.36, 0.46));

  for (const file of strewn) {
    const { lies } = file;
    const pile = piles[file.target];
    const open = opened[file.target];
    // To its pile, stacked a little off true, then into the widget.
    const stacked = { x: pile.x + file.layer * 3, y: pile.y - file.layer * 4 };
    const x = mix(mix(lies.x, stacked.x, gather), homes[file.target].x, ease(open));
    const y = mix(mix(lies.y, stacked.y, gather), homes[file.target].y, ease(open));
    const turn = gather * (file.layer % 2 ? 5 : -4) * (1 - open);
    file.element.style.transform = `translate(${x.toFixed(1)}px, ${y.toFixed(1)}px) translate(-50%, -50%) rotate(${turn.toFixed(2)}deg) scale(${(1 - 0.2 * gather - 0.5 * ease(open)).toFixed(3)})`;
    file.element.style.opacity = (1 - ease(span(open, 0.15, 0.55))).toFixed(3);
  }

  cards.forEach((element, index) => {
    const k = settleInto(opened[index]);
    const home = homes[index];
    const start = piles[index] ?? { x: home.x, y: home.y + 60 };
    const scale = piles[index] ? mix(0.16, 1, k) : mix(0.9, 1, k);
    element.style.transform = `translate(${((start.x - home.x) * (1 - k)).toFixed(1)}px, ${((start.y - home.y) * (1 - k)).toFixed(1)}px) scale(${scale.toFixed(3)})`;
    element.style.opacity = clamp(opened[index] * 2.4).toFixed(3);
  });

  // The picture is there from the start; only the widgets are made.
  deck.style.opacity = "";
  deck.style.filter = "";

  // The picture is heroPrinted into focus as it appears, once.
  if (!heroPrinted) {
    heroPrinted = true;
    resolve(heroPicture);
  }
  turnWheel();
}
function queueTell() {
  if (!queued) {
    queued = true;
    requestAnimationFrame(tell);
  }
}
addEventListener("scroll", turnWheel, { passive: true });

// The story plays once, as soon as the page is ready: the clutter is
// seen for a moment where the widgets will be, then gathers into them.
const PLAY_DELAY = 700;
const PLAY_LENGTH = 3000;
const END = 0.72;
let heroP = 0.36;
function play() {
  let started = null;
  let last = null;
  const frame = (now) => {
    // Time spent in a hidden tab does not count: the story waits.
    if (last !== null && now - last > 200) started += now - last;
    last = now;
    started ??= now;
    const elapsed = Math.max(0, now - started - PLAY_DELAY);
    heroP = 0.36 + (END - 0.36) * clamp(elapsed / PLAY_LENGTH);
    tell();
    if (heroP < END) {
      requestAnimationFrame(frame);
      return;
    }
  };
  requestAnimationFrame(frame);
}
addEventListener("resize", () => {
  measure();
  queueTell();
});
narrow.addEventListener("change", () => {
  measure();
  queueTell();
});

// ---- Pictures: an image drawn small, then printed as dots that thin out
// toward the foot, the way the app prints the picture you choose.

const GROUND = [243, 243, 246];
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
measure();
tell();
const printAll = () => pictures.forEach((canvas) => print(canvas));

/** Print a picture coarse, then finer and finer, as if coming into focus. */
async function resolve(canvas = plate) {
  if (still) return print(canvas);
  const run = (canvas.run = (canvas.run ?? 0) + 1);
  for (const cell of [34, 24, 16, 11, 7, 5, 3]) {
    if (canvas.run !== run) return;
    print(canvas, cell);
    await wait(85);
  }
}

let resizing;
addEventListener("resize", () => {
  clearTimeout(resizing);
  resizing = setTimeout(printAll, 150);
});
printAll();

// The page waits for the photograph and the type, then arrives in turn:
// the words, the screen, the picture printing into focus, the task box,
// the widgets.
const loading = new Image();
const photoReady = new Promise((done) => {
  loading.onload = () => {
    photo = loading;
    done();
  };
  loading.onerror = done;
});
loading.src = "hero.jpg";
Promise.all([photoReady, document.fonts?.ready]).then(() => {
  measure();
  printAll();
  heroPrinted = fixed();
  tell();
  requestAnimationFrame(() => scene.classList.add("on"));
  if (!fixed()) play();
});

for (const button of $$("[data-look]")) {
  button.addEventListener("click", () => {
    look = button.dataset.look;
    for (const other of $$("[data-look]")) other.setAttribute("aria-pressed", String(other.dataset.look === look));
    pictures.filter((canvas) => canvas !== plate).forEach((canvas) => print(canvas));
    resolve(plate);
  });
}

// ---- Focus: a real timer, wherever a Focus widget is showing. Under
// the clock, a ruler of minutes slides beneath a fixed needle; before a
// focus begins it can be dragged to set how long it runs.

const TICK = 0.75; // em between minutes on the ruler
let length = 25 * 60;
let remaining = length;
let ticking;
const fresh = () => !ticking && remaining === length;

// Each ruler gets an hour of ticks, every fifth numbered.
for (const scale of $$("[data-scale]")) {
  scale.innerHTML = Array.from({ length: 61 }, (_, minute) =>
    `<i class="${minute % 5 ? "" : "major"}" style="--m:${minute}">${minute % 5 ? "" : `<b>${minute}</b>`}</i>`).join("");
}

function showClock() {
  const seconds = Math.ceil(remaining);
  const text = `${String(Math.floor(seconds / 60)).padStart(2, "0")}:${String(seconds % 60).padStart(2, "0")}`;
  const minutes = remaining / 60;
  for (const clock of $$("[data-clock]")) clock.textContent = text;
  for (const scale of $$("[data-scale]")) {
    scale.style.transform = `translateX(${(-minutes * TICK).toFixed(3)}em)`;
    [...scale.children].forEach((tick, minute) => tick.classList.toggle("past", minute > minutes));
  }
  for (const ruler of $$("[data-ruler]")) ruler.classList.toggle("free", fresh());
  for (const again of $$("[data-again]")) again.hidden = fresh();
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
        remaining = length;
        showPlay(true);
      }
      showClock();
    }, 250);
  }
  showPlay(running);
  showClock();
}

function showPlay(stopped) {
  for (const button of $$("[data-focus]")) {
    $("svg", button).innerHTML = icons[stopped ? "play" : "pause"];
    button.setAttribute("aria-label", stopped ? "Start the focus timer" : "Pause the focus timer");
  }
}

function startOver() {
  clearInterval(ticking);
  ticking = undefined;
  remaining = length;
  showPlay(true);
  showClock();
}

for (const button of $$("[data-focus]")) button.addEventListener("click", toggleFocus);
for (const button of $$("[data-again]")) button.addEventListener("click", startOver);

// Drawn right, fewer minutes; drawn left, more: a minute at a time, 1 to 60.
for (const ruler of $$("[data-ruler]")) {
  ruler.addEventListener("pointerdown", (down) => {
    if (!fresh()) return;
    down.preventDefault();
    down.stopPropagation();
    const em = parseFloat(getComputedStyle(ruler).fontSize) * TICK;
    const from = length / 60;
    ruler.setPointerCapture(down.pointerId);
    const move = (event) => {
      const minutes = Math.min(60, Math.max(1, Math.round(from - (event.clientX - down.clientX) / em)));
      if (minutes * 60 !== length) {
        length = remaining = minutes * 60;
        showClock();
      }
    };
    const up = () => {
      ruler.removeEventListener("pointermove", move);
      ruler.removeEventListener("pointerup", up);
    };
    ruler.addEventListener("pointermove", move);
    ruler.addEventListener("pointerup", up);
  });
}
showClock();

// Reminders can be ticked off, as they can in the app.
for (const row of $$(".todo li")) row.addEventListener("click", () => row.classList.toggle("done"));

// ---- Files: a file dragged into a folder, the folder opened in place

const files = $("[data-files]");
const iconGrid = $("[data-icons]", files);
const pointer = $("[data-pointer]", files);
const count = $("[data-count]", files);
const path = $("[data-path]", files);
const where = $("[data-where]", files);
const DESKTOP = [
  ["Brand", ""], ["Invoices", ""], ["Trip notes", "doc"], ["Harbour.jpg", "pic"], ["Contract.pdf", "doc"],
  ["Sketches", ""], ["Dunes.jpg", "pic"], ["Budget", "doc"], ["Archive", ""], ["Poster.jpg", "pic"],
  ["Letter", "doc"], ["Site photos", ""], ["Receipts", ""], ["Notes", "doc"],
];
const SITE_PHOTOS = [
  ["Harbour.jpg", "pic"], ["Pier.jpg", "pic"], ["Lighthouse.jpg", "pic"], ["Dock.jpg", "pic"], ["Rocks.jpg", "pic"], ["Survey.pdf", "doc"],
];

function show(items, place) {
  iconGrid.innerHTML = items.map(([name, kind]) => `<div class="icon ${kind}" data-name="${name}"><b></b><span><em>${name}</em></span></div>`).join("");
  where.textContent = place;
  path.classList.toggle("up", place !== "Desktop");
  count.textContent = `${items.length} items`;
}
const named = (name) => $(`[data-name="${name}"]`, iconGrid);

/** The middle of an element, in the files view's own untilted pixels. */
function middle(element) {
  let x = element.offsetWidth / 2;
  let y = element.offsetHeight / 2;
  for (let at = element; at && at !== files; at = at.offsetParent) {
    x += at.offsetLeft;
    y += at.offsetTop;
  }
  return { x, y };
}

let at = { x: 40, y: 60 };
/** Moves the pointer to `to`; `during` hears where it is on each frame. */
function glide(to, length, during) {
  const from = at;
  const began = performance.now();
  return new Promise((done) => {
    const step = (now) => {
      const t = ease(span(now - began, 0, length));
      at = { x: mix(from.x, to.x, t), y: mix(from.y, to.y, t) };
      pointer.style.transform = `translate(${at.x.toFixed(1)}px, ${at.y.toFixed(1)}px)`;
      during?.(at, t);
      if (t < 1) requestAnimationFrame(step); else done();
    };
    requestAnimationFrame(step);
  });
}

async function turnTo(items, place) {
  iconGrid.classList.add("swap");
  await wait(220);
  show(items, place);
  iconGrid.classList.remove("swap");
}

/** While in view: a file goes into a folder, the folder opens, and back. */
async function demonstrate() {
  if (demonstrate.running || still) return;
  demonstrate.running = true;
  while (demonstrate.inView) {
    show(DESKTOP, "Desktop");
    pointer.style.opacity = 1;
    await wait(600);
    const file = named("Harbour.jpg");
    const folder = named("Site photos");
    await glide(middle(file), 800);
    file.classList.add("picked");
    await wait(250);

    // Picked up: a copy follows the pointer, the original stays faint.
    const ghost = file.cloneNode(true);
    ghost.classList.add("ghost");
    files.append(ghost);
    const carry = (point) => (ghost.style.transform = `translate(${(point.x - ghost.offsetWidth / 2).toFixed(1)}px, ${(point.y - ghost.offsetHeight / 2).toFixed(1)}px)`);
    carry(at);
    file.classList.add("lifted");
    await glide(middle(folder), 1300, (point, t) => {
      carry(point);
      folder.classList.toggle("target", t > 0.7);
    });

    // Dropped: in it goes.
    ghost.classList.add("drop");
    folder.classList.remove("target");
    folder.classList.add("took");
    file.classList.add("gone");
    await wait(450);
    // Its place stays empty, as on a desktop: nothing else moves.
    ghost.remove();
    count.textContent = `${DESKTOP.length - 1} items`;
    await wait(800);

    // A double click opens it where it is, not in a window.
    folder.classList.add("picked");
    await wait(130);
    folder.classList.remove("picked");
    await wait(100);
    folder.classList.add("picked");
    await wait(250);
    await turnTo(SITE_PHOTOS, "Site photos");
    named("Harbour.jpg").classList.add("picked");
    await wait(2200);

    // And one click goes back up.
    await glide({ x: path.offsetLeft + 8, y: path.offsetTop + path.offsetHeight / 2 }, 900);
    path.classList.add("press");
    await wait(160);
    path.classList.remove("press");
    await turnTo(DESKTOP.filter(([name]) => name !== "Harbour.jpg"), "Desktop");
    await wait(1800);
    iconGrid.classList.add("swap");
    await wait(220);
    iconGrid.classList.remove("swap");
  }
  pointer.style.opacity = 0;
  demonstrate.running = false;
}
show(DESKTOP, "Desktop");

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
const REQUEST = "Tidy my Downloads into folders by month";
const ANSWER = "Done. 46 files are now in five folders, one for each month. Nothing was deleted.";
// Each playing has its own number; when a newer one starts, or the chat
// leaves the screen, the older one stops at its next pause.
let conversation = 0;
const STOPPED = Symbol("stopped");

const thinking = $("[data-thinking]");
const elapsed = $("[data-elapsed]");
const TOOLS = ["Bash: ls -lt ~/Downloads", "Bash: mkdir ~/Downloads/2026-{07..11}"];

/** As in the app: what the agent runs, folded into one line under way. */
function trace(lines, running) {
  const line = say("trace", `<span class="head">${icon("sparkle")}<em></em>${icon("chevronDown")}</span><span class="list"></span>`);
  const list = $(".list", line);
  for (const text of lines) list.insertAdjacentHTML("beforeend", `<span>${text}</span>`);
  drawIcons(line);
  settle(line, running);
  return line;
}
function settle(line, running) {
  const count = $$(".list span", line).filter((row) => !row.textContent.startsWith("Allowed")).length;
  $("em", line).textContent = running ? "Running tools" : `Ran ${count} tool${count === 1 ? "" : "s"}`;
  line.classList.toggle("running", running);
  line.classList.toggle("open", running);
}

/** The answer, a word at a time, each word fading in. */
async function stream(text, pause) {
  const line = say("", "");
  for (const word of text.split(" ")) {
    line.insertAdjacentHTML("beforeend", `<span class="word">${word} </span>`);
    await pause(45);
  }
}

/** The agent at work: a moving mark, a label and the seconds going by. */
function think(on) {
  thinking.classList.toggle("on", on);
  clearInterval(think.timer);
  if (!on) return;
  const began = performance.now();
  elapsed.textContent = "0.0s";
  think.timer = setInterval(() => (elapsed.textContent = `${((performance.now() - began) / 1000).toFixed(1)}s`), 100);
}

async function converse() {
  const run = ++conversation;
  const pause = async (ms) => {
    await wait(ms);
    if (run !== conversation) throw STOPPED;
  };
  try {
    for (;;) {
      thread.replaceChildren();
      think(false);
      typing.textContent = "";
      await pause(700);
      for (const letter of REQUEST) {
        typing.textContent += letter;
        await pause(26 + Math.random() * 40);
      }
      await pause(350);
      typing.textContent = "";
      say("you", REQUEST);
      think(true);
      await pause(1300);
      const tools = trace([TOOLS[0]], true);
      await pause(1000);
      $(".list", tools).insertAdjacentHTML("beforeend", `<span>${TOOLS[1]}</span>`);
      await pause(900);
      think(false);
      const ask = say("ask", "mv ~/Downloads/*.pdf ~/Downloads/2026-11/ <i>Don’t allow</i><b>Allow</b>");
      await pause(2100);
      ask.remove();
      $(".list", tools).insertAdjacentHTML("beforeend", "<span>Allowed · mv ~/Downloads/*.pdf ~/Downloads/2026-11/</span>");
      think(true);
      await pause(1000);
      think(false);
      settle(tools, false);
      await stream(ANSWER, pause);
      await pause(5200);
    }
  } catch (reason) {
    think(false);
    if (reason !== STOPPED) throw reason;
  }
}

function showConversation() {
  thread.replaceChildren();
  say("you", REQUEST);
  trace([...TOOLS, "Allowed · mv ~/Downloads/*.pdf ~/Downloads/2026-11/"], false);
  say("", ANSWER);
}

// Each screen lies flat as it comes up the page.
const stages = $$(".tilt-stage");
function tiltStages() {
  for (const stage of stages) {
    const top = stage.getBoundingClientRect().top;
    stage.style.setProperty("--tilt", fixed() ? "0" : (1 - ease(span(innerHeight - top, 80, innerHeight * 0.75))).toFixed(4));
  }
}
addEventListener("scroll", () => requestAnimationFrame(tiltStages), { passive: true });
addEventListener("resize", tiltStages);
tiltStages();

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

whenSeen(files, () => {
  demonstrate.inView = true;
  demonstrate();
}, () => (demonstrate.inView = false));

whenSeen(thread.parentElement, () => (still ? showConversation() : converse()), () => conversation++, 0.3);
thread.addEventListener("click", (event) => event.target.closest(".trace .head")?.parentElement.classList.toggle("open"));

let printed = false;
whenSeen(plate, () => {
  if (!printed) {
    printed = true;
    resolve();
  }
});
