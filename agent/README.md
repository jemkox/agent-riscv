# The agent setup that built this CPU

This folder is the harness that let a local LLM work on the CPU unattended for
about 35 hours: what it was allowed to do, how it was kept going, and how its
claims were checked. These are the files that ran, generalized so anyone can
install them: paths, the session id and the model settings now come from one
config file instead of being written into the scripts.

```text
             PROMPT.md (task, milestones, rules)
                         |
                         v
 model server  --->  opencode server  <--- cpu-loop.js plugin (instant "continue", activity log)
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
| `install.sh`, `config.example` | Installs everything for the current user and writes `~/.config/cpu-agent/config` (workspace, project, model, finish line). |
| `bin/model-up`, `systemd/cpu-agent-model.service` | Makes sure the model server answers; starts it with `MODEL_CMD` if you set one. The original run used Qwen 3.8 Flash Next Coder 125B (IQ1_M) behind an OpenAI-compatible API; any llama.cpp-style server works. |
| `opencode/opencode.json.template` | Points [opencode](https://opencode.ai) at the local model and sets permissions: broad allow, with hard denies for disks, bootloader, `~/.ssh`, `~/.gnupg`, password files and the agent's own config. |
| `opencode/AGENTS.md` | Global rules for the agent: HDL tool usage, self-checking testbenches, "never claim a pass you did not see", act instead of narrating. |
| `opencode/agent/cpu.md` | The builder agent: one engineer working alone on the project, every reply must make a tool call, commit after each milestone, stop only at the finish line. |
| `bin/hdl` | The sandbox. Every HDL/RISC-V tool runs in bubblewrap: the whole system read-only, only `~/agent-workspace` writable, secret folders hidden, and the out-of-memory killer pointed at the tool, never at the model. |
| `opencode/plugin/cpu-loop.js` | Runs inside opencode. When the agent ends a turn with plain text (the model's most common way to stall), it sends "continue" within seconds, unless the agent said `TASK COMPLETE` / `NEED USER`, the user stopped it, the finish line is in PROGRESS.md, or 6 nudges in a row changed no file. Logs every tool call to an activity feed. |
| `bin/agent-watchdog` | A separate process that follows the same rules more slowly, in case the plugin or server dies. It also sends desktop and phone notifications: milestones, tests turning red or green, model down, no actions for 30 min, low disk, an hourly digest. |
| `bin/review-at-commit`, `opencode/agent/review.md`, `reviews/REVIEW_PROMPT.md` | The independent reviewer. After a builder commit (at most hourly) it pauses the builder, starts a fresh read-only agent on its own clone, runs 10 scripted checks and reads the diff, writes a report with a verdict, checks the builder's project was not touched, then resumes the builder with the fix list. |
| `bin/cpu-agent`, `bin/cpu-agent-serve`, `systemd/*.service` | Start/stop everything as systemd user services so it survives logouts and restarts itself. The first start creates the builder session and hands it `PROMPT.md`. |

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

Needs Linux with systemd, [opencode](https://opencode.ai) 1.x, `bwrap`
(bubblewrap), Python 3, git, curl, the HDL tools from the main README, and a
local OpenAI-compatible model server (for example llama.cpp's `llama-server`).

```sh
git clone https://github.com/jemkox/agent-riscv.git ~/agent-workspace/agent-riscv
cd ~/agent-workspace/agent-riscv && make deps
agent/install.sh --model-id <name your server reports> --context 131072 \
  --model-cmd "llama-server -m /path/to/model.gguf --port 8080 -c 131072"
cpu-agent start      # starts model, server, watchdog, reviewer; creates the builder session
cpu-agent activity   # live feed of every edit, test run and commit
cpu-agent stop
```

The agent works on the repo it was installed from, following `PROMPT.md` and
stopping at the `DONE_MARK` line in `PROGRESS.md` (both are this project's,
so to start a new run give it your own `PROMPT.md` and an empty
`PROGRESS.md`). The sandbox can only write inside the workspace folder.

Notes:

- The installer copies into `~/.local/bin`, `~/.config/opencode`,
  `~/.config/systemd/user` and `~/.config/cpu-agent`. An existing file with
  different content is kept as `<file>.before-cpu-agent`. It replaces
  opencode's global `opencode.json` and `AGENTS.md`, so use it on a machine or
  user account set aside for the agent.
- Phone notifications are optional: put an [ntfy](https://ntfy.sh) topic name
  in `~/.config/cpu-agent/ntfy-topic`.
- `sudo -A` inside the agent only works if you add your own askpass helper at
  `~/.local/bin/agent-sudo-askpass`; without one it fails and the agent carries
  on.
- Tested: the installer in a clean home folder (repo outside `~/agent-workspace`),
  then `cpu-agent start` against the real model with the systemd calls run
  directly: it created the builder session, the plugin logged the agent's
  commands, and the watchdog attached to the session. The reviewer loop was
  only syntax-checked in this setup; it ran for real during the original build.
