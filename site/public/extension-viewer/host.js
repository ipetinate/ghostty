// Drives the vendored phantom-mdx viewer from a web page instead of from the
// app's WKWebView. The bundle is copied byte for byte; only this file and the
// page around it are the site's own — the app's own page allows `file:` images
// and this one is served over https, which is the whole of the difference.
//
// Reads ?doc= (the document to render) and ?base= (the folder its media sit
// in), then reports its height so the embedding page can size the frame.

const params = new URLSearchParams(location.search);
const doc = params.get("doc");
const base = params.get("base") ?? "";
const theme = params.get("theme") ?? "dark";

const root = document.getElementById("root");

function fail(message) {
  root.textContent = message;
  root.setAttribute("style", "padding:2rem;font:14px system-ui;color:#9494a8");
  report();
}

function report() {
  const height = Math.ceil(
    Math.max(
      document.documentElement.scrollHeight,
      document.body?.scrollHeight ?? 0,
    ),
  );
  parent.postMessage({ type: "phantom-viewer-height", height }, location.origin);
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
    new ResizeObserver(report).observe(document.documentElement);
    setTimeout(report, 60);
    setTimeout(report, 400);
    setTimeout(report, 1200);
  } catch (error) {
    fail(`This document could not be rendered: ${error.message}`);
  }
}
