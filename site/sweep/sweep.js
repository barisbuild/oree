import { icons } from "../icons.js";
import { widgets } from "./widgets.js";

const still = matchMedia("(prefers-reduced-motion: reduce)").matches;
const clamp = (value, low = 0, high = 1) => Math.min(high, Math.max(low, value));
/** How far `value` is between `from` and `to`, 0 to 1. */
const span = (value, from, to) => clamp((value - from) / (to - from));
const ease = (t) => t * t * (3 - 2 * t);
/** Ease out with a little overshoot, for things settling into place. */
const settleInto = (t) => 1 + 2.2 * Math.pow(t - 1, 3) + 1.2 * Math.pow(t - 1, 2);
const mix = (from, to, t) => from + (to - from) * t;
const $ = (selector, root = document) => root.querySelector(selector);

const section = $("[data-sw]");
const scene = $("[data-scene]");
const lead = $("[data-lead]");
const desk = $("[data-desk]");
const box = $("[data-box]");
const rect = $("[data-rect]");
const cursor = $("[data-cursor]");
const close = $("[data-close]");

// ---- The widgets, in the desk, and the clutter that becomes them.
// Each file: its name, its kind, where it lies (% of the scene), and the
// widget (index into `widgets`) it is gathered into.

$("[data-cards]").innerHTML = widgets.map((widget, index) => `<article class="w" style="--i:${index}">${widget.html}</article>`).join("");
const cards = [...$("[data-cards]").children];

const files = [
  ["Notes.txt", "note", 29, 15, 2], ["Brand", "", 11, 23, 0], ["Harbour.jpg", "pic", 70, 12, 0],
  ["Lunch.ics", "cal", 86, 21, 1], ["Screenshot.png", "pic", 8, 47, 0], ["Flight.ics", "cal", 92, 46, 1],
  ["Invoices", "", 18, 66, 0], ["Tickets.eml", "eml", 79, 70, 3], ["To do.txt", "note", 26, 86, 2],
  ["Low Tide.mp3", "mp3", 61, 86, 4], ["Groceries.txt", "note", 41, 89, 2], ["Invoice.eml", "eml", 90, 83, 3],
];
$("[data-items]").innerHTML = files.map(([name, kind], n) => {
  const drift = () => (Math.random() * 10 - 5).toFixed(1);
  return `<div class="sw-item"><div class="icon ${kind}" style="--n:${n};--dur:${(7 + (n % 4) * 1.6).toFixed(1)}s;--delay:${(-n * 0.9).toFixed(1)}s;--dx:${drift()}px;--dy:${drift()}px;--tilt:${(1 + (n % 3)).toFixed(1)}"><b></b><span>${name}</span></div></div>`;
}).join("");
const items = [...$("[data-items]").children].map((element, n) => ({
  element,
  icon: element.firstElementChild,
  x: files[n][2] / 100,
  y: files[n][3] / 100,
  target: files[n][4],
}));

for (const svg of document.querySelectorAll("svg[data-icon]")) {
  svg.setAttribute("viewBox", "0 0 24 24");
  svg.setAttribute("fill", "none");
  svg.setAttribute("aria-hidden", "true");
  svg.innerHTML = icons[svg.dataset.icon] ?? "";
}

// ---- Measuring: where things rest, in the scene's own pixels

let size = { w: 1, h: 1 };
let homes = [];
let gridBox = { x: 0, y: 0, w: 0, h: 0 };

function measure() {
  for (const card of cards) card.style.transform = "none";
  const sceneBox = scene.getBoundingClientRect();
  size = { w: sceneBox.width, h: sceneBox.height };
  homes = cards.map((card) => {
    const at = card.getBoundingClientRect();
    return { x: at.left - sceneBox.left + at.width / 2, y: at.top - sceneBox.top + at.height / 2, w: at.width, h: at.height };
  });
  const all = $("[data-cards]").getBoundingClientRect();
  gridBox = { x: all.left - sceneBox.left, y: all.top - sceneBox.top, w: all.width, h: all.height };
}

// ---- The story

/** Where the pointer is at `p`, and whether it is drawing a rectangle from `from`. */
function pointer(p) {
  const A = { x: 0.05 * size.w, y: 0.07 * size.h };
  const B = { x: 0.96 * size.w, y: 0.93 * size.h };
  const C = { x: gridBox.x - 26, y: gridBox.y - 22 };
  const D = { x: gridBox.x + gridBox.w + 26, y: gridBox.y + gridBox.h + 22 };
  const along = (from, to, t, bow = 0) => ({
    // A hand does not drag in a straight line: a slight bow.
    x: mix(from.x, to.x, t) + Math.sin(t * Math.PI) * bow,
    y: mix(from.y, to.y, t) - Math.sin(t * Math.PI) * bow * 0.6,
  });
  if (p < 0.08) return { at: A };
  if (p < 0.36) return { at: along(A, B, ease(span(p, 0.08, 0.36)), 40), from: A };
  if (p < 0.4) return { at: B, from: A, letGo: span(p, 0.36, 0.4) };
  if (p < 0.58) return { at: along(B, C, ease(span(p, 0.4, 0.58)), -60) };
  if (p < 0.68) return { at: along(C, D, ease(span(p, 0.58, 0.68)), 24), from: C };
  return { at: D, from: C, letGo: span(p, 0.68, 0.72) };
}

