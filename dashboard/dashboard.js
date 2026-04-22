// dashboard.js — renders charts from window.__GRAPHIFY_DATA (set by
// data-bundle.js, regenerated on every dashboard-append). Script-tag
// loading avoids the file:// CORS block on fetch().

const state = {
  projects: {}, // slug -> [records]
  active: "__all",
  charts: {},
};

function loadFromBundle() {
  const bundle = window.__GRAPHIFY_DATA;
  if (!bundle || typeof bundle !== "object") {
    const e = document.getElementById("error");
    e.style.display = "block";
    e.textContent = "No data bundle found. Run: bash ~/Projects/claude-workflow/scripts/dashboard-bundle.sh";
    return;
  }
  for (const [slug, records] of Object.entries(bundle)) {
    if (Array.isArray(records) && records.length) state.projects[slug] = records;
  }
  renderTabs();
  renderActive();
  renderLastUpdated();
}

function renderLastUpdated() {
  const all = Object.values(state.projects).flat();
  if (!all.length) {
    document.getElementById("last-updated").textContent = "no data yet — run bootstrap";
    return;
  }
  const latest = all.map(r => r.ts).sort().pop();
  document.getElementById("last-updated").textContent = `last event: ${latest}`;
}

function renderTabs() {
  const tabs = document.getElementById("tabs");
  tabs.innerHTML = "";
  const all = document.createElement("button");
  all.textContent = "All projects";
  all.dataset.project = "__all";
  if (state.active === "__all") all.classList.add("active");
  all.onclick = () => setActive("__all");
  tabs.appendChild(all);
  for (const slug of Object.keys(state.projects).sort()) {
    const b = document.createElement("button");
    b.textContent = slug;
    b.dataset.project = slug;
    if (state.active === slug) b.classList.add("active");
    b.onclick = () => setActive(slug);
    tabs.appendChild(b);
  }
}

function setActive(slug) {
  state.active = slug;
  document.querySelectorAll("#tabs button").forEach(b => {
    b.classList.toggle("active", b.dataset.project === slug);
  });
  renderActive();
}

function destroyCharts() {
  for (const c of Object.values(state.charts)) { try { c.destroy(); } catch {} }
  state.charts = {};
}

function renderActive() {
  destroyCharts();
  const main = document.getElementById("main");
  main.innerHTML = "";
  const recs = state.active === "__all"
    ? Object.values(state.projects).flat().sort((a,b) => a.ts < b.ts ? -1 : 1)
    : state.projects[state.active] || [];
  if (!recs.length) {
    main.innerHTML = '<div class="card wide"><div class="empty">No data for this project yet. Run /wrap or the bootstrap.</div></div>';
    return;
  }
  addLineCard(main, "nodes", "Nodes", recs, r => r.graph?.nodes);
  addLineCard(main, "edges", "Edges", recs, r => r.graph?.edges);
  addLineCard(main, "communities", "Communities", recs, r => r.graph?.communities);
  addLineCard(main, "reduction", "Token reduction (x)", recs, r => r.benchmark?.reduction_ratio);
  addLineCard(main, "wikiPages", "Wiki pages (total)", recs, r => r.wiki?.pages_total);
  addSessionsCard(main, recs);
  addSummaryTable(main, recs);
}

function formatTs(ts) {
  const d = new Date(ts);
  const mm = String(d.getMonth() + 1).padStart(2, "0");
  const dd = String(d.getDate()).padStart(2, "0");
  const hh = String(d.getHours()).padStart(2, "0");
  const mi = String(d.getMinutes()).padStart(2, "0");
  return `${mm}/${dd} ${hh}:${mi}`;
}

function addLineCard(main, id, title, recs, extract) {
  const card = document.createElement("div");
  card.className = "card";
  card.innerHTML = `<h2>${title}</h2><canvas id="chart-${id}"></canvas>`;
  main.appendChild(card);
  const ctx = card.querySelector("canvas").getContext("2d");
  const grouped = groupByProject(recs);
  // Shared x-axis: union of all timestamps across projects, sorted.
  const allTs = [...new Set(recs.map(r => r.ts))].sort();
  const labels = allTs.map(formatTs);
  const datasets = grouped.map(([proj, rs]) => {
    const byTs = Object.fromEntries(rs.map(r => [r.ts, extract(r)]));
    return {
      label: proj,
      data: allTs.map(t => byTs[t] ?? null),
      borderWidth: 2,
      tension: 0.2,
      pointRadius: 3,
      spanGaps: true,
    };
  });
  state.charts[id] = new Chart(ctx, {
    type: "line",
    data: { labels, datasets },
    options: {
      responsive: true,
      animation: false,
      plugins: { legend: { display: datasets.length > 1, labels: { color: "#9aa0a6" } } },
      scales: {
        x: { ticks: { color: "#9aa0a6", maxRotation: 0, autoSkip: true }, grid: { color: "#262a33" } },
        y: { ticks: { color: "#9aa0a6" }, grid: { color: "#262a33" }, beginAtZero: true },
      },
    },
  });
}

