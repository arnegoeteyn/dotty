/**
 * subagent-viewer: browse every subagent conversation of this session.
 *
 * ctrl+shift+s (or /subagents) opens an overlay listing all subagent runs
 * (finished ones from the session, running ones live). Enter opens a run's
 * full conversation: task, thinking, text, tool calls and tool results.
 *
 * Keys, list:          up/down (j/k) move, enter (l) open, esc (q) close
 * Keys, conversation:  up/down (j/k) scroll, pgup/pgdn (space) page,
 *                      g/G top/bottom, e expand tool output and thinking,
 *                      esc (h, q) back to the list
 *
 * The data comes from the subagent tool's result details
 * (extensions/subagent): every SingleResult carries the subagent's messages.
 */

import type { ExtensionAPI, Theme } from "@earendil-works/pi-coding-agent";
import { getMarkdownTheme } from "@earendil-works/pi-coding-agent";
import { Markdown, matchesKey, truncateToWidth, visibleWidth, wrapTextWithAnsi } from "@earendil-works/pi-tui";

const SHORTCUT = "ctrl+shift+s";
const COLLAPSED_TOOL_LINES = 8;
const COLLAPSED_THINKING_LINES = 3;

type Status = "running" | "ok" | "failed";

type Run = {
	key: string;
	agent: string;
	task: string;
	status: Status;
	mode: string;
	step?: number;
	result: any; // SingleResult from extensions/subagent
};

// toolCallId -> latest details of a subagent call not yet in the session.
const live = new Map<string, { details: any; ended: boolean }>();
const listeners = new Set<() => void>();
const notify = () => {
	for (const l of listeners) l();
};

const isFailed = (r: any) =>
	r.exitCode > 0 || r.stopReason === "error" || r.stopReason === "aborted";

function runsFromDetails(id: string, details: any, running: boolean): Run[] {
	const results: any[] = details?.results ?? [];
	const mode = details?.mode ?? "single";
	return results.map((r, i) => {
		let status: Status = isFailed(r) ? "failed" : "ok";
		if (running) {
			if (r.exitCode === -1) status = "running";
			else if (mode !== "parallel" && i === results.length - 1) status = "running";
		}
		return {
			key: `${id}#${i}`,
			agent: r.agent ?? "unknown",
			task: r.task ?? "",
			status,
			mode,
			step: r.step,
			result: r,
		};
	});
}

function collectRuns(ctx: any): Run[] {
	const runs: Run[] = [];
	const seen = new Set<string>();
	const entries = ctx.sessionManager.getBranch?.() ?? ctx.sessionManager.getEntries();
	for (const entry of entries) {
		if (entry.type !== "message") continue;
		const msg = entry.message;
		if (msg?.role !== "toolResult" || msg.toolName !== "subagent") continue;
		seen.add(msg.toolCallId);
		runs.push(...runsFromDetails(msg.toolCallId, msg.details, false));
	}
	for (const [id, l] of live) {
		if (seen.has(id)) {
			live.delete(id);
			continue;
		}
		runs.push(...runsFromDetails(id, l.details, !l.ended));
	}
	return runs;
}

const oneLine = (s: string) => s.replace(/\s+/g, " ").trim();

const tokens = (n: number) =>
	n < 1000 ? `${n}` : n < 1_000_000 ? `${(n / 1000).toFixed(1)}k` : `${(n / 1_000_000).toFixed(2)}M`;

function usageLine(r: any): string {
	const u = r.usage ?? {};
	const parts: string[] = [];
	if (u.turns) parts.push(`${u.turns} turn${u.turns > 1 ? "s" : ""}`);
	if (u.input) parts.push(`↑${tokens(u.input)}`);
	if (u.output) parts.push(`↓${tokens(u.output)}`);
	if (u.cacheRead) parts.push(`R${tokens(u.cacheRead)}`);
	if (u.cost) parts.push(`$${u.cost.toFixed(4)}`);
	if (r.model) parts.push(r.thinking ? `${r.model} (${r.thinking})` : r.model);
	return parts.join(" ");
}

function statusIcon(theme: Theme, s: Status): string {
	if (s === "running") return theme.fg("warning", "⏳");
	if (s === "failed") return theme.fg("error", "✗");
	return theme.fg("success", "✓");
}

