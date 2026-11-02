# The agent setup that built this CPU

This folder is the harness that let a local LLM work on the CPU unattended for
about 35 hours: what it was allowed to do, how it was kept going, and how its
claims were checked. The files are the ones that ran, with personal details
(home path, session id, disk names) replaced by placeholders.

```text
             PROMPT.md (task, milestones, rules)
                         |
                         v
 strata-model  --->  opencode server  <--- cpu-loop.js plugin (instant "continue", activity log)
 (local LLM,         (agent "cpu")     <--- agent-watchdog    (slow safety net, notifications)
  127.0.0.1:8080)        |             <--- review-at-commit  (pauses builder, runs reviewer)
                         | every tool run
                         v
                  hdl  (bubblewrap sandbox: Verilator, Yosys, nextpnr, riscv-gcc, sby)
                         |
                         v
              git commits + PROGRESS.md   --->  reviewer agent "review" (read-only, fresh clone)
                                                 -> reviews/rv32cpu-<commit>.md + fix list
```

## The pieces

| File | Role |
|---|---|
| `bin/strata-model-up`, `systemd/strata-model.service` | Starts the local model (Qwen 3.8 Flash Next Coder 125B, IQ1_M) behind an OpenAI-compatible API on 127.0.0.1:8080. Any llama.cpp-style server works. |
| `opencode/opencode.json` | Points [opencode](https://opencode.ai) at the local model and sets permissions: broad allow, with hard denies for disks, bootloader, `~/.ssh`, `~/.gnupg`, password files and the agent's own config. |
| `opencode/AGENTS.md` | Global rules for the agent: HDL tool usage, self-checking testbenches, "never claim a pass you did not see", act instead of narrating. |
| `opencode/agent/cpu.md` | The builder agent: one engineer working alone on the project, every reply must make a tool call, commit after each milestone, stop only at the finish line. |
| `bin/hdl` | The sandbox. Every HDL/RISC-V tool runs in bubblewrap: the whole system read-only, only `~/agent-workspace` writable, secret folders hidden, and the out-of-memory killer pointed at the tool, never at the model. |
| `opencode/plugin/cpu-loop.js` | Runs inside opencode. When the agent ends a turn with plain text (the model's most common way to stall), it sends "continue" within seconds, unless the agent said `TASK COMPLETE` / `NEED USER`, the user stopped it, the finish line is in PROGRESS.md, or 6 nudges in a row changed no file. Logs every tool call to an activity feed. |
| `bin/agent-watchdog` | A separate process that follows the same rules more slowly, in case the plugin or server dies. It also sends desktop and phone notifications: milestones, tests turning red or green, model down, no actions for 30 min, low disk, an hourly digest. |
| `bin/review-at-commit`, `opencode/agent/review.md`, `reviews/REVIEW_PROMPT.md` | The independent reviewer. After a builder commit (at most hourly) it pauses the builder, starts a fresh read-only agent on its own clone, runs 10 scripted checks and reads the diff, writes a report with a verdict, checks the builder's project was not touched, then resumes the builder with the fix list. |
| `bin/cpu-agent`, `bin/cpu-agent-serve`, `systemd/*.service` | Start/stop everything as systemd user services so it survives logouts and restarts itself. |

## The reviewer works: three real reports

The `reviews/` folder holds three reports the reviewer agent wrote during the
build, unedited apart from the home path:

- **52890e2: PASS WITH ISSUES.** All claims reproduced, but it found that the
  commit's debug output broke `make m7`, a suite that had to stay green.
- **b9139f6: PASS WITH ISSUES.** It caught a hard-coded `/home` path, a
  testbench that was claimed but never committed, and a metric that could not
  come from the quoted numbers.
- **c006154: FAIL.** The commit claimed `ALL MI PASS`. In a fresh clone the
  official `instret_overflow` test failed, because that same commit had
  deleted a counter carry from the simulation build. The builder fixed it from
  the fix list.

These are the failure modes that matter when an LLM does engineering work:
claims that are not true, tests quietly weakened, shortcuts that make a number
look good. The setup assumes they will happen and checks for them.

## Using it yourself

The scripts assume `~/agent-workspace` as the workspace and opencode 1.x.
Replace `ses_BUILDER_SESSION_ID` with your builder's session id and
`/home/USER` with your home path, copy `bin/` to `~/.local/bin`,
`opencode/` into `~/.config/opencode`, and `systemd/` to
`~/.config/systemd/user`. Optional phone notifications go to an
[ntfy](https://ntfy.sh) topic read from `~/.config/cpu-agent/ntfy-topic`
(not included). `cpu-agent-serve` points `SUDO_ASKPASS` at a password pop-up
script that is not included; without it, `sudo -A` simply fails and the agent
continues without installing packages.

`systemd/cpu-agent-server.service` and `cpu-agent-watchdog.service` were
written afresh for this folder from the scripts they run; the original unit
files were not kept.
