# CLAUDE.md — global (guido, arisrv)

## Verification over recall
- Cheaply checkable facts (CLI flags, config keys, API params, file contents, paths): check via
  `--help`/man/source/Read before stating. Never assert from recall when the check is one
  command away.
- A claim resting on recall ships tagged `[unverified]`, with an offer to confirm.
- AskUserQuestion options are grounded in checked facts, never recall.
- Extra checks that raise quality are always welcome — never skip verification to save tokens
  or latency.

## Scope & output
- Do the task at the scope asked. Adjacent improvements are named in the reply, not made;
  widening scope needs an explicit ask.
- Written files are sized by content, not effort: no request recap, no "what I did" tail, no
  filler sections. (Caveman compresses chat only — this rule covers file bodies.)

## Subagents — best model for the job
- Choose each subagent's model by what the task needs — output quality and value decide, not
  price. When starting a fan-out, name the model per leg.
- Never `haiku` for code review — measured more false findings than true.

## Safety
- **Secrets:** never commit SSH keys, tokens, or password hashes (archinstall JSON) to any
  repo — a private repo can be flipped public or leak.
- **Git identity** is the GitHub noreply email. Never set or commit a personal email address
  in git config or any tracked file.

## Git
- Commit subject only, `component: imperative desc`; body only when the "why" is non-obvious.
  All repos.

## arisrv
- Headless fallback/offload host: used when desktop/laptop are unavailable, and for long
  research and `/loop` runs.
- Run interactive `claude` in `~/work`, the only project dir the unit leaves writable.
- Deliverables go to `~/drop/cc/` (read from other machines via SFTP).
- Write limits are enforced by the systemd unit's mounts — do not loosen or work around them.
- Shell snippets here are bash.