function toolCallSummary(name: string, args: any): string {
	args = args ?? {};
	switch (name) {
		case "bash":
			return `$ ${args.command ?? ""}`;
		case "read":
		case "write":
		case "edit":
		case "ls":
			return `${name} ${args.path ?? args.file_path ?? ""}`;
		case "grep":
		case "find":
			return `${name} ${args.pattern ?? ""} in ${args.path ?? "."}`;
		default:
			return `${name} ${JSON.stringify(args)}`;
	}
}

/** Renders one run's conversation into plain lines of the given width. */
function conversationLines(run: Run, width: number, expanded: boolean, theme: Theme): string[] {
	const r = run.result;
	const out: string[] = [];
	const wrap = (text: string, style: (s: string) => string, indent = "") => {
		for (const line of wrapTextWithAnsi(text, Math.max(10, width - indent.length))) {
			out.push(indent + style(line));
		}
	};
	const clipped = (text: string, max: number, style: (s: string) => string, indent: string) => {
		const lines = text.replace(/\s+$/, "").split("\n");
		const shown = expanded ? lines : lines.slice(0, max);
		wrap(shown.join("\n"), style, indent);
		if (shown.length < lines.length) {
			out.push(indent + theme.fg("muted", `… ${lines.length - shown.length} more lines (e to expand)`));
		}
	};
	const section = (title: string) => {
		out.push("");
		out.push(theme.fg("muted", `─── ${title} `.padEnd(Math.min(width, 60), "─")));
	};

	let header = `${statusIcon(theme, run.status)} ${theme.bold(theme.fg("accent", run.agent))}`;
	if (run.step) header += theme.fg("muted", ` (step ${run.step})`);
	if (r.stopReason && run.status === "failed") header += theme.fg("error", ` [${r.stopReason}]`);
	out.push(header);
	const usage = usageLine(r);
	if (usage) out.push(theme.fg("dim", usage));

	section("Task");
	wrap(run.task, (s) => theme.fg("dim", s));

	const md = getMarkdownTheme();
	for (const msg of r.messages ?? []) {
		if (msg.role === "assistant") {
			for (const part of msg.content ?? []) {
				if (part.type === "thinking" && part.thinking?.trim()) {
					section("Thinking");
					clipped(part.thinking, COLLAPSED_THINKING_LINES, (s) => theme.italic(theme.fg("dim", s)), "");
				} else if (part.type === "text" && part.text?.trim()) {
					section("Assistant");
					out.push(...new Markdown(part.text.trim(), 0, 0, md).render(width));
				} else if (part.type === "toolCall") {
					out.push("");
					wrap(toolCallSummary(part.name, part.arguments), (s) => theme.fg("toolOutput", s), "→ ");
				}
			}
			if (msg.errorMessage) wrap(`Error: ${msg.errorMessage}`, (s) => theme.fg("error", s));
		} else if (msg.role === "toolResult") {
			const text = (msg.content ?? [])
				.map((c: any) => (c.type === "text" ? c.text : `[${c.type}]`))
				.join("\n");
			const style = msg.isError ? (s: string) => theme.fg("error", s) : (s: string) => theme.fg("muted", s);
			if (text.trim()) clipped(text, COLLAPSED_TOOL_LINES, style, "  ");
			else out.push(`  ${theme.fg("muted", "(no output)")}`);
		}
	}

	if (run.status === "running") {
		out.push("");
		out.push(theme.fg("warning", "(running…)"));
	}
	if (run.status === "failed") {
		if (r.errorMessage) {
			section("Error");
			wrap(r.errorMessage, (s) => theme.fg("error", s));
		}
		if (r.stderr?.trim()) {
			section("stderr");
			clipped(r.stderr, COLLAPSED_TOOL_LINES, (s) => theme.fg("error", s), "");
		}
	}
	return out.map((l) => truncateToWidth(l, width));
}

class SubagentViewer {
	private selected = 0;
	private open: string | null = null; // key of the run shown
	private scroll = 0;
	private follow = true;
	private expanded = false;
	private cache?: { sig: string; lines: string[] };
	private lastBodyHeight = 10;
	private lastMax = 0;

