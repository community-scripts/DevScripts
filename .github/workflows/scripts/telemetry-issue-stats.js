// Posts (or updates) one telemetry comment on every open script issue.
//
// Called from telemetry-issue-stats.yml through actions/github-script:
//   await require('./.github/workflows/scripts/telemetry-issue-stats.js')({ github, context, core })
//
// Data comes from the public telemetry service (community-scripts/services,
// cmd/telemetry), filtered to runs whose repo_source is DevScripts. The window
// starts at the day the issue was opened, so a test issue counts the runs made
// while it was open, not an older script of the same name.

const fs = require("fs");

const API = (process.env.TELEMETRY_API || "https://telemetry.community-scripts.org").replace(/\/$/, "");
const REPO_SOURCE = "DevScripts";
const MARKER = "<!-- telemetry-stats -->";
const MAX_CAUSES = 5;
const MAX_DAYS = 365;

// Stale check, both counted since the issue was opened; issues younger than
// STALE_MIN_AGE days are not checked yet:
//  - fewer than STALE_MIN_SUCCESS successful installs in the last STALE_WINDOW
//    days, unless it already has more than STALE_SKIP_TOTAL installs;
//  - more than STALE_RATE_MIN_TOTAL installs and a success rate below
//    STALE_MIN_RATE %, however many installs it has.
const STALE_LABEL = "stale";
const STALE_MARKER = "<!-- telemetry-stale -->";
const STALE_MIN_AGE = 14;
const STALE_WINDOW = 7;
const STALE_MIN_SUCCESS = 15;
const STALE_SKIP_TOTAL = 100;
const STALE_RATE_MIN_TOTAL = 50;
const STALE_MIN_RATE = 75;
const STALE_ONLY = "Ready For Testing";
const STALE_EXEMPT = ["keep-open", "Migration To ProxmoxVE", "Started Migration To ProxmoxVE"];

