/**
 * note: /note <text> records your verdict on the session (what went well or
 * wrong, what you did with the result) for later review of the setup.
 *
 * The note is a custom entry: saved in the session file and shown in the
 * transcript, never sent to the model. Find them later with:
 *   jq 'select(.customType == "note")' <session>.jsonl
 */

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { Box, Text } from "@earendil-works/pi-tui";

const ENTRY_TYPE = "note";

type Note = { text: string };

export default function (pi: ExtensionAPI) {
	pi.registerEntryRenderer<Note>(ENTRY_TYPE, (entry, _opts, theme) => {
		const box = new Box(1, 1, (text) => theme.bg("customMessageBg", text));
		box.addChild(new Text(theme.fg("accent", theme.bold("Note")) + theme.fg("dim", " (not sent to the model)"), 0, 0));
		box.addChild(new Text(entry.data?.text ?? "", 0, 0));
		return box;
	});

	pi.registerCommand("note", {
		description: "Save a note on this session for later review (not sent to the model)",
		handler: async (args, ctx) => {
			const text = args.trim();
			if (!text) {
				if (ctx.hasUI) ctx.ui.notify("Usage: /note <text>", "warning");
				return;
			}
			pi.appendEntry<Note>(ENTRY_TYPE, { text });
			if (ctx.hasUI && ctx.mode !== "tui") ctx.ui.notify("Note saved", "info");
		},
	});
}