	constructor(
		private ctx: any,
		private theme: Theme,
		private keybindings: any,
		private done: () => void,
	) {
		const runs = collectRuns(ctx);
		this.selected = Math.max(0, runs.length - 1);
	}

	invalidate() {
		this.cache = undefined;
	}

	private height(): number {
		const rows = process.stdout.rows || 40;
		return Math.max(10, Math.floor(rows * 0.9));
	}

	private frame(width: number, title: string, body: string[], help: string): string[] {
		const t = this.theme;
		const inner = width - 4;
		const border = (s: string) => t.fg("border", s);
		const top = `${border("╭─")} ${t.bold(t.fg("accent", title))} `;
		const lines = [truncateToWidth(top + border("─".repeat(Math.max(0, width - visibleWidth(top) - 1))) + border("╮"), width)];
		for (const line of body) {
			const content = truncateToWidth(line, inner);
			lines.push(`${border("│")} ${content}${" ".repeat(Math.max(0, inner - visibleWidth(content)))} ${border("│")}`);
		}
		const bottom = `${border("╰─")} ${t.fg("dim", help)} `;
		lines.push(truncateToWidth(bottom + border("─".repeat(Math.max(0, width - visibleWidth(bottom) - 1))) + border("╯"), width));
		return lines;
	}

	render(width: number): string[] {
		const runs = collectRuns(this.ctx);
		const bodyHeight = this.height() - 2;
		this.lastBodyHeight = bodyHeight;
		const inner = Math.max(20, width - 4);
		const run = this.open ? runs.find((r) => r.key === this.open) : undefined;
		if (this.open && !run) this.open = null;

		if (!run) return this.renderList(runs, width, inner, bodyHeight);

		const sig = `${run.key}|${inner}|${run.result.messages?.length ?? 0}|${run.status}|${this.expanded}`;
		if (this.cache?.sig !== sig) {
			this.cache = { sig, lines: conversationLines(run, inner, this.expanded, this.theme) };
		}
		const lines = this.cache.lines;
		const max = Math.max(0, lines.length - bodyHeight);
		this.lastMax = max;
		if (this.follow) this.scroll = max;
		this.scroll = Math.min(Math.max(0, this.scroll), max);
		const body = lines.slice(this.scroll, this.scroll + bodyHeight);
		while (body.length < bodyHeight) body.push("");
		const pos = lines.length > bodyHeight ? ` ${this.scroll + body.length}/${lines.length}` : "";
		return this.frame(
			width,
			`${run.agent}${pos}`,
			body,
			`↑↓ pgup/pgdn g/G scroll · e ${this.expanded ? "collapse" : "expand"} · esc back`,
		);
	}

	private renderList(runs: Run[], width: number, inner: number, bodyHeight: number): string[] {
		const t = this.theme;
		const body: string[] = [];
		if (runs.length === 0) {
			body.push(t.fg("muted", "No subagent runs in this session yet."));
		} else {
			this.selected = Math.min(Math.max(0, this.selected), runs.length - 1);
			const nameWidth = Math.min(16, Math.max(...runs.map((r) => r.agent.length)));
			const start = Math.max(0, Math.min(this.selected - Math.floor(bodyHeight / 2), runs.length - bodyHeight));
			runs.slice(start, start + bodyHeight).forEach((run, i) => {
				const idx = start + i;
				const cursor = idx === this.selected ? t.fg("accent", "› ") : "  ";
				const name = run.agent.padEnd(nameWidth);
				const stats = usageLine({ usage: run.result.usage });
				const prefix = `${cursor}${statusIcon(t, run.status)} ${idx === this.selected ? t.bold(t.fg("accent", name)) : t.fg("accent", name)}  `;
				const room = inner - visibleWidth(prefix) - visibleWidth(stats) - 2;
				const task = truncateToWidth(oneLine(run.task), Math.max(10, room));
				const gap = " ".repeat(Math.max(2, inner - visibleWidth(prefix) - visibleWidth(task) - visibleWidth(stats)));
				body.push(prefix + task + gap + t.fg("dim", stats));
			});
		}
		const running = runs.filter((r) => r.status === "running").length;
		const title = `Subagents (${runs.length}${running ? `, ${running} running` : ""})`;
		return this.frame(width, title, body, "↑↓ select · enter open · esc close");
	}

