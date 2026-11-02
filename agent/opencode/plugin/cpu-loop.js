// agent loop: keeps whichever session is currently running working, and logs what it does.
//  - Active session: the session that most recently started working. Only that one is ever nudged.
//  - Instant continue: when the active session goes idle, it is nudged after a few seconds with its own
//    agent, unless its last reply ends with TASK COMPLETE or NEED USER, the user aborted it (Esc), the CPU
//    project's PROGRESS.md says FINAL ACCEPTANCE: MET, or MAX_NO_PROGRESS nudges in a row changed no file.
//    (The external agent-watchdog follows the same rules as a slower safety net.)
//  - Activity feed: every finished tool call becomes one line in ~/agent-workspace/.agent-logs/activity.log
//    (time, session, tool, file/command, test result); the latest state goes to activity.json for the app.
//  - Compaction: asks the summary to keep the task state and end with the exact next action.
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

const CPU_SESSION = "ses_BUILDER_SESSION_ID";
const HOME = os.homedir();
const CPU_PROJECT = path.join(HOME, "agent-workspace/hdl/rv32cpu");
const CPU_DONE_MARK = "DOOM CPU: DONE"; // the current goal's finish line in PROGRESS.md
const LOGDIR = path.join(HOME, "agent-workspace/.agent-logs");
const ACTIVITY = path.join(LOGDIR, "activity.log");
const STATE = path.join(LOGDIR, "activity.json");
const NUDGE_DELAY_MS = 8000;
const MAX_NO_PROGRESS = 6;
const STOP_RE = /^\s*(TASK COMPLETE|NEED USER:.*)\s*$/im;
const NUDGE =
  "Continue. Make a tool call now and work on the next unfinished step (no chat summaries). " +
  "If the task is fully done, end with the line TASK COMPLETE.";
const RESULT_RE = /(ALL PASS|ALL UI PASS|TEST PASSED[^\n]*|TEST FAILED[^\n]*|%Error[^\n]*|error:[^\n]*|Max frequency[^\n]*|Number of cells[^\n]*|FAIL[^\n]*)/i;

let active = null; // session that most recently started working
const busy = new Map();
const noProgress = new Map();
const stopLogged = new Map();
let timer = null;

const stamp = () => new Date().toTimeString().slice(0, 8);
const tag = (sid) => (sid === CPU_SESSION ? "cpu" : String(sid).slice(-5));

function log(sid, line) {
  try {
    fs.mkdirSync(LOGDIR, { recursive: true });
    fs.appendFileSync(ACTIVITY, `${stamp()}  [${tag(sid)}] ${line}\n`);
    fs.writeFileSync(STATE, JSON.stringify({ time: stamp(), session: sid, last: line, noProgress: noProgress.get(sid) || 0 }));
  } catch {}
}

function short(s, n = 90) {
  s = String(s ?? "").replace(/\s+/g, " ").trim();
  return s.length > n ? s.slice(0, n - 1) + "…" : s;
}

const rel = (p) => String(p ?? "").replace(CPU_PROJECT + "/", "").replace(HOME, "~");

function cpuFinished() {
  try {
    // only a line that is exactly the marker counts; the agent also mentions it in its notes
    const mark = new RegExp("^\\s*" + CPU_DONE_MARK.replace(/[.*+?^${}()|[\]\\]/g, "\\$&") + "\\s*$", "m");
    return mark.test(fs.readFileSync(path.join(CPU_PROJECT, "PROGRESS.md"), "utf8"));
  } catch {
    return false;
  }
}

function describe(tool, a, output) {
  a = a || {};
  if (tool === "bash") {
    const m = String(output ?? "").match(RESULT_RE);
    const tail = String(output ?? "").trim().split("\n").filter(Boolean).pop() || "";
    return `run   ${short(a.command, 70)}  →  ${short(m ? m[0] : tail, 70)}`;
  }
  if (["edit", "multiedit", "patch"].includes(tool)) return `edit  ${rel(a.filePath || a.path)}`;
  if (tool === "write") return `write ${rel(a.filePath || a.path)}`;
  if (tool === "read") return `read  ${rel(a.filePath || a.path)}`;
  if (tool === "grep" || tool === "glob") return `${tool.padEnd(5)} ${short(a.pattern, 60)}`;
  return `${tool.padEnd(5)} ${short(JSON.stringify(a), 70)}`;
}

