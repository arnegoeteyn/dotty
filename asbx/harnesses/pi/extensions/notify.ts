/**
 * notify: tell me when Pi needs me, via the shared notify.sh (OSC 9 on the
 * attached terminal, same as the copilot hooks).
 *
 * Content is deliberately minimal (folder name and state; never prompts or
 * model output) because notifications can show on the lock screen.
 *
 * Only active in the interactive TUI: in print/json/rpc mode (e.g. subagents)
 * there is no one to notify.
 */

import { spawn } from "node:child_process";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

// Filled in by ./asbx sync.
const NOTIFY = "{{.Shared}}/scripts/notify.sh";

type State = "needs input" | "done" | "failed";

// Maps onto notify.sh's events and the hook JSON fields it reads.
function alert(cwd: string, state: State): void {
	let event: string;
	let input: Record<string, unknown> = { cwd };
	if (state === "done") {
		event = "stop";
	} else if (state === "failed") {
		event = "error";
		input = { cwd, recoverable: false, error: { message: "Run failed" } };
	} else {
		event = "notification";
		input = { cwd, notification_type: "elicitation_dialog", message: "Needs your input" };
	}
	try {
		const child = spawn("sh", [NOTIFY, event], { stdio: ["pipe", "ignore", "ignore"], timeout: 5000 });
		child.on("error", () => {});
		child.stdin.on("error", () => {});
		child.stdin.end(JSON.stringify(input));
	} catch {
		// Notifications are best effort.
	}
}

type Block = { type: string; text?: string };
type Msg = { role?: string; stopReason?: string; content?: unknown };

function lastAssistant(messages: unknown[]): Msg | undefined {
	for (let i = messages.length - 1; i >= 0; i--) {
		const m = messages[i] as Msg;
		if (m?.role === "assistant") return m;
	}
	return undefined;
}

function finalText(m: Msg | undefined): string {
	if (!m || !Array.isArray(m.content)) return "";
	return (m.content as Block[])
		.filter((b) => b.type === "text" && typeof b.text === "string")
		.map((b) => b.text as string)
		.join("\n")
		.trim();
}

export default function (pi: ExtensionAPI) {
	let last: Msg | undefined;

	pi.on("agent_end", async (event) => {
		last = lastAssistant(event.messages as unknown[]) ?? last;
	});

	pi.on("agent_settled", async (event, ctx) => {
		const m = last;
		last = undefined;
		if (ctx.mode !== "tui" || event.aborted) return; // Escape: you're already here

		let state: State = "done";
		if (m?.stopReason === "error") state = "failed";
		// Heuristic: a reply ending in a question is waiting on you.
		else if (/\?\s*(\*\*|_|`)?\s*$/.test(finalText(m))) state = "needs input";
		alert(ctx.cwd, state);
	});

	// Extension dialogs (confirm/select/input, project trust, ...) block on you.
	pi.on("ui_prompt_start", async (_event, ctx) => {
		if (ctx.mode !== "tui") return;
		alert(ctx.cwd, "needs input");
	});
}
