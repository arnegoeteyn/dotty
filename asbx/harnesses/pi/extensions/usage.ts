/**
 * usage: /usage shows the GitHub Copilot quota (like Copilot CLI's /usage)
 * and the tokens used in this pi session.
 *
 * The quota comes from api.github.com/copilot_internal/user. In the sandbox
 * GH_TOKEN is a placeholder that the sbx proxy swaps for the real token.
 */

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

type Quota = {
	unlimited?: boolean;
	entitlement?: number;
	remaining?: number;
	quota_remaining?: number;
	percent_remaining?: number;
	overage_count?: number;
	overage_permitted?: boolean;
};

type CopilotUser = {
	copilot_plan?: string;
	quota_reset_date?: string;
	quota_snapshots?: Record<string, Quota>;
};

const QUOTA_LABELS: Record<string, string> = {
	premium_interactions: "Premium requests",
	chat: "Chat",
	completions: "Completions",
};

const num = (n: number) => Math.round(n).toLocaleString("en-US");

async function fetchCopilotUser(signal?: AbortSignal): Promise<CopilotUser> {
	const token = process.env.GH_TOKEN || process.env.GITHUB_TOKEN;
	if (!token) throw new Error("GH_TOKEN is not set");
	const res = await fetch("https://api.github.com/copilot_internal/user", {
		headers: { Authorization: `token ${token}`, Accept: "application/json" },
		signal,
	});
	if (!res.ok) throw new Error(`GitHub API returned ${res.status}`);
	return (await res.json()) as CopilotUser;
}

function quotaLines(user: CopilotUser): string[] {
	const lines = [`Copilot plan: ${user.copilot_plan ?? "unknown"}`];
	for (const [id, q] of Object.entries(user.quota_snapshots ?? {})) {
		const label = QUOTA_LABELS[id] ?? id;
		if (q.unlimited) {
			lines.push(`  ${label}: unlimited`);
			continue;
		}
		const left = q.quota_remaining ?? q.remaining ?? 0;
		const used = (q.entitlement ?? 0) - left;
		let line = `  ${label}: ${num(left)} of ${num(q.entitlement ?? 0)} left`;
		line += ` (${(q.percent_remaining ?? 0).toFixed(1)}%, ${num(used)} used)`;
		if (q.overage_count) line += `, ${num(q.overage_count)} overage`;
		else if (q.overage_permitted) line += ", overage allowed";
		lines.push(line);
	}
	if (user.quota_reset_date) lines.push(`  Resets: ${user.quota_reset_date}`);
	return lines;
}

type Usage = { input?: number; output?: number; cacheRead?: number; cacheWrite?: number };

function sessionLines(ctx: any): string[] {
	const total = { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, requests: 0 };
	for (const entry of ctx.sessionManager.getEntries() as any[]) {
		let u: Usage | undefined;
		if (entry.type === "message" && entry.message?.role === "assistant") {
			u = entry.message.usage;
			total.requests++;
		} else if (entry.type === "usage") {
			u = entry.usage;
		}
		if (!u) continue;
		total.input += u.input ?? 0;
		total.output += u.output ?? 0;
		total.cacheRead += u.cacheRead ?? 0;
		total.cacheWrite += u.cacheWrite ?? 0;
	}
	const lines = [
		`Session: ${num(total.requests)} model requests`,
		`  Tokens: ${num(total.input)} in, ${num(total.output)} out, ${num(total.cacheRead)} cache read, ${num(total.cacheWrite)} cache write`,
	];
	const ctxUsage = ctx.getContextUsage?.();
	if (ctxUsage?.tokens != null) {
		lines.push(
			`  Context: ${num(ctxUsage.tokens)} of ${num(ctxUsage.contextWindow)} (${(ctxUsage.percent ?? 0).toFixed(1)}%)`,
		);
	}
	return lines;
}

export default function (pi: ExtensionAPI) {
	pi.registerCommand("usage", {
		description: "Show GitHub Copilot quota and this session's token usage",
		handler: async (_args, ctx) => {
			let quota: string[];
			try {
				quota = quotaLines(await fetchCopilotUser(ctx.signal));
			} catch (err) {
				quota = [`Copilot quota unavailable: ${(err as Error).message}`];
			}
			ctx.ui.notify([...quota, "", ...sessionLines(ctx)].join("\n"), "info");
		},
	});
}