const inside = (point, area) => point.x >= area.x && point.x <= area.x + area.w && point.y >= area.y && point.y <= area.y + area.h;

let queued = false;
function tell() {
  queued = false;
  const room = section.offsetHeight - innerHeight;
  const p = still ? 1 : clamp(scrollY / room);

  // The words make way as the first sweep reaches them.
  const gone = ease(span(p, 0.24, 0.38));
  lead.style.opacity = 1 - gone;
  lead.style.transform = `translateY(${-40 * gone}px)`;
  lead.toggleAttribute("inert", gone > 0.5);

  // The pointer, and the rectangle it draws.
  const { at, from, letGo = 0 } = pointer(p);
  cursor.style.transform = `translate(${at.x}px, ${at.y}px)`;
  cursor.style.setProperty("--seen", (1 - ease(span(p, 0.72, 0.78))).toFixed(3));
  scene.classList.toggle("moving", p > 0.08);
  let area = null;
  if (from) {
    area = { x: Math.min(from.x, at.x), y: Math.min(from.y, at.y), w: Math.abs(at.x - from.x), h: Math.abs(at.y - from.y) };
    rect.style.transform = `translate(${area.x}px, ${area.y}px)`;
    rect.style.width = `${area.w}px`;
    rect.style.height = `${area.h}px`;
    rect.style.opacity = (1 - letGo).toFixed(3);
  } else {
    rect.style.opacity = 0;
  }

  // Each widget is folded out of its files, one after another.
  const folded = cards.map((_, index) => settleInto(span(p, 0.4 + index * 0.024, 0.55 + index * 0.024)));
  const sources = cards.map((_, index) => items.filter((item) => item.target === index));

  for (const item of items) {
    const point = { x: item.x * size.w, y: item.y * size.h };
    const k = clamp(folded[item.target]);
    const home = homes[item.target] ?? point;
    const flight = ease(k);
    item.element.style.transform = `translate(${mix(point.x, home.x, flight)}px, ${mix(point.y, home.y, flight)}px) translate(-50%, -50%) scale(${1 - 0.65 * flight})`;
    item.element.style.opacity = (1 - ease(span(k, 0.45, 0.85))).toFixed(3);
    // Picked while the first rectangle covers it, and until it has gone.
    const picked = p >= 0.36 ? p < 0.62 : Boolean(area && p < 0.4 && inside(point, area));
    item.icon.classList.toggle("picked", picked);
  }

  cards.forEach((card, index) => {
    const k = folded[index];
    const home = homes[index];
    if (!home) return;
    const fromHere = sources[index].length
      ? sources[index].reduce((sum, item) => ({ x: sum.x + item.x * size.w / sources[index].length, y: sum.y + item.y * size.h / sources[index].length }), { x: 0, y: 0 })
      : { x: home.x, y: home.y + 60 };
    const dx = (fromHere.x - home.x) * (1 - k);
    const dy = (fromHere.y - home.y) * (1 - k);
    const scale = sources[index].length ? mix(0.18, 1, k) : mix(0.9, 1, k);
    card.style.transform = `translate(${dx}px, ${dy}px) scale(${scale})`;
    card.style.opacity = clamp(k * 1.8).toFixed(3);
    // The second sweep: what its rectangle touches is held, outlined.
    const swept = p >= 0.58 && p < 0.72 && area && inside({ x: home.x, y: home.y }, area);
    card.classList.toggle("swept", Boolean(swept));
  });

  // The task box, the picture, the desktop around it all, the last word.
  const boxIn = settleInto(span(p, 0.52, 0.64));
  const closing = ease(span(p, 0.86, 0.96));
  box.style.opacity = (clamp(boxIn) * (1 - closing * 0.88)).toFixed(3);
  box.style.transform = `translateY(${(1 - boxIn) * 18}px)`;
  $("[data-cards]").style.opacity = (1 - closing * 0.88).toFixed(3);
  $("[data-cards]").style.filter = `blur(${closing * 3}px)`;
  desk.style.setProperty("--photo", ease(span(p, 0.66, 0.8)).toFixed(3));
  desk.style.setProperty("--frame", ease(span(p, 0.72, 0.84)).toFixed(3));
  close.style.opacity = closing.toFixed(3);
  close.style.transform = `translateY(${(1 - closing) * 24}px)`;
  close.style.filter = `blur(${(1 - closing) * 8}px)`;
}

function queueTell() {
  if (!queued) {
    queued = true;
    requestAnimationFrame(tell);
  }
}

addEventListener("scroll", queueTell, { passive: true });
addEventListener("resize", () => {
  measure();
  queueTell();
});

document.fonts.ready.then(() => {
  measure();
  tell();
  requestAnimationFrame(() => scene.classList.add("on"));
});
measure();
tell();
