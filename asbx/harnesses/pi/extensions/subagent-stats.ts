/**
 * subagent-stats: how many runs of each subagent this session made, and what
 * they cost.
 *
 * /subagent-stats prints the table on demand. When a run that called the
 * subagent tool settles (e.g. the lead stops at the approval gate or
 * finishes), the table is printed automatically.
 *
 * The numbers come from the subagent tool's result details
 * (extensions/subagent). Subagents run as separate `pi --no-session`
 * processes, so their usage is not in pi's own session totals or footer.
 * Costs are pi's estimate from list prices, not what Copilot bills.
 *
 * The table is a custom entry: shown in the transcript, never sent to the
 * model.
 */

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { Box, Text } from "@earendil-works/pi-tui";

const ENTRY_TYPE = "subagent-stats";

type Row = {
	name: string;
	runs: number;
	failed: number;
	turns: number;
	input: number;
	cacheRead: number;
	output: number;
	cost: number;
};

type Stats = { lead: Row; agents: Row[]; total: Row };

const emptyRow = (name: string): Row => ({
	name,
	runs: 0,
	failed: 0,
	turns: 0,
	input: 0,
	cacheRead: 0,
	output: 0,
	cost: 0,
});

function addUsage(row: Row, u: any): void {
	if (!u) return;
	row.input += (u.input ?? 0) + (u.cacheWrite ?? 0);
	row.cacheRead += u.cacheRead ?? 0;
	row.output += u.output ?? 0;
	// Assistant messages carry cost.total, subagent results a plain number.
	row.cost += typeof u.cost === "number" ? u.cost : (u.cost?.total ?? 0);
}

function collect(entries: any[]): Stats {
	const lead = emptyRow("lead");
	const byAgent = new Map<string, Row>();

	for (const entry of entries) {
		if (entry.type === "usage") {
			addUsage(lead, entry.usage);
			continue;
		}
		if (entry.type !== "message") continue;
		const msg = entry.message;
		if (msg?.role === "assistant") {
			lead.turns++;
			addUsage(lead, msg.usage);
		} else if (msg?.role === "toolResult" && msg.toolName === "subagent") {
			for (const r of msg.details?.results ?? []) {
				const name = r.agent ?? "unknown";
				let row = byAgent.get(name);
				if (!row) byAgent.set(name, (row = emptyRow(name)));
				row.runs++;
				if (r.exitCode !== 0 || r.stopReason === "error" || r.stopReason === "aborted") row.failed++;
				row.turns += r.usage?.turns ?? 0;
				addUsage(row, r.usage);
			}
		}
	}
	lead.runs = lead.turns > 0 ? 1 : 0;

	const agents = [...byAgent.values()].sort((a, b) => b.cost - a.cost);
	const total = emptyRow("total");
	for (const row of [lead, ...agents]) {
		for (const k of ["runs", "failed", "turns", "input", "cacheRead", "output", "cost"] as const) {
			total[k] += row[k];
		}
	}
	return { lead, agents, total };
}

const tokens = (n: number) =>
	n < 1000 ? `${n}` : n < 1_000_000 ? `${(n / 1000).toFixed(1)}k` : `${(n / 1_000_000).toFixed(2)}M`;

function tableLines(stats: Stats): string[] {
	const header = ["agent", "runs", "failed", "turns", "in", "cached", "out", "cost"];
	const cells = (r: Row) => [
		r.name,
		`${r.runs}`,
		r.failed ? `${r.failed}` : "-",
		`${r.turns}`,
		tokens(r.input),
		tokens(r.cacheRead),
		tokens(r.output),
		`$${r.cost.toFixed(4)}`,
	];
	const rows = [header, ...stats.agents.map(cells), cells(stats.lead), cells(stats.total)];
	const widths = header.map((_, i) => Math.max(...rows.map((r) => r[i].length)));
	const fmt = (r: string[]) =>
		r.map((c, i) => (i === 0 ? c.padEnd(widths[i]) : c.padStart(widths[i]))).join("  ");
	const rule = "-".repeat(widths.reduce((a, b) => a + b + 2, -2));
	const lines = [fmt(header), rule, ...stats.agents.map((r) => fmt(cells(r)))];
	lines.push(rule, fmt(cells(stats.lead)), fmt(cells(stats.total)));
	return lines;
}

export default function (pi: ExtensionAPI) {
	pi.registerEntryRenderer<Stats>(ENTRY_TYPE, (entry, _opts, theme) => {
		const box = new Box(1, 1, (text) => theme.bg("customMessageBg", text));
		const stats = entry.data;
		if (!stats || stats.agents.length === 0) {
			box.addChild(new Text(theme.fg("muted", "No subagents run in this session."), 0, 0));
			return box;
		}
		const [header, ...rest] = tableLines(stats);
		box.addChild(new Text(theme.fg("accent", theme.bold("Subagent usage (this session)")), 0, 0));
		box.addChild(new Text(theme.bold(header), 0, 0));
		box.addChild(new Text(rest.join("\n"), 0, 0));
		box.addChild(new Text(theme.fg("dim", "Costs are estimates from list prices."), 0, 0));
		return box;
	});

	const show = (ctx: any) => {
		const stats = collect(ctx.sessionManager.getEntries());
		if (ctx.mode === "tui") {
			pi.appendEntry<Stats>(ENTRY_TYPE, stats);
		} else if (ctx.hasUI) {
			const text = stats.agents.length ? tableLines(stats).join("\n") : "No subagents run in this session.";
			ctx.ui.notify(text, "info");
		}
	};

	pi.registerCommand("subagent-stats", {
		description: "Show how many runs of each subagent this session made and their cost",
		handler: async (_args, ctx) => show(ctx),
	});

	// Print automatically when a run that used subagents settles. Interactive
	// only: subagents themselves run pi in json mode and load this extension too.
	let usedSubagents = false;
	pi.on("tool_execution_end", async (event) => {
		if (event.toolName === "subagent") usedSubagents = true;
	});
	pi.on("agent_settled", async (_event, ctx) => {
		if (!usedSubagents) return;
		usedSubagents = false;
		if (ctx.mode === "tui") show(ctx);
	});
}