function addSessionsCard(main, recs) {
  const card = document.createElement("div");
  card.className = "card";
  card.innerHTML = `<h2>Sessions per week</h2><canvas id="chart-sessions"></canvas>`;
  main.appendChild(card);
  const wraps = recs.filter(r => r.event === "wrap");
  const byWeek = {};
  for (const r of wraps) {
    const d = new Date(r.ts);
    const y = d.getUTCFullYear();
    // ISO-ish week
    const oneJan = new Date(Date.UTC(y, 0, 1));
    const week = Math.ceil((((d - oneJan) / 86400000) + oneJan.getUTCDay() + 1) / 7);
    const key = `${y}-W${String(week).padStart(2,"0")}`;
    byWeek[key] = (byWeek[key] || 0) + 1;
  }
  const labels = Object.keys(byWeek).sort();
  state.charts.sessions = new Chart(card.querySelector("canvas").getContext("2d"), {
    type: "bar",
    data: { labels, datasets: [{ label: "wraps", data: labels.map(k => byWeek[k]),
                                  backgroundColor: "#4ec9b0" }] },
    options: {
      responsive: true, animation: false,
      plugins: { legend: { display: false } },
      scales: {
        x: { ticks: { color: "#9aa0a6" }, grid: { color: "#262a33" } },
        y: { ticks: { color: "#9aa0a6" }, grid: { color: "#262a33" }, beginAtZero: true },
      },
    },
  });
}

function groupByProject(recs) {
  const g = {};
  for (const r of recs) {
    const k = r.project || "(unknown)";
    (g[k] = g[k] || []).push(r);
  }
  for (const k of Object.keys(g)) g[k].sort((a,b) => a.ts < b.ts ? -1 : 1);
  return Object.entries(g);
}

function addSummaryTable(main, recs) {
  const card = document.createElement("div");
  card.className = "card wide";
  card.innerHTML = `<h2>Projects</h2>
    <table><thead><tr>
      <th>Project</th><th>Last event</th><th>Nodes</th><th>Edges</th>
      <th>Communities</th><th>Reduction</th><th>Top god nodes</th><th>Graph</th>
    </tr></thead><tbody></tbody></table>`;
  main.appendChild(card);
  const tbody = card.querySelector("tbody");
  const byProj = groupByProject(recs);
  for (const [proj, rs] of byProj) {
    const last = rs[rs.length - 1];
    const d = new Date(last.ts);
    const ageDays = Math.floor((Date.now() - d.getTime()) / 86400000);
    const badge = ageDays < 7 ? "green" : ageDays < 30 ? "yellow" : "red";
    const top3 = (last.graph?.god_nodes_top3 || []).join(", ") || "—";
    const projPath = `file://${projectPath(proj)}/graphify-out/graph.html`;
    tbody.insertAdjacentHTML("beforeend", `
      <tr>
        <td>${proj}</td>
        <td><span class="badge ${badge}">${ageDays}d ago</span></td>
        <td>${last.graph?.nodes ?? "—"}</td>
        <td>${last.graph?.edges ?? "—"}</td>
        <td>${last.graph?.communities ?? "—"}</td>
        <td>${last.benchmark?.reduction_ratio ? last.benchmark.reduction_ratio.toFixed(1) + "x" : "—"}</td>
        <td>${top3}</td>
        <td><a href="${projPath}">graph.html</a></td>
      </tr>`);
  }
}

function projectPath(slug) {
  // Best-effort. Case-preserving map for known projects; default capitalizes.
  const known = {
    "authtools": "AuthTools",
    "career": "career",
    "claude-workflow": "claude-workflow",
    "graphify": "graphify",
    "mnemom": "mnemom",
    "mobile": "Mobile",
    "modeltraining": "ModelTraining",
    "netsec": "NetSec",
    "obsidian-wiki": "obsidian-wiki",
    "pashion": "pashion",
    "redrabbit": "RedRabbit",
    "wiki-graph": "wiki-graph",
  };
  const name = known[slug] || slug;
  // ~ doesn't resolve in file:// — use a best-guess absolute path.
  // EDIT THIS: replace YOUR_USERNAME with your macOS username.
  return `/Users/YOUR_USERNAME/Projects/${name}`;
}

try {
  loadFromBundle();
} catch (err) {
  const e = document.getElementById("error");
  e.style.display = "block";
  e.textContent = `Error rendering dashboard: ${err}`;
}