	handleInput(data: string): void {
		const kb = this.keybindings;
		const is = (action: string, ...keys: string[]) =>
			(action && kb.matches(data, action)) || keys.some((k) => matchesKey(data, k as any));

		if (!this.open) {
			const runs = collectRuns(this.ctx);
			if (is("tui.select.cancel", "q")) return this.done();
			if (is("tui.select.up", "k")) this.selected = Math.max(0, this.selected - 1);
			else if (is("tui.select.down", "j")) this.selected = Math.min(runs.length - 1, this.selected + 1);
			else if (is("tui.select.pageUp")) this.selected = Math.max(0, this.selected - this.lastBodyHeight);
			else if (is("tui.select.pageDown")) this.selected = Math.min(runs.length - 1, this.selected + this.lastBodyHeight);
			else if (is("tui.select.confirm", "l", "right") && runs[this.selected]) {
				this.open = runs[this.selected].key;
				this.expanded = false;
				this.follow = runs[this.selected].status === "running";
				this.scroll = 0;
				this.cache = undefined;
			}
			return;
		}

		const page = Math.max(1, this.lastBodyHeight - 2);
		const scrollTo = (n: number) => {
			this.scroll = Math.min(Math.max(0, n), this.lastMax);
			this.follow = this.scroll >= this.lastMax;
		};
		if (is("tui.select.cancel", "q", "h", "left", "backspace")) {
			this.open = null;
			this.cache = undefined;
		} else if (is("tui.select.up", "k")) scrollTo(this.scroll - 1);
		else if (is("tui.select.down", "j")) scrollTo(this.scroll + 1);
		else if (is("tui.select.pageUp", "b", "ctrl+u")) scrollTo(this.scroll - page);
		else if (is("tui.select.pageDown", "space", "ctrl+d")) scrollTo(this.scroll + page);
		else if (is("", "g", "home")) scrollTo(0);
		else if (is("", "shift+g", "end") || data === "G") scrollTo(Number.MAX_SAFE_INTEGER);
		else if (is("", "e")) {
			this.expanded = !this.expanded;
			this.cache = undefined;
		}
	}
}

export default function (pi: ExtensionAPI) {
	pi.on("tool_execution_update", async (event: any) => {
		if (event.toolName !== "subagent" || event.parentToolCallId) return;
		live.set(event.toolCallId, { details: event.partialResult?.details, ended: false });
		notify();
	});
	pi.on("tool_execution_end", async (event: any) => {
		if (event.toolName !== "subagent" || event.parentToolCallId) return;
		live.set(event.toolCallId, { details: event.result?.details, ended: true });
		notify();
	});
	pi.on("session_start", async () => {
		live.clear();
	});

	const show = async (ctx: any) => {
		if (ctx.mode !== "tui") {
			ctx.ui?.notify?.("The subagent viewer needs interactive mode.", "error");
			return;
		}
		let listener: (() => void) | undefined;
		await ctx.ui.custom(
			(tui: any, theme: Theme, keybindings: any, done: () => void) => {
				const viewer = new SubagentViewer(ctx, theme, keybindings, () => done());
				const rerender = () => {
					viewer.invalidate();
					tui.requestRender();
				};
				// The viewer handles input itself; re-render after each key and
				// whenever a running subagent reports progress.
				const handle = viewer.handleInput.bind(viewer);
				viewer.handleInput = (data: string) => {
					handle(data);
					tui.requestRender();
				};
				listener = rerender;
				listeners.add(listener);
				return viewer;
			},
			{ overlay: true, overlayOptions: { width: "92%", maxHeight: "90%", anchor: "center" } },
		);
		if (listener) listeners.delete(listener);
	};

	pi.registerShortcut(SHORTCUT, {
		description: "Show all subagent conversations",
		handler: show,
	});
	pi.registerCommand("subagents", {
		description: "Show all subagent conversations (also ctrl+shift+s)",
		handler: async (_args, ctx) => show(ctx),
	});
}