// Same slug rule as push_json_to_pocketbase.yml / pr-merged-ready-for-testing.yml:
// the "Name of the Script" field, else the title, lowercased, spaces -> dashes.
const slugify = (s) => (s || "").replace(/\r/g, "").trim().toLowerCase().replace(/\s+/g, "-");
function issueSlug(issue) {
  const m = (issue.body || "")
    .replace(/\r/g, "")
    .match(/^###[ \t]*Name of the Script[ \t]*\n+([^\n#][^\n]*)/m);
  return slugify(m ? m[1] : issue.title);
}

// The telemetry key (nsapp) is not always the slug: a CT reports APP lowercased
// with spaces removed ("Bluesky PDS" -> "blueskypds"), a VM or tool may set its
// own name. Read it from the script, then fall back to the slug forms.
function telemetryKeys(slug) {
  const keys = [];
  const add = (k) => {
    k = (k || "").trim();
    if (k && /^[a-z0-9._-]+$/.test(k) && !keys.includes(k)) keys.push(k);
  };

  // "Rocket.Chat" -> "rocket.chat", but its files are json/rocketchat.json, ct/rocketchat.sh.
  const bases = [...new Set([slug, slug.replace(/[^a-z0-9]/g, "")])];
  const scripts = [];
  for (const base of bases) {
    try {
      const data = JSON.parse(fs.readFileSync(`json/${base}.json`, "utf8"));
      (data.install_methods || []).forEach((im) => im.script && scripts.push(im.script));
    } catch {
      // Not merged yet, or no JSON: guess the usual locations.
    }
    scripts.push(`ct/${base}.sh`, `vm/${base}.sh`, `tools/addon/${base}.sh`, `tools/pve/${base}.sh`);
  }

  for (const path of scripts) {
    let text;
    try {
      text = fs.readFileSync(path, "utf8");
    } catch {
      continue;
    }
    add((text.match(/^NSAPP="([^"$]+)"/m) || [])[1]);
    add((text.match(/init_tool_telemetry\s+"([^"$]+)"/) || [])[1]);
    add((text.match(/post_addon_to_api\s+"([^"$]+)"/) || [])[1]);
    const app = (text.match(/^APP="([^"$]+)"/m) || [])[1];
    if (app) add(app.toLowerCase().replace(/\s+/g, ""));
  }
  bases.forEach(add);
  add(slug.replace(/-/g, ""));
  return keys;
}

async function fetchDetail(app, days) {
  const q = new URLSearchParams({ app, repo: REPO_SOURCE, days: String(days) });
  const res = await fetch(`${API}/api/script-detail?${q}`, { headers: { Accept: "application/json" } });
  if (!res.ok) throw new Error(`script-detail ${app}: HTTP ${res.status} ${(await res.text()).slice(0, 200)}`);
  return res.json();
}

const n = (v) => Number(v || 0).toLocaleString("en-US");
const pct = (v) => `${Number(v || 0).toFixed(1)}%`;
const esc = (s) =>
  String(s || "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/\|/g, "&#124;")
    .replace(/\s+/g, " ")
    .trim();
const clip = (s, max) => (s.length > max ? s.slice(0, max - 1) + "…" : s);
// Success rate over every finished run: aborted and no-result runs count as
// failures (the API's success_rate leaves them out). null when nothing ran.
function successRate(d) {
  const runs = (d.success || 0) + (d.failed || 0) + (d.aborted || 0) + (d.no_result || 0);
  return runs ? ((d.success || 0) / runs) * 100 : null;
}
const day = (iso) => (iso ? iso.slice(0, 16).replace("T", " ") + " UTC" : "—");

// Most recent run of any status: `recent` lists the runs (aborted ones too),
// last_success / last_failure are the fallback.
function lastRun(d) {
  const runs = (d.recent || [])
    .map((r) => ({ t: new Date(r.started_at), status: r.status }))
    .filter((r) => !isNaN(r.t));
  if (runs.length) return runs.reduce((a, b) => (b.t > a.t ? b : a));
  const times = [d.last_success, d.last_failure].filter(Boolean).map((t) => new Date(t)).filter((t) => !isNaN(t));
  return times.length ? { t: new Date(Math.max(...times)) } : null;
}

// "13.11.2026 at 14:05 UTC (2 days 3 hours ago)"
function ago(t) {
  const p = (v) => String(v).padStart(2, "0");
  const when = `${p(t.getUTCDate())}.${p(t.getUTCMonth() + 1)}.${t.getUTCFullYear()} at ${p(t.getUTCHours())}:${p(t.getUTCMinutes())} UTC`;
  const mins = Math.max(0, Math.floor((Date.now() - t.getTime()) / 60000));
  const unit = (v, s) => `${v} ${s}${v === 1 ? "" : "s"}`;
  const days = Math.floor(mins / 1440), hours = Math.floor((mins % 1440) / 60);
  const rel = days ? `${unit(days, "day")} ${unit(hours, "hour")}`
    : hours ? `${unit(hours, "hour")} ${unit(mins % 60, "minute")}`
    : unit(mins, "minute");
  return `${when} (${rel} ago)`;
}

function renderEmpty(app, since) {
  return [
    MARKER,
    `### 📊 Install telemetry for \`${app}\``,
    "",
    `No installs of the DevScripts version of this script reported yet since this issue was opened (${since}).`,
    "",
    `<sub>updated hourly · last refresh ${new Date().toISOString().slice(0, 16).replace("T", " ")} UTC</sub>`,
  ].join("\n");
}

function render(d, app, days, since) {
  // The dashboard only offers these periods.
  const period = [1, 7, 30, 90, 365].find((p) => p >= days) || 365;
  const link = `${API}/script-analysis?${new URLSearchParams({ repo: REPO_SOURCE, days: String(period), app })}`;
  const lines = [
    MARKER,
    `### 📊 Install telemetry for \`${app}\``,
    "",
    `Runs reported by the DevScripts version of this script since this issue was opened (${since}).`,
    "",
    "| Installs | ✅ Successful | ❌ Failed | ⏹️ Aborted | ❔ No result | Success rate |",
    "| ---: | ---: | ---: | ---: | ---: | ---: |",
    `| ${n(d.total)} | ${n(d.success)} | ${n(d.failed)} | ${n(d.aborted)} | ${n(d.no_result)} | ${successRate(d) == null ? "—" : pct(successRate(d))} |`,
    "",
  ];
  const last = lastRun(d);
  if (last) lines.push(`**Last run:** ${ago(last.t)}${last.status ? ` · ${clip(esc(last.status), 40)}` : ""}`, "");
  lines.push(
    `Last success: ${day(d.last_success)} · Last failure: ${day(d.last_failure)}` +
      (d.avg_duration ? ` · Avg. install time: ${Math.round(d.avg_duration / 60)} min` : ""),
  );

  const causes = (d.causes || []).slice(0, MAX_CAUSES);
  if (causes.length) {
    lines.push(
      "",
      `#### Failures by cause${(d.causes || []).length > MAX_CAUSES ? ` (top ${MAX_CAUSES})` : ""}`,
      "",
      "| Count | Exit code | Error | Last seen |",
      "| ---: | --- | --- | --- |",
    );
    for (const c of causes) {
      const exit = c.exit_code != null ? `\`${c.exit_code}\` ${esc(c.exit_description)}` : "—";
      let msg = `<code>${clip(esc(c.message || c.key), 300)}</code>`;
      if (c.example_message && c.example_message !== c.message) msg += `<br>${clip(esc(c.example_message), 300)}`;
      lines.push(`| ${n(c.failures)} | ${exit} | ${msg} | ${day(c.last_seen)} |`);
    }
  }

  lines.push(
    "",
    `<sub>[Open in the telemetry dashboard](${link}) · updated hourly · last refresh ${new Date().toISOString().slice(0, 16).replace("T", " ")} UTC</sub>`,
  );
  return lines.join("\n");
}

// The refresh time changes every run; compare without it so an unchanged
// comment is not edited every hour.
const stable = (body) => (body || "").replace(/ · last refresh [^<]*<\/sub>/, "</sub>");

function staleNotice(app, reasons) {
  return [
    STALE_MARKER,
    `⚠️ **Marked as stale.** \`${app}\` since this issue was opened:`,
    "",
    ...reasons.map((r) => `- ${r}`),
    "",
    "This issue will be closed due to lack of testing 7 days after this label, unless it recovers first: the label is removed again automatically once the script has " +
      `${STALE_MIN_SUCCESS} successful installs in ${STALE_WINDOW} days (or more than ${STALE_SKIP_TOTAL} installs in total) ` +
      `and, past ${STALE_RATE_MIN_TOTAL} installs, a success rate of at least ${STALE_MIN_RATE}% ` +
      "(aborted and no-result runs count as failed). Maintainers can add `keep-open` to skip this check.",
  ].join("\n");
}

// Adds or removes the stale label for one issue. Returns what it did.
async function checkStale({ github, owner, repo, issue, comments, key, d, created, dryRun, core }) {
  const total = d.total || 0;
  const labels = (issue.labels || []).map((l) => (typeof l === "string" ? l : l.name));
  const hasStale = labels.includes(STALE_LABEL);
  // Anyone can paste the marker; only the workflow's own comment counts.
  const ourNotice = comments.some((c) => c.user?.login === "github-actions[bot]" && (c.body || "").startsWith(STALE_MARKER));
  const ageDays = (Date.now() - created.getTime()) / 86400000;

  const eligible = labels.includes(STALE_ONLY) && !labels.some((l) => STALE_EXEMPT.includes(l)) && ageDays >= STALE_MIN_AGE;
  const reasons = [];
  if (eligible && total <= STALE_SKIP_TOTAL) {
    const success7 = (await fetchDetail(key, STALE_WINDOW)).success || 0;
    if (success7 < STALE_MIN_SUCCESS) {
      reasons.push(`only ${success7} successful install(s) in the last ${STALE_WINDOW} days (${STALE_MIN_SUCCESS} needed), ${total} install(s) in total`);
    }
  }
  const rate = successRate(d);
  if (eligible && total > STALE_RATE_MIN_TOTAL && rate != null && rate < STALE_MIN_RATE) {
    reasons.push(`success rate ${pct(rate)} over ${total} installs (${STALE_MIN_RATE}% needed)`);
  }
  const tooLittle = reasons.length > 0;

  const tag = `#${issue.number} (${key})`;
  if (tooLittle && !hasStale) {
    if (dryRun) {
      core.info(`${tag}: would be marked stale: ${reasons.join("; ")}.`);
    } else {
      await github.rest.issues.addLabels({ owner, repo, issue_number: issue.number, labels: [STALE_LABEL] });
      await github.rest.issues.createComment({ owner, repo, issue_number: issue.number, body: staleNotice(key, reasons) });
      core.info(`${tag}: marked stale: ${reasons.join("; ")}.`);
    }
    return "marked";
  }
  // Only lift a label this workflow set; a maintainer's own stale label stays.
  if (!tooLittle && hasStale && ourNotice) {
    if (dryRun) {
      core.info(`${tag}: stale label would be removed.`);
    } else {
      await github.rest.issues.removeLabel({ owner, repo, issue_number: issue.number, name: STALE_LABEL });
      core.info(`${tag}: stale label removed.`);
    }
    return "unmarked";
  }
  return null;
}

module.exports = async function ({ github, context, core }) {
  const { owner, repo } = context.repo;
  const only = Number(process.env.ISSUE_NUMBER || 0);
  const dryRun = process.env.DRY_RUN === "true";

  let issues;
  if (only) {
    const { data } = await github.rest.issues.get({ owner, repo, issue_number: only });
    issues = [data];
  } else {
    issues = await github.paginate(github.rest.issues.listForRepo, { owner, repo, state: "open", per_page: 100 });
  }
  issues = issues.filter((i) => !i.pull_request);
  core.info(`${issues.length} issue(s) to check.`);

  const stats = { created: 0, updated: 0, unchanged: 0, skipped: 0, failed: 0, marked: 0, unmarked: 0 };

  for (const issue of issues) {
    const slug = issueSlug(issue);
    if (!/^[a-z0-9][a-z0-9._-]*$/.test(slug)) {
      core.info(`#${issue.number}: no usable slug ("${slug}"), skipped.`);
      stats.skipped++;
      continue;
    }

    try {
      const created = new Date(issue.created_at);
      const days = Math.min(MAX_DAYS, Math.max(1, Math.ceil((Date.now() - created.getTime()) / 86400000) + 1));

      // Pick the key with the most runs: the one the script really reports under.
      let best = null;
      for (const key of telemetryKeys(slug)) {
        const d = await fetchDetail(key, days);
        if (!best || (d.total || 0) > (best.d.total || 0)) best = { key, d };
      }

      const comments = await github.paginate(github.rest.issues.listComments, {
        owner, repo, issue_number: issue.number, per_page: 100,
      });
      const existing = comments.find((c) => (c.body || "").startsWith(MARKER));

      const since = created.toISOString().slice(0, 10);
      // No runs on any key: the first key is the one read from the script, if any.
      const body = best && best.d.total
        ? render(best.d, best.key, days, since)
        : renderEmpty(best ? best.key : slug, since);

      const staleResult = await checkStale({
        github, owner, repo, issue, comments, core, dryRun, created,
        key: best ? best.key : slug, d: best ? best.d : {},
      });
      if (staleResult) stats[staleResult]++;

      if (existing && stable(existing.body) === stable(body)) {
        core.info(`#${issue.number} (${slug} -> ${best.key}): unchanged.`);
        stats.unchanged++;
        continue;
      }

      const action = existing ? "updated" : "created";
      if (dryRun) {
        core.info(`#${issue.number} (${slug} -> ${best.key}): would be ${action}, ${best.d.total} run(s):\n${body}`);
      } else {
        if (existing) await github.rest.issues.updateComment({ owner, repo, comment_id: existing.id, body });
        else await github.rest.issues.createComment({ owner, repo, issue_number: issue.number, body });
        core.info(`#${issue.number} (${slug} -> ${best.key}): ${action}, ${best.d.total} run(s).`);
      }
      stats[action]++;
    } catch (e) {
      core.warning(`#${issue.number} (${slug}): ${e.message}`);
      stats.failed++;
    }
  }

  core.info(`Done: ${JSON.stringify(stats)}`);
  await core.summary
    .addHeading("Telemetry issue comments")
    .addTable([
      [{ data: "Created", header: true }, { data: "Updated", header: true }, { data: "Unchanged", header: true },
        { data: "Skipped", header: true }, { data: "Failed", header: true }, { data: "Marked stale", header: true },
        { data: "Stale removed", header: true }],
      [String(stats.created), String(stats.updated), String(stats.unchanged), String(stats.skipped), String(stats.failed),
        String(stats.marked), String(stats.unmarked)],
    ])
    .write();
  if (stats.failed && stats.failed === issues.length - stats.skipped) {
    core.setFailed("Every issue with a slug failed; is the telemetry service reachable?");
  }
};
