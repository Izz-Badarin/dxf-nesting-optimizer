/* dxf-nesting-optimizer web GUI */
"use strict";

const $ = (sel) => document.querySelector(sel);
const state = {
  file: null,
  example: null,
  payload: null,
  selectedSheet: {},   // strategy -> sheet index
  showLabels: true,
};

/* ---------------- init ---------------- */

document.addEventListener("DOMContentLoaded", () => {
  $("#version-badge").textContent = "v" + (window.NEST_VERSION || "0.1.0");

  const fileInput = $("#file-input");
  const dropzone = $("#dropzone");

  fileInput.addEventListener("change", () => {
    if (fileInput.files.length) setSourceFile(fileInput.files[0]);
  });
  ["dragenter", "dragover"].forEach((ev) =>
    dropzone.addEventListener(ev, (e) => { e.preventDefault(); dropzone.classList.add("drag"); })
  );
  ["dragleave", "drop"].forEach((ev) =>
    dropzone.addEventListener(ev, (e) => { e.preventDefault(); dropzone.classList.remove("drag"); })
  );
  dropzone.addEventListener("drop", (e) => {
    if (e.dataTransfer.files.length) setSourceFile(e.dataTransfer.files[0]);
  });

  $("#sheet-preset").addEventListener("change", (e) => {
    const [w, h] = e.target.value.split("x");
    if (w && h) { $("#sheet-width").value = w; $("#sheet-height").value = h; }
  });
  ["#tool-diameter", "#clearance"].forEach((sel) =>
    $(sel).addEventListener("input", updateGapPreview)
  );
  $("#show-labels").addEventListener("change", (e) => {
    state.showLabels = e.target.checked;
    renderSheets();
  });
  $("#run").addEventListener("click", runNesting);

  fetch("/api/examples")
    .then((r) => r.json())
    .then((data) => {
      const wrap = $("#example-buttons");
      data.examples.forEach((name) => {
        const chip = document.createElement("button");
        chip.className = "chip";
        chip.textContent = name.replace(/\.dxf$/, "").replaceAll("_", " ");
        chip.title = name;
        chip.addEventListener("click", () => {
          setExample(name, chip);
        });
        wrap.appendChild(chip);
      });
    })
    .catch(() => {});
  updateGapPreview();
});

function setSourceFile(file) {
  if (!file.name.toLowerCase().endsWith(".dxf")) {
    setStatus("Please choose a .dxf file.", "error");
    return;
  }
  state.file = file;
  state.example = null;
  document.querySelectorAll("#example-buttons .chip").forEach((c) => c.classList.remove("active"));
  $("#file-name").textContent = `${file.name} (${(file.size / 1024).toFixed(0)} KB)`;
}

function setExample(name, chip) {
  state.example = name;
  state.file = null;
  document.querySelectorAll("#example-buttons .chip").forEach((c) => c.classList.remove("active"));
  chip.classList.add("active");
  $("#file-name").textContent = `example: ${name}`;
}

function updateGapPreview() {
  const tool = parseFloat($("#tool-diameter").value) || 0;
  const clearance = parseFloat($("#clearance").value) || 0;
  $("#gap-preview").textContent = (tool + 2 * clearance).toFixed(1) + " mm";
}

function setStatus(message, kind) {
  const el = $("#status");
  el.hidden = !message;
  el.textContent = message || "";
  el.className = "status " + (kind || "info");
}

/* ---------------- run ---------------- */

async function runNesting() {
  if (!state.file && !state.example) {
    setStatus("Choose a DXF file or click one of the examples first.", "error");
    return;
  }
  const btn = $("#run");
  btn.disabled = true;
  setStatus("Importing DXF and nesting both strategies… this can take a moment.");
  $("#results").hidden = true;

  const form = new FormData();
  if (state.file) form.append("file", state.file);
  if (state.example) form.append("example", state.example);
  form.append("sheet_width", $("#sheet-width").value);
  form.append("sheet_height", $("#sheet-height").value);
  form.append("tool_diameter", $("#tool-diameter").value);
  form.append("clearance", $("#clearance").value);
  form.append("edge_clearance", $("#edge-clearance").value);
  form.append("rotation_step", $("#rotation-step").value);
  form.append("allow_mirror", $("#allow-mirror").checked);
  form.append("depth", $("#depth").value);

  try {
    const response = await fetch("/api/nest", { method: "POST", body: form });
    if (!response.ok) {
      let detail = response.statusText;
      try { detail = (await response.json()).detail || detail; } catch {}
      throw new Error(detail);
    }
    state.payload = await response.json();
    state.selectedSheet = {};
    setStatus("");
    $("#results").hidden = false;
    renderAll();
    $("#results").scrollIntoView({ behavior: "smooth", block: "start" });
  } catch (err) {
    setStatus("Nesting failed: " + err.message, "error");
  } finally {
    btn.disabled = false;
  }
}

/* ---------------- render ---------------- */

