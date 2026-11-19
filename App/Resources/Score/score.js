// score.js — the page half of the score view: Verovio engraves, the app plays the MIDI it writes
// and asks which notes sound at a time; a tapped note asks the app to seek (docs/score.md).
// The one thing a reader would get wrong: a toolkit holds ONE loaded file, so the MIDI is taken before the part is cut.
"use strict";

const BASE_SCALE = 40;
const LAYOUT = {
  breaks: "auto", adjustPageHeight: true, footer: "none", header: "none",
  pageMarginLeft: 30, pageMarginRight: 30, pageMarginTop: 30, pageMarginBottom: 30,
};
const PLAYING = "score-playing";
const host = document.getElementById("pages");
const post = (msg) => window.webkit.messageHandlers.score.postMessage(msg);

let tk = null;
let lit = [];
let litKey = "";
let shownScale = 1;
let resizing = 0;

// The app is told once the module has compiled; it sends the score only then.
verovio.module.onRuntimeInitialized = () => {
  tk = new verovio.toolkit();
  tk.setOptions(LAYOUT);
  post({ type: "ready" });
};

function unlight() {
  for (const el of lit) el.classList.remove(PLAYING);
  lit = [];
  litKey = "";
}

// Lay the loaded file out to the window's width at `scale`, as one column of pages.
function draw(scale) {
  shownScale = scale;
  const vrvScale = Math.round(BASE_SCALE * scale);
  const width = document.documentElement.clientWidth || 400;
  tk.setOptions({ scale: vrvScale, pageWidth: Math.max(100, Math.round((width * 100) / vrvScale)) });
  tk.redoLayout();
  let svg = "";
  for (let p = 1; p <= tk.getPageCount(); p++) svg += tk.renderToSVG(p);
  unlight();
  host.innerHTML = svg;
}

window.k7 = {
  // The whole score's MIDI first, then the part drawn; both share one timing.
  engrave({ whole, shown, transpose, scale }) {
    try {
      tk.setOptions({ transpose: transpose ? String(transpose) : "" });
      if (!tk.loadData(whole)) throw new Error("Verovio could not read this score.");
      const midi = tk.renderToMIDI();
      if (shown !== whole) tk.loadData(shown);
      tk.renderToTimemap();
      draw(scale);
      post({ type: "engraved", midi });
    } catch (e) {
      post({ type: "error", message: String(e.message || e) });
    }
  },

  redraw(scale) { if (tk) draw(scale); },

  clear: unlight,

  // The notes sounding at `ms` lit, and kept in view when they leave it.
  light(ms) {
    if (!tk) return;
    const ids = tk.getElementsAtTime(Math.round(ms)).notes || [];
    if (ids.length === 0) return;
    const key = ids.join(" ");
    if (key === litKey && lit.length) return;
    const next = ids.map((id) => document.getElementById(id)).filter(Boolean);
    const first = next[0] && next[0].getBoundingClientRect();
    unlight();
    litKey = key;
    lit = next;
    for (const el of next) el.classList.add(PLAYING);
    if (first && (first.top < 0 || first.bottom > window.innerHeight))
      window.scrollBy(0, first.top - window.innerHeight / 3);
  },
};

// A new width is a new layout: the systems wrap again once a rotation or a resize settles.
window.addEventListener("resize", () => {
  clearTimeout(resizing);
  resizing = setTimeout(() => { if (tk && host.firstChild) draw(shownScale); }, 150);
});

host.addEventListener("click", (e) => {
  const note = e.target.closest && e.target.closest(".note");
  if (!note || !tk) return;
  post({ type: "seek", ms: tk.getTimeForElement(note.id) });
});
