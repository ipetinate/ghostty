// Drives the vendored phantom-mdx viewer from a web page instead of from the
// app's WKWebView. The bundle is copied byte for byte; only this file and the
// page around it are the site's own — the app's own page allows `file:` images
// and this one is served over https, which is the whole of the difference.
//
// Reads ?doc= (the document to render) and ?base= (the folder its media sit
// in), then reports its height so the embedding page can size the frame.

const params = new URLSearchParams(location.search);
const doc = params.get("doc");
/* Absolute, always: the viewer resolves a document's own paths with
   `new URL(path, baseURL)`, and that throws on a relative base — which is how
   an icon theme's browser came to report that it could not read the file the
   server was serving. */
const base = new URL(params.get("base") ?? "./", location.href).href;
const theme = params.get("theme") ?? "dark";

const root = document.getElementById("root");

function fail(message) {
  root.textContent = message;
  root.setAttribute("style", "padding:2rem;font:14px system-ui;color:#9494a8");
  report();
}

/**
 * How tall the rendered document actually is.
 *
 * Not `documentElement.scrollHeight`: the viewer's stylesheet stretches the
 * page to the frame with `min-height: 100vh`, so that number is the frame's
 * own height. Reporting it made the parent grow the frame, which grew the
 * number, which grew the frame — a page that scrolled on its own and ran to
 * thousands of empty pixels.
 *
 * The bottom edge of the last laid-out child does not move when the frame
 * grows, so measuring it settles after one pass.
 */
function contentHeight() {
  const root = document.getElementById("root");
  if (!root) return 0;
  let bottom = 0;
  for (const child of root.children) {
    const rect = child.getBoundingClientRect();
    if (rect.height === 0 && rect.width === 0) continue;
    bottom = Math.max(bottom, rect.bottom + window.scrollY);
  }
  if (bottom === 0) return 0;
  const padding = parseFloat(getComputedStyle(root).paddingBottom) || 0;
  return Math.ceil(bottom + padding);
}

let lastReported = 0;
let pending = false;

function report() {
  if (pending) return;
  pending = true;
  requestAnimationFrame(() => {
    pending = false;
    const height = contentHeight();
    /* A frame that never measured anything keeps whatever it had. */
    if (height < 1 || Math.abs(height - lastReported) <= 2) return;
    lastReported = height;
    parent.postMessage({ type: "phantom-viewer-height", height }, location.origin);
  });
}

async function ready(timeoutMs = 8000) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    if (window.phantomViewer?.render) return true;
    await new Promise((r) => setTimeout(r, 40));
  }
  return false;
}

if (!doc) {
  fail("No document requested.");
} else {
  try {
    const res = await fetch(doc);
    if (!res.ok) throw new Error(`${res.status} ${res.statusText}`);
    const source = await res.text();
    if (!(await ready())) throw new Error("the viewer did not start");
    window.phantomViewer.render({ source, baseURL: base, theme });
    new ResizeObserver(report).observe(document.getElementById("root"));
    setTimeout(report, 60);
    setTimeout(report, 400);
    setTimeout(report, 1200);
  } catch (error) {
    fail(`This document could not be rendered: ${error.message}`);
  }
}
