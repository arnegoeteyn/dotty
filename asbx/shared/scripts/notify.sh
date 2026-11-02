#!/bin/sh
# Agent hook: shows a desktop notification via OSC 9 on the attached terminal.
# Usage: notify.sh <event>, hook JSON on stdin. Never prints to stdout (that
# would be read as a hook decision) and always exits 0.

event=$1
in=$(cat)
field() { printf '%s' "$in" | jq -r "$1 // empty" 2>/dev/null; }

repo=$(basename "$(field .cwd)")
case $event in
stop) title=Done body="Finished its turn" ;;
error)
	[ "$(field .recoverable)" = true ] && exit 0
	title=Error body=$(field .error.message)
	;;
notification)
	case $(field .notification_type) in
	permission_prompt) title=Permission ;;
	elicitation_dialog) title=Question ;;
	*) title=$(field .title) ;;
	esac
	body=$(field .message)
	;;
*) title=$event ;;
esac

# Keep it to one line without control characters, so it can't break the escape.
msg=$(printf '%s: %s - %s' "${repo:-agent}" "${title:-Agent}" "$body" | tr -d '\000-\037' | cut -c1-200)

# Hooks may run without a controlling terminal; then use the TTY of the
# closest ancestor (the agent itself).
tty=/dev/tty
if ! (: >/dev/tty) 2>/dev/null; then
	tty=
	pid=$PPID
	while [ "${pid:-0}" -gt 1 ]; do
		t=$(readlink "/proc/$pid/fd/0" 2>/dev/null)
		case $t in /dev/pts/* | /dev/tty*) tty=$t && break ;; esac
		pid=$(awk '{print $4}' "/proc/$pid/stat" 2>/dev/null)
	done
fi
[ -n "$tty" ] && printf '\033]9;%s\a' "$msg" >"$tty" 2>/dev/null
exit 0