function renderAll() {
  renderCards();
  renderRecommendation();
  renderComparisonTable();
  renderSheets();
  renderDownloads();
}

function renderCards() {
  const p = state.payload;
  const job = p.job;
  const cards = [
    { k: "Parts", v: `${job.parts.unique}`, s: `${job.parts.total_quantity} total` },
    { k: "Part area", v: fmtArea(job.parts.total_area_mm2), s: "mm² to place" },
  ];
  for (const name of Object.keys(p.strategies)) {
    const m = p.strategies[name].metrics;
    cards.push({
      k: name,
      v: `${m.utilization_pct}%`,
      s: `${m.sheet_count} sheet${m.sheet_count === 1 ? "" : "s"} · ${m.replication_efficiency.toFixed(2)} replication`,
    });
  }
  $("#summary-cards").innerHTML = cards
    .map((c) => `<div class="card"><div class="k">${esc(c.k)}</div><div class="v">${esc(String(c.v))}</div><div class="s">${esc(c.s)}</div></div>`)
    .join("");
}

function renderRecommendation() {
  const rec = state.payload.comparison.recommendation;
  const el = $("#recommendation");
  if (!rec) { el.hidden = true; return; }
  const scores = Object.entries(rec.scores).map(([n, s]) => `${esc(n)}: ${s}`).join(" · ");
  el.hidden = false;
  el.innerHTML = `
    <h3>✅ Recommended: ${esc(rec.strategy)}</h3>
    <div class="scores">weighted scores — ${scores}</div>
    <ul>${rec.rationale.map((r) => `<li>${esc(r)}</li>`).join("")}</ul>`;
}

function renderComparisonTable() {
  const table = state.payload.comparison.table;
  const names = Object.keys(state.payload.strategies);
  const rows = table
    .map((row) => {
      const cells = names
        .map((n) => {
          const best = row.better === n;
          return `<td class="${best ? "best" : ""}">${esc(String(row[n]))}${best ? " ✓" : ""}</td>`;
        })
        .join("");
      return `<tr><td>${esc(row.metric)}</td>${cells}</tr>`;
    })
    .join("");
  $("#comparison-table").innerHTML =
    `<thead><tr><th>Metric</th>${names.map((n) => `<th>${esc(n)}</th>`).join("")}</tr></thead><tbody>${rows}</tbody>`;
}

function renderSheets() {
  const p = state.payload;
  const wrap = $("#sheet-columns");
  wrap.innerHTML = "";
  for (const [name, strategy] of Object.entries(p.strategies)) {
    const col = document.createElement("div");
    col.className = "strategy-col";

    const m = strategy.metrics;
    const head = document.createElement("h3");
    head.innerHTML = `${esc(name)} <span class="util-chip">— ${m.utilization_pct}% util · ${m.sheet_count} sheet${m.sheet_count === 1 ? "" : "s"}</span>`;
    col.appendChild(head);

    if (strategy.unplaced.length) {
      const warn = document.createElement("p");
      warn.style.cssText = "color:#b45309;font-size:13px";
      warn.textContent = "⚠ unplaced: " + strategy.unplaced.map((u) => `${u.part_id} ×${u.quantity}`).join(", ");
      col.appendChild(warn);
    }

    const uniqueSheets = strategy.sheets;   // already copy-merged by the backend
    const selected = state.selectedSheet[name] ?? 0;
    const tabs = document.createElement("div");
    tabs.className = "strategy-chips";
    uniqueSheets.forEach((sheet, i) => {
      const tab = document.createElement("button");
      tab.className = "chip" + (i === selected ? " active" : "");
      const copies = sheet.copies > 1 ? ` ×${sheet.copies}` : "";
      tab.textContent = `Sheet ${sheet.index}${copies}`;
      tab.addEventListener("click", () => { state.selectedSheet[name] = i; renderSheets(); });
      tabs.appendChild(tab);
    });
    col.appendChild(tabs);

    const frame = document.createElement("div");
    frame.className = "sheet-frame";
    const sheet = uniqueSheets[Math.min(selected, uniqueSheets.length - 1)];
    if (sheet) frame.appendChild(buildSheetSvg(sheet, p.job.sheet));
    col.appendChild(frame);

    wrap.appendChild(col);
  }
}