export const CpuLoop = async ({ serverUrl }) => {
  const api = (p, body) =>
    fetch(new URL(p, serverUrl), body ? { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(body) } : {});

  // Why the session should not be nudged, or null if it should.
  async function stopReason(sid) {
    if (sid === CPU_SESSION && cpuFinished()) return `${CPU_DONE_MARK} in PROGRESS.md`;
    if ((noProgress.get(sid) || 0) >= MAX_NO_PROGRESS) return `${MAX_NO_PROGRESS} nudges without a file edit or commit (needs a look)`;
    const msgs = await (await api(`/session/${sid}/message?limit=1`)).json();
    const last = msgs[msgs.length - 1];
    if (!last || last.info.role !== "assistant") return null;
    if (last.info.error && /abort/i.test(last.info.error.name || "")) return "stopped by the user";
    const text = (last.parts || []).filter((p) => p.type === "text").map((p) => p.text).join("\n");
    const m = text.match(STOP_RE);
    return m ? `agent said: ${short(m[1], 80)}` : null;
  }

  async function lastAgent(sid) {
    const msgs = await (await api(`/session/${sid}/message?limit=6`)).json();
    for (let i = msgs.length - 1; i >= 0; i--) if (msgs[i].info.role === "user" && msgs[i].info.agent) return msgs[i].info.agent;
    return undefined;
  }

  async function nudge(sid) {
    timer = null;
    if (sid !== active || busy.get(sid)) return;
    try {
      const why = await stopReason(sid);
      if (why) {
        if (stopLogged.get(sid) !== why) log(sid, `not continuing: ${why}`);
        stopLogged.set(sid, why);
        return;
      }
      stopLogged.delete(sid);
      const n = (noProgress.get(sid) || 0) + 1;
      noProgress.set(sid, n);
      const agent = await lastAgent(sid);
      const res = await api(`/session/${sid}/prompt_async`, { ...(agent ? { agent } : {}), parts: [{ type: "text", text: NUDGE }] });
      log(sid, `nudge (idle; no-progress ${n}/${MAX_NO_PROGRESS})${res.ok ? "" : " failed: HTTP " + res.status}`);
    } catch (e) {
      log(sid, `nudge failed: ${e}`);
    }
  }

  return {
    event: async ({ event }) => {
      const sid = event?.properties?.sessionID;
      if (!sid) return;
      if (event.type === "session.status") {
        const isBusy = event.properties.status?.type !== "idle";
        busy.set(sid, isBusy);
        if (isBusy) {
          active = sid;
          if (timer) clearTimeout(timer), (timer = null);
        }
      } else if (event.type === "session.idle") {
        busy.set(sid, false);
        if (sid === active && !timer) timer = setTimeout(() => nudge(sid), NUDGE_DELAY_MS);
      } else if (event.type === "session.compacted") {
        log(sid, "context compacted");
      }
    },
    "chat.message": async (input, output) => {
      // A real user message (not one of the automatic "Continue..." nudges) resets the no-progress counter.
      const text = (output?.parts || []).filter((p) => p.type === "text").map((p) => p.text).join(" ");
      if (input?.sessionID && !/^Continue[. ]/.test(text.trim())) {
        noProgress.set(input.sessionID, 0);
        stopLogged.delete(input.sessionID);
      }
    },
    "tool.execute.after": async (input, output) => {
      const sid = input.sessionID;
      const args = input.args || {};
      const commit = input.tool === "bash" && /git commit/.test(args.command || "");
      if (["edit", "multiedit", "patch", "write"].includes(input.tool) || commit) noProgress.set(sid, 0);
      log(sid, commit ? `COMMIT ${short(args.command, 90)}` : describe(input.tool, args, output?.output));
    },
    "experimental.session.compacting": async (input, output) => {
      const extra =
        input.sessionID === CPU_SESSION
          ? " This is the autonomous RISC-V CPU project in ~/agent-workspace/hdl/rv32cpu: keep the current milestone, what passes and fails, uncommitted work and the RULES section of PROGRESS.md."
          : "";
      output.context.push(
        "Keep the user's task, what is done, what is left and any open errors." + extra +
          " End the summary with a line 'NEXT ACTION: <the exact next tool call to make>'.",
      );
    },
  };
};
