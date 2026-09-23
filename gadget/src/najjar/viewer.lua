--------------------------------------------------------------------------------
-- Najjar Pro — interactive 3D viewer (v0.7)
--
-- Generates ONE self-contained HTML file: no internet, no libraries.
-- A tiny hand-written 3D engine (canvas, painter's algorithm) renders the
-- panel boxes; the user can drag to rotate, scroll to zoom, explode the
-- cabinet with a slider, click parts in the list to highlight them, and
-- read the dimension-check results.
--------------------------------------------------------------------------------
local M = {}

local function esc(s)
  s = tostring(s)
  return (s:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end

---
-- Write the viewer HTML.
--   parts   -- unique parts (for the list + dims)
--   boxes   -- 3D boxes from najjar.model3d
--   checks  -- entries from najjar.check (may be nil)
--   opts    -- { title, tr = translator, lang, rtl }
--
function M.write(path, parts, boxes, checks, opts)
  opts = opts or {}
  local tr = opts.tr or function(k, p)
    local s = k
    if type(p) == "table" then
      for kk, vv in pairs(p) do s = s:gsub("{" .. tostring(kk) .. "}", tostring(vv)) end
    end
    return s
  end

  local json = require("najjar.json")

  -- parts list data
  local list = {}
  for _, p in ipairs(parts) do
    list[#list + 1] = {
      id = p.id, label = p.label, role = p.role,
      w = math.floor(p.w + 0.5), h = math.floor(p.h + 0.5),
      t = p.thickness, qty = p.qty,
      note = (p.meta and p.meta.note) or "",
      edge = tr("edge_" .. ((p.meta and p.meta.edge_banding) or "none")),
    }
  end

  -- check strings
  local check_items = {}
  for _, e in ipairs(checks or {}) do
    check_items[#check_items + 1] = { level = e.level, text = tr(e.code, e.params) }
  end

  local payload = json.encode({
    parts = list,
    boxes = boxes,
    checks = check_items,
    strings = {
      title = tr("viewer_title", { project = opts.title or "Najjar Pro" }),
      explode = tr("viewer_explode"),
      parts_h = tr("viewer_parts"),
      drag = tr("viewer_drag"),
      front = tr("viewer_front"),
      iso = tr("viewer_iso"),
      top = tr("viewer_top"),
      check_h = tr("viewer_check"),
      no_check = tr("viewer_no_check"),
      dims = tr("viewer_dims"),
      edge = tr("bom_edge"),
      note = tr("bom_notes"),
      qty = tr("bom_qty"),
      tagline = tr("viewer_tagline"),
    },
  })

  local html = {} 
  html[#html+1] = '<!DOCTYPE html><html><head><meta charset="utf-8">'
  html[#html+1] = '<title>Najjar Pro</title><style>'
  html[#html+1] = [[
body { margin:0; font-family: Segoe UI, Arial; background:#11161d; color:#e8ecf2; overflow:hidden; }
#hd { position:fixed; top:0; left:0; right:0; height:54px; padding:10px 16px; box-sizing:border-box;
      background:#0c1017; border-bottom:1px solid #232c3a; z-index:5; }
#hd .t { font-size:17px; font-weight:bold; }
#hd .s { font-size:12px; color:#8a93a3; margin-top:2px; }
#wrap { position:fixed; top:54px; bottom:0; left:0; right:220px; }
canvas { display:block; width:100%; height:100%; cursor:grab; }
#side { position:fixed; top:54px; right:0; bottom:0; width:220px; background:#0c1017;
        border-left:1px solid #232c3a; overflow-y:auto; padding:10px; box-sizing:border-box; z-index:5; }
#side h3 { font-size:13px; margin:8px 0 6px 0; color:#c8ceda; }
.pitem { padding:6px 8px; margin:4px 0; border:1px solid #232c3a; border-radius:6px; cursor:pointer; font-size:12px; }
.pitem:hover { background:#1a2230; }
.pitem.sel { border-color:#f0b64b; background:#241f12; }
.pitem .nm { font-weight:bold; }
.pitem .dm { color:#8a93a3; margin-top:2px; }
.chk { padding:5px 8px; margin:4px 0; border-radius:6px; font-size:12px; }
.chk.warn { background:#332711; border:1px solid #7a5b16; color:#ffd47f; }
.chk.error { background:#331111; border:1px solid #7a1616; color:#ff8f8f; }
.chk.info { background:#11251a; border:1px solid #1c5c39; color:#8fe0b1; }
#ctl { position:fixed; bottom:12px; left:16px; z-index:6; background:#0c1017ee; border:1px solid #232c3a;
       border-radius:8px; padding:10px 14px; font-size:12px; }
#ctl input[type=range] { vertical-align:middle; }
.vbtn { display:inline-block; padding:3px 10px; margin-right:4px; border:1px solid #35415a;
        border-radius:5px; cursor:pointer; background:#1a2230; }
.vbtn:hover { background:#243044; }
]]
  html[#html+1] = '</style></head><body>'
  html[#html+1] = '<div id="hd"><div class="t"></div><div class="s"></div></div>'
  html[#html+1] = '<div id="wrap"><canvas id="cv"></canvas></div>'
  html[#html+1] = '<div id="side"><h3 id="ph"></h3><div id="plist"></div><h3 id="ch"></h3><div id="checks"></div></div>'
  html[#html+1] = '<div id="ctl"><span class="vbtn" id="bFront"></span><span class="vbtn" id="bIso"></span><span class="vbtn" id="bTop"></span> &nbsp; <span id="exLbl"></span> <input type="range" id="explode" min="0" max="100" value="0"> <span id="hint" style="color:#8a93a3"></span></div>'

  html[#html+1] = '<script>\nvar DATA = ' .. payload .. ';\n'
  html[#html+1] = [==[
(function () {
  var S = DATA.strings;
  document.querySelector('#hd .t').textContent = S.title;
  document.querySelector('#hd .s').textContent = S.tagline;
  document.getElementById('ph').textContent = S.parts_h;
  document.getElementById('ch').textContent = S.check_h;
  document.getElementById('bFront').textContent = S.front;
  document.getElementById('bIso').textContent = S.iso;
  document.getElementById('bTop').textContent = S.top;
  document.getElementById('exLbl').textContent = S.explode;
  document.getElementById('hint').textContent = S.drag;

  var cv = document.getElementById('cv');
  var ctx = cv.getContext('2d');
  var W = 0, H = 0;
  function resize() {
    var r = document.getElementById('wrap').getBoundingClientRect();
    cv.width = W = r.width; cv.height = H = r.height;
  }
  window.addEventListener('resize', resize); resize();

  // camera -----------------------------------------------------------------
  var yaw = -0.6, pitch = 0.42, dist = 2200, fov = 1100;
  var explode = 0;
  var selected = -1;

  function setView(v) {
    if (v === 'front') { yaw = 0; pitch = 0; }
    if (v === 'iso') { yaw = -0.6; pitch = 0.42; }
    if (v === 'top') { yaw = 0; pitch = 1.35; }
    draw();
  }
  document.getElementById('bFront').onclick = function () { setView('front'); };
  document.getElementById('bIso').onclick = function () { setView('iso'); };
  document.getElementById('bTop').onclick = function () { setView('top'); };
  document.getElementById('explode').oninput = function () {
    explode = this.value / 100; draw();
  };

  var drag = null;
  cv.addEventListener('mousedown', function (e) { drag = { x: e.clientX, y: e.clientY }; });
  window.addEventListener('mousemove', function (e) {
    if (!drag) return;
    yaw += (e.clientX - drag.x) * 0.008;
    pitch += (e.clientY - drag.y) * 0.008;
    pitch = Math.max(-1.4, Math.min(1.4, pitch));
    drag = { x: e.clientX, y: e.clientY };
    draw();
  });
  window.addEventListener('mouseup', function () { drag = null; });
  cv.addEventListener('wheel', function (e) {
    e.preventDefault();
    dist *= (e.deltaY > 0) ? 1.1 : 0.9;
    dist = Math.max(300, Math.min(12000, dist));
    draw();
  });

  // touch (v0.8): one finger rotates, pinch zooms - works on shop tablets
  var tp = null;
  cv.addEventListener('touchstart', function (e) {
    if (e.touches.length === 1) tp = { x: e.touches[0].clientX, y: e.touches[0].clientY };
    else if (e.touches.length === 2) tp = { d: Math.hypot(e.touches[0].clientX - e.touches[1].clientX, e.touches[0].clientY - e.touches[1].clientY) };
    e.preventDefault();
  }, { passive: false });
  cv.addEventListener('touchmove', function (e) {
    if (e.touches.length === 1 && tp && tp.x !== undefined) {
      yaw += (e.touches[0].clientX - tp.x) * 0.008;
      pitch += (e.touches[0].clientY - tp.y) * 0.008;
      pitch = Math.max(-1.4, Math.min(1.4, pitch));
      tp = { x: e.touches[0].clientX, y: e.touches[0].clientY };
      draw();
    } else if (e.touches.length === 2 && tp && tp.d !== undefined) {
      var dd = Math.hypot(e.touches[0].clientX - e.touches[1].clientX, e.touches[0].clientY - e.touches[1].clientY);
      if (dd > 0 && tp.d > 0) { dist *= tp.d / dd; dist = Math.max(300, Math.min(12000, dist)); }
      tp = { d: dd };
      draw();
    }
    e.preventDefault();
  }, { passive: false });
  cv.addEventListener('touchend', function () { tp = null; });

  // geometry ----------------------------------------------------------------
  function rot(p) {
    var cy = Math.cos(yaw), sy = Math.sin(yaw);
    var cp = Math.cos(pitch), sp = Math.sin(pitch);
    var x = p[0] * cy + p[2] * sy;
    var z = -p[0] * sy + p[2] * cy;
    var y = p[1] * cp - z * sp;
    z = p[1] * sp + z * cp;
    return [x, y, z];
  }

  var FACES = [
    { n: [0, 0, -1], c: [[-1, -1, -1], [1, -1, -1], [1, 1, -1], [-1, 1, -1]] },
    { n: [0, 0, 1],  c: [[1, -1, 1], [-1, -1, 1], [-1, 1, 1], [1, 1, 1]] },
    { n: [-1, 0, 0], c: [[-1, -1, 1], [-1, -1, -1], [-1, 1, -1], [-1, 1, 1]] },
    { n: [1, 0, 0],  c: [[1, -1, -1], [1, -1, 1], [1, 1, 1], [1, 1, -1]] },
    { n: [0, -1, 0], c: [[-1, -1, 1], [1, -1, 1], [1, -1, -1], [-1, -1, -1]] },
    { n: [0, 1, 0],  c: [[-1, 1, -1], [1, 1, -1], [1, 1, 1], [-1, 1, 1]] }
  ];

  function shade(hex, k) {
    var r = parseInt(hex.substr(1, 2), 16), g = parseInt(hex.substr(3, 2), 16), b = parseInt(hex.substr(5, 2), 16);
    r = Math.round(r * k); g = Math.round(g * k); b = Math.round(b * k);
    return 'rgb(' + r + ',' + g + ',' + b + ')';
  }

  var LIGHT = null;
  function norm(v) {
    var l = Math.sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2]);
    return [v[0] / l, v[1] / l, v[2] / l];
  }

  function draw() {
    ctx.fillStyle = '#11161d';
    ctx.fillRect(0, 0, W, H);
    LIGHT = norm([0.35, 0.75, -0.55]);

    // camera target = center of all boxes
    var cx = 0, cy = 0, cz = 0;
    var bs = DATA.boxes;
    for (var i = 0; i < bs.length; i++) {
      cx += bs[i].c[0]; cy += bs[i].c[1]; cz += bs[i].c[2];
    }
    cx /= bs.length; cy /= bs.length; cz /= bs.length;
    var target = [cx, cy, cz];

    var faces = [];
    for (var i = 0; i < bs.length; i++) {
      var b = bs[i];
      var ex = explode * 220;
      var cc = [b.c[0] + b.e[0] * ex, b.c[1] + b.e[1] * ex, b.c[2] + b.e[2] * ex];
      for (var fi = 0; fi < FACES.length; fi++) {
        var F = FACES[fi];
        var pts = [], zsum = 0;
        for (var k = 0; k < 4; k++) {
          var cor = F.c[k];
          var p = [cc[0] + cor[0] * b.s[0] / 2 - target[0],
                   cc[1] + cor[1] * b.s[1] / 2 - target[1],
                   cc[2] + cor[2] * b.s[2] / 2 - target[2]];
          var r = rot(p);
          pts.push(r); zsum += r[2];
        }
        var n = rot([F.n[0], F.n[1], F.n[2]]);
        faces.push({ pts: pts, z: zsum / 4, n: n, color: b.color, idx: i, label: b.label });
      }
    }
    faces.sort(function (a, b2) { return b2.z - a.z; });

    for (var i = 0; i < faces.length; i++) {
      var f = faces[i];
      var lum = Math.max(0.35, f.n[0] * LIGHT[0] + f.n[1] * LIGHT[1] + f.n[2] * LIGHT[2]);
      var col = (f.idx === selected) ? '#f0b64b' : f.color;
      ctx.beginPath();
      for (var k = 0; k < 4; k++) {
        var zz = dist - f.pts[k][2];
        if (zz < 10) zz = 10;
        var px = W / 2 + f.pts[k][0] * fov / zz;
        var py = H / 2 - f.pts[k][1] * fov / zz;
        if (k === 0) ctx.moveTo(px, py); else ctx.lineTo(px, py);
      }
      ctx.closePath();
      ctx.fillStyle = shade(col, lum);
      ctx.fill();
      ctx.strokeStyle = 'rgba(0,0,0,0.35)';
      ctx.stroke();
    }
  }

  // parts list ------------------------------------------------------------------
  var pl = document.getElementById('plist');
  DATA.parts.forEach(function (p, i) {
    var d = document.createElement('div');
    d.className = 'pitem';
    d.innerHTML = '<div class="nm">' + p.id + ' ×' + p.qty + '</div>' +
      '<div class="dm">' + S.dims + ': ' + p.w + ' × ' + p.h + ' × ' + p.t + '</div>' +
      '<div class="dm">' + S.edge + ': ' + p.edge + '</div>' +
      (p.note ? '<div class="dm">' + S.note + ': ' + p.note + '</div>' : '');
    d.onclick = function () {
      var all = pl.children;
      for (var j = 0; j < all.length; j++) all[j].classList.remove('sel');
      d.classList.add('sel');
      selected = -1;
      for (var j = 0; j < DATA.boxes.length; j++) {
        if (DATA.boxes[j].id.indexOf(p.id) === 0) { selected = j; break; }
      }
      draw();
    };
    pl.appendChild(d);
  });

  // checks -----------------------------------------------------------------------
  var ch = document.getElementById('checks');
  if (!DATA.checks.length) {
    ch.innerHTML = '<div class="chk info">' + S.no_check + '</div>';
  } else {
    DATA.checks.forEach(function (c) {
      var d = document.createElement('div');
      d.className = 'chk ' + c.level;
      d.textContent = c.text;
      ch.appendChild(d);
    });
  }

  draw();
})();
]==]
  html[#html+1] = '</script></body></html>'

  local fs = require("najjar.fs")
  return fs.writefile(path, table.concat(html, "\n"))
end

return M