function buildSheetSvg(sheet, sheetSpec) {
  const W = sheetSpec.width, H = sheetSpec.height;
  const pad = Math.max(W, H) * 0.03;
  const svgNS = "http://www.w3.org/2000/svg";
  const svg = document.createElementNS(svgNS, "svg");
  svg.setAttribute("viewBox", `${-pad} ${-pad} ${W + 2 * pad} ${H + 2 * pad}`);
  svg.setAttribute("role", "img");
  svg.setAttribute("aria-label", `Sheet ${sheet.index}`);

  // sheet outline
  svg.appendChild(rect(svgNS, 0, 0, W, H, { fill: "#ffffff", stroke: "#334155", "stroke-width": Math.max(W, H) * 0.002 }));

  // offcuts
  for (const ring of sheet.offcuts) {
    svg.appendChild(poly(svgNS, ring, { fill: "#e2e8f0", stroke: "#94a3b8", "stroke-dasharray": "8 6", "stroke-width": Math.max(W, H) * 0.0012 }));
  }

  // parts
  const fontSize = Math.max(W, H) * 0.016;
  for (const placement of sheet.placements) {
    const g = document.createElementNS(svgNS, "g");
    g.appendChild(poly(svgNS, placement.polygon, {
      fill: placement.color, "fill-opacity": "0.88",
      stroke: "#1e293b", "stroke-width": Math.max(W, H) * 0.0012,
    }));
    for (const hole of placement.holes) {
      g.appendChild(poly(svgNS, hole, { fill: "#ffffff", stroke: "#1e293b", "stroke-width": Math.max(W, H) * 0.001 }));
    }
    if (state.showLabels) {
      const c = ringCentroid(placement.polygon);
      const text = document.createElementNS(svgNS, "text");
      text.setAttribute("x", c[0]); text.setAttribute("y", c[1]);
      text.setAttribute("font-size", fontSize);
      text.setAttribute("text-anchor", "middle");
      text.setAttribute("dominant-baseline", "middle");
      text.setAttribute("class", "svg-label");
      text.textContent = placement.part_id;
      g.appendChild(text);
    }
    g.setAttribute("class", "svg-part");
    g.addEventListener("mousemove", (e) => showTooltip(e, placement));
    g.addEventListener("mouseleave", hideTooltip);
    svg.appendChild(g);
  }

  // utilization badge
  const badge = document.createElementNS(svgNS, "text");
  badge.setAttribute("x", 0); badge.setAttribute("y", -pad * 0.35);
  badge.setAttribute("font-size", fontSize);
  badge.setAttribute("class", "svg-label");
  badge.textContent = `sheet ${sheet.index}: ${sheet.utilization_pct}% utilized${sheet.copies > 1 ? ` — ${sheet.copies} identical copies` : ""}`;
  svg.appendChild(badge);

  return svg;
}

function poly(svgNS, ring, attrs) {
  const el = document.createElementNS(svgNS, "polygon");
  el.setAttribute("points", ring.map(([x, y]) => `${x},${y}`).join(" "));
  for (const [k, v] of Object.entries(attrs)) el.setAttribute(k, v);
  return el;
}

function rect(svgNS, x, y, w, h, attrs) {
  const el = document.createElementNS(svgNS, "rect");
  el.setAttribute("x", x); el.setAttribute("y", y);
  el.setAttribute("width", w); el.setAttribute("height", h);
  for (const [k, v] of Object.entries(attrs)) el.setAttribute(k, v);
  return el;
}

function ringCentroid(ring) {
  let x = 0, y = 0;
  for (const [px, py] of ring) { x += px; y += py; }
  return [x / ring.length, y / ring.length];
}

/* ---------------- tooltip ---------------- */

function showTooltip(event, placement) {
  const el = $("#tooltip");
  el.innerHTML = `
    <div class="t-name">${esc(placement.part_id)} — ${esc(placement.name || "")}</div>
    <div class="t-dim">${placement.mirrored ? "mirrored" : ""}${placement.rotation_deg ? ` · ${Math.round(placement.rotation_deg)}°` : ""}</div>`;
  el.hidden = false;
  const pad = 14;
  let left = event.clientX + pad, top = event.clientY + pad;
  const box = el.getBoundingClientRect();
  if (left + box.width > window.innerWidth - 8) left = event.clientX - box.width - pad;
  if (top + box.height > window.innerHeight - 8) top = event.clientY - box.height - pad;
  el.style.left = left + "px";
  el.style.top = top + "px";
}

function hideTooltip() { $("#tooltip").hidden = true; }

/* ---------------- downloads ---------------- */

function renderDownloads() {
  const id = state.payload.job_id;
  const links = [
    { label: "⬇ DXF · symmetry-first", href: `/api/download/dxf/${id}/symmetry-first` },
    { label: "⬇ DXF · waste-first", href: `/api/download/dxf/${id}/waste-first` },
    { label: "⬇ Report · JSON", href: `/api/download/report/${id}/json` },
    { label: "⬇ Report · Markdown", href: `/api/download/report/${id}/md` },
    { label: "⬇ Comparison · PDF", href: `/api/download/pdf/${id}` },
  ];
  $("#downloads").innerHTML = links
    .map((l) => `<a class="chip download" href="${l.href}" download>${esc(l.label)}</a>`)
    .join("");
}

/* ---------------- helpers ---------------- */

function esc(text) {
  return String(text).replace(/[&<>"']/g, (c) => ({
    "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;",
  })[c]);
}

function fmtArea(mm2) {
  return mm2 >= 1e6 ? (mm2 / 1e6).toFixed(2) + " m²" : Math.round(mm2).toLocaleString();
}
