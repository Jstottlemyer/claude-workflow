### Key Considerations

**Threat model summary:** `/autorun` is a local, single-user, scheduled process. The realistic adversary is (a) malicious content in a `.spec.md` the user dropped or pulled from an untrusted source, (b) a compromised dependency, or (c) the user making a mistake the automation amplifies before it can be stopped.

**Surface inventory by severity:**

1. **Prompt injection via `queue/*.spec.md`** — High severity. Spec file content is interpolated directly into `claude -p "..."`. An adversary who writes to `queue/` can embed instructions that attempt to override the autonomy directive, exfiltrate `$GH_TOKEN` via `gh api` calls embedded in generated code, or suppress Stage 6 halt.

2. **Credential inheritance by all subprocesses** — Medium-High. `ANTHROPIC_API_KEY` and `GH_TOKEN` are in the environment of every child process: Claude agents, Codex, `gh`, any code Claude writes and executes inline. Codex `--full-auto --ephemeral` means Codex itself runs generated code autonomously.

3. **`autorun.config.json` in the repo** — Medium. `webhook_url` and `mail_to` are notification targets. If committed and repo becomes public, webhook URL is leaked.

4. **`/tmp/codex-autorun-review.txt`** — Low-Medium. macOS maps `/tmp` → per-user `$TMPDIR`, so world-readable concern is lower than on Linux, but worth using `$TMPDIR` explicitly.

5. **`git reset --hard` blast radius** — Medium. If rollback fires on a wave that has already pushed to remote and opened a PR, `reset --hard` on the local branch does not undo the remote push. Rollback is local-only.

6. **Kill-switch `queue/STOP`** — Low-Medium. Race-prone: if check happens between when a wave starts and when `STOP` is written, that wave completes.

7. **Auto-merge to `main` without human gate** — Design-level risk the user accepted.

8. **Branch protection bypass via `gh pr merge --squash`** — Low on a personal repo (no branch protection rules enforced).

9. **No audit trail** — Medium for forensic/recovery purposes. No structured event log means no easy "what did the autonomy directive decide at step 4."

---

### Options Explored

**A. Sanitize/scope spec content before interpolation**
- Strip or encode content between `--- CONTEXT:` and end-of-string; disallow injection markers.
- Cons: Blocklist is inherently incomplete. High effort for uncertain coverage.
- Effort: Medium.

**B. Separate autonomy directive from user-controlled content using structured message format**
- Pass the autonomy directive as a system prompt (`--system-prompt` or equivalent) and spec content as a separate `--user` message.
- Pros: Architectural defense, not a blocklist. Matches how Claude's safety guarantees are designed to work.
- Cons: Requires verifying `claude -p` supports `--system` flag.
- Effort: Low-Medium once flag is confirmed.

**C. Restrict `GH_TOKEN` scope for autorun**
- Create a dedicated GitHub fine-grained PAT scoped to: write to `autorun/*` branches only, create PRs, merge PRs on the specific repo.
- Pros: Limits blast radius if token is exfiltrated.
- Effort: Low (GitHub UI, ~10 min).

**D. Gitignore `autorun.config.json`**
- Trivial, no downside. Provide `autorun.config.json.example`.
- Effort: Trivial.

**E. Use `$TMPDIR` instead of `/tmp`**
- macOS per-user temp. Belt-and-suspenders.
- Effort: Trivial.

**F. Structured run log with wave-level records**
- `run.sh` appends JSON lines to `queue/run.log` (gitignored): `{timestamp, slug, stage, exit_code, finding_summary}`. Each auto-merge appended with commit SHA.
- Effort: Low.

**G. Kill-switch hardening: atomic check**
- Check `queue/STOP` using an atomic test. Shell `flock` or PID lockfile.
- Effort: Low-Medium.

---

### Recommendation

**Must-do before shipping:**

1. **Option D** — gitignore `autorun.config.json` immediately.
2. **Option B** — validate whether `claude -p` supports `--system` separation. Add to spike test list.
3. **Option C** — create a scoped `AUTORUN_GH_TOKEN` distinct from the general `GH_TOKEN`. Name it distinctly in `~/.zshenv.local` so `run.sh` exports `GH_TOKEN=$AUTORUN_GH_TOKEN` only for its subprocess tree.
4. **Option E** — replace `/tmp/` with `$TMPDIR/`.

**Strongly recommended:**

5. **Option F** — structured run log. The user accepted no human gate; the quid pro quo should be a reliable audit trail.
6. **Option G** — atomic kill-switch check.

**Accept as known risk:**

- Auto-merge to `main` — user explicitly accepted. Document in `commands/autorun.md`.
- `git reset --hard` local-only scope — document that rollback does not undo remote pushes; remote cleanup is manual.

---

### Constraints Identified

- **LaunchAgent user-scope constraint is correct and must not be relaxed.** Running as a LaunchDaemon (root) would give the agent root-level `GH_TOKEN` and filesystem access.
- **`~/.zshenv.local` chmod 600 is already implemented** — no change needed.
- **Codex `--full-auto` is a Codex design choice, not configurable here.** Document what it means in plan.

---

### Open Questions

1. Does `claude -p` support a `--system` flag or equivalent for separating system-prompt from user-message? **Critical for the spike.**
2. Should `autorun/<slug>` branches be deleted post-merge? They accumulate on remote otherwise.
3. Does Stage 6 halt logic check the Codex exit code, or parse the review text? If it parses text, a prompt injection altering review output could suppress the halt.
4. Should `queue/run.log` be gitignored or committed? Recommend gitignore + local-only.
5. Is `autorun.config.json` read once at startup or re-read each wave? Should be read once.

---

### Integration Points with Other Dimensions

- **Architecture/Orchestration:** Option B (prompt-injection defense) requires the orchestration layer to split system prompt from user content at command-construction time.
- **Developer Experience:** A scoped `AUTORUN_GH_TOKEN` means install/setup docs need a "create this PAT" step.
- **Reliability/Rollback:** "reset --hard is local-only" means the reliability dimension needs a recovery runbook.
- **Observability:** Structured run log (Option F) is the primary observability artifact; schema and rotation policy need to be defined.
- **Codex integration:** The `--full-auto` semantics question (Open Question 3) directly affects whether Stage 6 halt logic is trustworthy.
