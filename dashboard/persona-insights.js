// persona-insights.js — renderer for the "Persona Insights" tab.
//
// Loaded under file:// (no fetch). Reads:
//   window.PERSONA_ROSTER       — set by dashboard/data/persona-roster.js
//   window.__PERSONA_RANKINGS   — set by dashboard/data/persona-rankings-bundle.js
//   window.__PERSONA_BUNDLES_LOADED — flipped to false by the index.html onerror
//                                    handlers when any bundle script 404s
//
// Registers window.__renderPersonaInsightsView, invoked by index.html when the
// user clicks the "Persona Insights" mode button.
//
// Design references (CANONICAL):
//   docs/specs/token-economics/spec.md (v4.2)
//   docs/specs/token-economics/plan/raw/ux.md (banner copy + column spec)
//   schemas/persona-rankings.allowlist.json (row shape)
//
// CSS classes are scaffolded by Agent G in dashboard/index.html — this file
// adds NO new classes. If a new visual is needed, list it for /preship instead
// of inlining a new selector here.

(function () {
  "use strict";

  // --------------------------------------------------------------------------
  // Constants
  // --------------------------------------------------------------------------

  // Color-band thresholds — heuristic, derived from spec example values
  // (e.g., "ux-flow 0.89 highest retention"). Reviewable post-merge.
  // TODO(v1.1): tune from observed distribution.
  const BAND_THRESHOLDS = {
    retention: { low: 0.20, high: 0.50 },
    survival:  { low: 0.20, high: 0.50 },
    unique:    { low: 0.05, high: 0.20 },
  };

  const STALE_DAYS = 14;

  // run_state → (badge class, badge text). complete_value renders silently.
  const STATE_BADGE = {
    complete_value:   null, // no badge (silent default)
    silent:           { cls: "silent",    text: "silent" },
    missing_survival: { cls: "yellow",    text: "survival pending" },
    missing_findings: { cls: "red",       text: "no findings" },
    missing_raw:      { cls: "red",       text: "no raw" },
    malformed:        { cls: "red",       text: "malformed" },
    cost_only:        { cls: "yellow",    text: "cost only" },
  };

  // Column descriptor list — drives header + sort dispatch.
  // sortKind: 'alpha' | 'numeric' | 'date' | 'state' | null (no sort).
  // nullsLast: true means null/undefined values sink to bottom regardless of dir.
  const COLUMNS = [
    { key: "persona",          label: "Persona",   sortKind: "alpha",   nullsLast: false },
    { key: "gate",             label: "Gate",      sortKind: "alpha",   nullsLast: false },
    { key: "_state",           label: "State",     sortKind: "state",   nullsLast: true,
      title: "Row data completeness. Hover any row's badge for the per-state breakdown." },
    { key: "_runs",            label: "Runs",      sortKind: "numeric", nullsLast: true,
      title: "value-window: N artifact directories; cost-window: M dispatches" },
    { key: "judge_retention_ratio",    label: "Retention", sortKind: "numeric", nullsLast: true,
      title: "Compression ratio: findings emitted by Judge that include this persona ÷ top-level bullets in this persona's raw output. NOT a survival rate — Judge can merge or split bullets." },
    { key: "downstream_survival_rate", label: "Survived", sortKind: "numeric", nullsLast: true,
      title: "Of this persona's findings that survived Judge clustering, fraction marked 'addressed' in next pipeline artifact. Empty cells may mean 'not yet evaluated' (downstream gate hasn't run)." },
    { key: "uniqueness_rate",  label: "Unique",    sortKind: "numeric", nullsLast: true,
      title: "Findings where this persona is the sole contributor (unique_to_persona)." },
    { key: "avg_tokens_per_invocation", label: "Avg tok", sortKind: "numeric", nullsLast: true,
      title: "Average tokens per Agent dispatch loading this persona. Use this for cost ranking — totals penalize frequently-run personas." },
    { key: "total_tokens",     label: "Total tok", sortKind: "numeric", nullsLast: true },
    { key: "last_artifact_created_at", label: "Last seen", sortKind: "date", nullsLast: true },
    { key: "_findings",        label: "Findings",  sortKind: null,      nullsLast: false },
  ];

  // Renderer-local sort state. Default: gate asc then persona asc (handled in
  // mergeRosterAndRankings — sortState=null means "use natural merged order").
  const sortState = { col: null, dir: "asc" };

  // --------------------------------------------------------------------------
  // Banners
  // --------------------------------------------------------------------------

  function renderPrivacyBanner() {
    // Verbatim copy from ux.md — keep aligned with empty-state's "Data is
    // gitignored locally" claim (depends on persona-rankings.jsonl staying in
    // .gitignore per A9).
    const div = document.createElement("div");
    div.className = "card banner-privacy";
    div.textContent =
      "ⓘ  Persona scores reflect this machine's MonsterFlow runs only. " +
      "Persona names and numbers below are visible in any screenshot — " +
      "review before sharing publicly. Data is gitignored locally.";
    return div;
  }

  function renderStaleBanner(maxLastSeen) {
    const days = daysSince(maxLastSeen);
    const dateStr = (maxLastSeen || "").slice(0, 10); // YYYY-MM-DD
    const div = document.createElement("div");
    div.className = "card banner-stale";
    div.textContent =
      "⏱  Last refreshed " + days + " days ago (" + dateStr + "). " +
      "Run /wrap-insights to update — figures below may not reflect recent runs.";
    return div;
  }

  function renderEmptyState(container, reason) {
    const div = document.createElement("div");
    div.className = "card banner-empty-state";
    if (reason === "bundles-not-loaded") {
      // No PII to leak — privacy banner intentionally omitted (per spec lock).
      div.textContent =
        "Persona Insights bundle scripts not found. Expected files: " +
        "dashboard/data/persona-roster.js + dashboard/data/persona-rankings-bundle.js. " +
        "Run /wrap-insights to populate, or check that the bundle scripts exist.";
    } else {
      // 'empty' — fresh-install (e12). Verbatim from ux.md.
      div.innerHTML =
        "No persona data yet. The table below shows the personas your " +
        "pipeline will measure once you run them. To populate:" +
        "<ol style=\"margin: 8px 0 8px 20px; padding: 0;\">" +
        "<li><code>/spec-review</code>, <code>/plan</code>, or <code>/check</code> on any feature</li>" +
        "<li><code>/wrap-insights</code></li>" +
        "</ol>" +
        "Cross-project aggregation is opt-in — see " +
        "<code>docs/specs/token-economics/spec.md</code> §Project Discovery.";
    }
    container.appendChild(div);
  }

  // --------------------------------------------------------------------------
  // Data merge
  // --------------------------------------------------------------------------

  function mergeRosterAndRankings(roster, rankings) {
    // Returns rows with row_type ∈ { 'data', 'never-run', 'deleted' }.
    // Rules:
    //   - For each (persona, gate) in roster:
    //       if rankings has matching row → row_type='data'
    //       else                          → row_type='never-run' (synthesized)
    //   - For each (persona, gate) in rankings NOT in roster → row_type='deleted'.
    //
    // Roster shape (from persona-roster.js, expected):
    //   [{ persona, gate }, ...]  OR  [{ name, gate }, ...]
    // We tolerate either key.

    const rankingsKey = (r) => r.persona + "::" + r.gate;
    const rankingsMap = new Map();
    for (const r of (rankings || [])) {
      rankingsMap.set(rankingsKey(r), r);
    }

    const rows = [];
    const seen = new Set();

    for (const entry of (roster || [])) {
      const persona = entry.persona || entry.name;
      const gate = entry.gate;
      if (!persona || !gate) continue;
      const k = persona + "::" + gate;
      seen.add(k);
      const matched = rankingsMap.get(k);
      if (matched) {
        rows.push(Object.assign({}, matched, { row_type: "data" }));
      } else {
        rows.push({
          row_type: "never-run",
          persona: persona,
          gate: gate,
          runs_in_window: 0,
          window_size: 45,
          cost_runs_in_window: 0,
          run_state_counts: null,
          total_tokens: null,
          judge_retention_ratio: null,
          downstream_survival_rate: null,
          uniqueness_rate: null,
          avg_tokens_per_invocation: null,
          last_artifact_created_at: null,
          contributing_finding_ids: [],
          truncated_count: 0,
          insufficient_sample: false,
        });
      }
    }

    for (const r of (rankings || [])) {
      const k = rankingsKey(r);
      if (!seen.has(k)) {
        rows.push(Object.assign({}, r, { row_type: "deleted" }));
      }
    }

    // Default sort: gate asc, persona asc. Stable across re-renders.
    rows.sort((a, b) => {
      if (a.gate !== b.gate) return a.gate < b.gate ? -1 : 1;
      if (a.persona !== b.persona) return a.persona < b.persona ? -1 : 1;
      return 0;
    });

    return rows;
  }

  // --------------------------------------------------------------------------
  // Sorting
  // --------------------------------------------------------------------------

  function sortValueFor(row, col) {
    switch (col.key) {
      case "_state":
        // Sort by dominant state name (alpha). Never-run + deleted naturally
        // group via prefix.
        if (row.row_type === "never-run") return "zz-never-run";
        if (row.row_type === "deleted")   return "zz-deleted";
        return dominantState(row.run_state_counts) || "complete_value";
      case "_runs":
        // Sort by runs_in_window (value window). null sinks regardless.
        return row.runs_in_window != null ? row.runs_in_window : null;
      case "_findings":
        return null; // not sortable
      default:
        return row[col.key];
    }
  }

  function compareRows(a, b, col, dir) {
    const va = sortValueFor(a, col);
    const vb = sortValueFor(b, col);

    // nulls-last regardless of direction (per ux + spec lock).
    const aNull = (va == null || va === "");
    const bNull = (vb == null || vb === "");
    if (aNull && bNull) return 0;
    if (aNull) return 1;
    if (bNull) return -1;

    let cmp;
    if (col.sortKind === "numeric") {
      cmp = Number(va) - Number(vb);
    } else {
      // alpha, date (ISO sorts lexically), state (string)
      cmp = va < vb ? -1 : va > vb ? 1 : 0;
    }
    return dir === "asc" ? cmp : -cmp;
  }

  function applySort(rows) {
    if (!sortState.col) return rows; // natural order
    const col = COLUMNS.find((c) => c.key === sortState.col);
    if (!col || !col.sortKind) return rows;
    const copy = rows.slice();
    copy.sort((a, b) => compareRows(a, b, col, sortState.dir));
    return copy;
  }

  // --------------------------------------------------------------------------
  // Per-cell renderers
  // --------------------------------------------------------------------------

  function colorBandClass(value, dimension) {
    if (value == null || isNaN(value)) return null;
    const t = BAND_THRESHOLDS[dimension];
    if (!t) return null;
    if (value < t.low)  return "band-low";
    if (value >= t.high) return "band-high";
    return "band-mid";
  }

  function dominantState(counts) {
    if (!counts || typeof counts !== "object") return null;
    let best = null;
    let bestCount = -1;
    // complete_value wins on ties (silent default).
    const keys = Object.keys(counts);
    // First pass: find max count.
    for (const k of keys) {
      const c = counts[k] || 0;
      if (c > bestCount) {
        bestCount = c;
        best = k;
      }
    }
    // Second pass: prefer complete_value on tie.
    if ((counts.complete_value || 0) === bestCount && bestCount > 0) {
      return "complete_value";
    }
    return bestCount > 0 ? best : null;
  }

  function tooltipForCounts(counts) {
    if (!counts || typeof counts !== "object") return "";
    const parts = [];
    for (const k of Object.keys(counts)) {
      const v = counts[k] || 0;
      if (v > 0) parts.push(k + ": " + v);
    }
    return parts.join(" · ");
  }

  function badgeForRow(row) {
    if (row.row_type === "never-run") {
      return '<span class="badge never-run" aria-label="never run this window">never run</span>';
    }
    if (row.row_type === "deleted") {
      return '<span class="badge deleted" aria-label="persona file deleted">deleted</span>';
    }
    const dom = dominantState(row.run_state_counts);
    const tooltip = tooltipForCounts(row.run_state_counts);
    if (!dom || dom === "complete_value") {
      // Silent default — no badge rendered. Provide hover affordance via the
      // row title attr (handled at <tr> level if desired). Return empty cell.
      return "";
    }
    const meta = STATE_BADGE[dom];
    if (!meta) return "";
    return '<span class="badge ' + meta.cls + '" title="' + escapeAttr(tooltip) +
      '" aria-label="' + escapeAttr(meta.text + ". " + tooltip) + '">' +
      escapeText(meta.text) + "</span>";
  }

  function renderHashChangedBadge(row) {
    // Heuristic for v1 — see plan decision #21 / Risk S3.
    // Without per-row hash history in the bundle, we approximate: if the
    // dominant state's count is less than half the runs_in_window AND the
    // row has data, the persona prompt may have changed mid-window.
    if (row.row_type !== "data") return "";
    const counts = row.run_state_counts || {};
    const total = (row.runs_in_window || 0);
    if (total < 4) return ""; // need a meaningful window to flag
    const top = (counts.complete_value || 0) + (counts.silent || 0);
    if (top < total / 2) {
      return ' <span class="badge yellow" title="Heuristic: dominant state covers <50% of window — persona prompt may have changed mid-window. Per-row hash history is v1.1+.">hash changed mid-window</span>';
    }
    return "";
  }

  function fmtRate(value, kind) {
    if (value == null) return { text: "—", band: null };
    if (kind === "percent") {
      return { text: Math.round(value * 100) + "%", band: null };
    }
    return { text: value.toFixed(2), band: null };
  }

  function fmtTokens(n) {
    if (n == null) return "—";
    if (n >= 1_000_000) return (n / 1_000_000).toFixed(1) + "M";
    if (n >= 1_000)     return (n / 1_000).toFixed(1) + "k";
    return String(n);
  }

  function fmtDate(iso) {
    if (!iso) return "—";
    return iso.slice(0, 10); // YYYY-MM-DD
  }

  function renderFindingsCell(row) {
    const ids = row.contributing_finding_ids || [];
    const trunc = row.truncated_count || 0;
    if (ids.length === 0 && trunc === 0) return "—";
    const summary = trunc > 0
      ? ids.length + " IDs (+" + trunc + " more)"
      : ids.length + " IDs";
    const list = ids.map((id) => "<li><code>" + escapeText(id) + "</code></li>").join("");
    return "<details><summary>" + escapeText(summary) + "</summary>" +
      "<ul style=\"margin: 4px 0 0 16px; padding: 0; font-size: 11px;\">" + list + "</ul></details>";
  }

  // --------------------------------------------------------------------------
  // Table
  // --------------------------------------------------------------------------

  function renderTable(rows) {
    const wrap = document.createElement("div");
    wrap.className = "card wide";

    const table = document.createElement("table");
    table.className = "persona-insights-table";

    // <thead>
    const thead = document.createElement("thead");
    const headRow = document.createElement("tr");
    for (const col of COLUMNS) {
      const th = document.createElement("th");
      th.textContent = col.label;
      if (col.title) th.title = col.title;
      if (col.sortKind) {
        th.style.cursor = "pointer";
        th.setAttribute("role", "button");
        th.setAttribute("tabindex", "0");
        const isActive = sortState.col === col.key;
        if (isActive) {
          th.textContent = col.label + (sortState.dir === "asc" ? " ▲" : " ▼");
        }
        const handler = () => {
          if (sortState.col === col.key) {
            sortState.dir = (sortState.dir === "asc") ? "desc" : "asc";
          } else {
            sortState.col = col.key;
            sortState.dir = "asc";
          }
          render();
        };
        th.addEventListener("click", handler);
        th.addEventListener("keydown", (e) => {
          if (e.key === "Enter" || e.key === " ") { e.preventDefault(); handler(); }
        });
      }
      headRow.appendChild(th);
    }
    thead.appendChild(headRow);
    table.appendChild(thead);

    // <tbody>
    const tbody = document.createElement("tbody");
    const sorted = applySort(rows);
    for (const row of sorted) {
      tbody.appendChild(renderRow(row));
    }
    table.appendChild(tbody);

    wrap.appendChild(table);
    return wrap;
  }

  function renderRow(row) {
    const tr = document.createElement("tr");
    if (row.insufficient_sample) {
      tr.classList.add("row-low-sample");
      tr.setAttribute("aria-label",
        "Insufficient sample, " + (row.runs_in_window || 0) + " runs of 3 minimum");
    }

    // Persona (strikethrough on deleted)
    const tdPersona = document.createElement("td");
    if (row.row_type === "deleted") {
      tdPersona.innerHTML = "<s>" + escapeText(row.persona) + "</s>";
    } else {
      tdPersona.textContent = row.persona;
    }
    tr.appendChild(tdPersona);

    // Gate
    const tdGate = document.createElement("td");
    tdGate.textContent = row.gate;
    tr.appendChild(tdGate);

    // State (badge + heuristic hash-changed advisory)
    const tdState = document.createElement("td");
    tdState.innerHTML = badgeForRow(row) + renderHashChangedBadge(row);
    tr.appendChild(tdState);

    // Runs — "value / cost" combined cell with two-window tooltip
    const tdRuns = document.createElement("td");
    if (row.row_type === "never-run") {
      tdRuns.textContent = "—";
      tdRuns.style.color = "var(--muted)";
    } else {
      const v = row.runs_in_window != null ? row.runs_in_window : "?";
      const c = row.cost_runs_in_window != null ? row.cost_runs_in_window : "?";
      tdRuns.textContent = v + " / " + c;
      tdRuns.title = "value-window: " + v + " directories; cost-window: " + c + " dispatches";
    }
    tr.appendChild(tdRuns);

    // Rate cells — render "—" when insufficient_sample OR null.
    const showRates = !row.insufficient_sample && row.row_type !== "never-run";

    tr.appendChild(renderRateCell(showRates ? row.judge_retention_ratio : null,    "decimal", "retention"));
    tr.appendChild(renderRateCell(showRates ? row.downstream_survival_rate : null, "percent", "survival"));
    tr.appendChild(renderRateCell(showRates ? row.uniqueness_rate : null,          "percent", "unique"));

    // Avg tok
    const tdAvg = document.createElement("td");
    if (row.row_type === "never-run" || row.insufficient_sample) {
      tdAvg.textContent = "—";
      tdAvg.style.color = "var(--muted)";
    } else {
      tdAvg.textContent = fmtTokens(row.avg_tokens_per_invocation);
    }
    tr.appendChild(tdAvg);

    // Total tok — kept full-clarity even on dimmed rows (numbers trustworthy).
    const tdTot = document.createElement("td");
    tdTot.textContent = fmtTokens(row.total_tokens);
    tr.appendChild(tdTot);

    // Last seen
    const tdLast = document.createElement("td");
    tdLast.textContent = fmtDate(row.last_artifact_created_at);
    if (!row.last_artifact_created_at) tdLast.style.color = "var(--muted)";
    tr.appendChild(tdLast);

    // Findings (collapsible)
    const tdFind = document.createElement("td");
    tdFind.innerHTML = renderFindingsCell(row);
    tr.appendChild(tdFind);

    return tr;
  }

  function renderRateCell(value, fmtKind, dimension) {
    const td = document.createElement("td");
    if (value == null) {
      td.textContent = "—";
      td.style.color = "var(--muted)";
      return td;
    }
    const f = fmtRate(value, fmtKind);
    td.textContent = f.text;
    const band = colorBandClass(value, dimension);
    if (band) td.classList.add(band);
    return td;
  }

  // --------------------------------------------------------------------------
  // Helpers
  // --------------------------------------------------------------------------

  function daysSince(iso) {
    if (!iso) return 0;
    const t = Date.parse(iso);
    if (isNaN(t)) return 0;
    const ms = Date.now() - t;
    return Math.floor(ms / (1000 * 60 * 60 * 24));
  }

  function escapeText(s) {
    return String(s == null ? "" : s)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;");
  }

  function escapeAttr(s) {
    return escapeText(s).replace(/"/g, "&quot;");
  }

  // --------------------------------------------------------------------------
  // Public entry
  // --------------------------------------------------------------------------

  function render() {
    const main = document.getElementById("main");
    const tabs = document.getElementById("tabs");
    if (tabs) tabs.innerHTML = "";
    if (!main) return;
    main.innerHTML = "";

    // Bundle-load failure: surface the empty-state without the privacy banner
    // (no PII to leak). __PERSONA_BUNDLES_LOADED is flipped to false by the
    // <script onerror> handlers in index.html.
    if (window.__PERSONA_BUNDLES_LOADED === false) {
      renderEmptyState(main, "bundles-not-loaded");
      const lu = document.getElementById("last-updated");
      if (lu) lu.textContent = "persona bundles missing";
      return;
    }

    const roster = window.PERSONA_ROSTER || [];
    const rankings = window.__PERSONA_RANKINGS || [];

    // Fresh-install (e12): no rankings yet. Show empty-state + table of
    // never-run rows (so adopters see what their pipeline will measure).
    if (rankings.length === 0) {
      renderEmptyState(main, "empty");
      const merged = mergeRosterAndRankings(roster, rankings);
      if (merged.length > 0) {
        main.appendChild(renderTable(merged));
      }
      const lu = document.getElementById("last-updated");
      if (lu) lu.textContent = "no persona data yet";
      return;
    }

    // Normal path: privacy banner first, optional stale banner, then table.
    main.appendChild(renderPrivacyBanner());

    const lastSeenValues = rankings
      .map((r) => r.last_artifact_created_at)
      .filter(Boolean)
      .sort();
    const maxLastSeen = lastSeenValues[lastSeenValues.length - 1];
    if (maxLastSeen && daysSince(maxLastSeen) > STALE_DAYS) {
      main.appendChild(renderStaleBanner(maxLastSeen));
    }

    const merged = mergeRosterAndRankings(roster, rankings);
    main.appendChild(renderTable(merged));

    const lu = document.getElementById("last-updated");
    if (lu) {
      lu.textContent = maxLastSeen
        ? "persona data through: " + maxLastSeen.slice(0, 10)
        : "persona data loaded";
    }
  }

  window.__renderPersonaInsightsView = render;
})();
