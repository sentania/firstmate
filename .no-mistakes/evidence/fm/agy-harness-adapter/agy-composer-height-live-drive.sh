#!/usr/bin/env bash
# Live drive: does FM_COMPOSER_AGY_MAX_LINES move the accepted Agy composer
# container height against a REAL Agy render holding a multi-line draft?
set -u
ROOT=/home/scott/.no-mistakes/worktrees/bf67b868af46/01M25VHW7RKFNP0AXM5MEQVHQJ
EV=/home/scott/.no-mistakes/evidence/01M25VHW7RKFNP0AXM5MEQVHQJ
unset TMUX TMUX_PANE NO_MISTAKES_GATE
# tests/lib.sh exports this for the same reason: drive the REAL fm-spawn from a gate worktree.
export FM_GATE_REFUSE_BYPASS=1
SOCKET="fm-agy-tall-$$"
REAL_TMUX=$(command -v tmux)
LAB=$(mktemp -d "${TMPDIR:-/tmp}/fm-agy-tall.XXXXXX"); LAB=$(cd "$LAB" && pwd -P)
TASK="agytall-$$"
PROJ="$LAB/projects/agytall"
PASSED=0
cleanup() {
  FM_HOME="$LAB" "$ROOT/bin/fm-teardown.sh" "$TASK" --force >/dev/null 2>&1 || true
  "$REAL_TMUX" -L "$SOCKET" kill-server >/dev/null 2>&1 || true
  [ "$PASSED" -eq 1 ] && rm -rf -- "$LAB" || printf '# lab preserved: %s\n' "$LAB" >&2
}
trap cleanup EXIT

mkdir -p "$LAB/config" "$LAB/data" "$LAB/state" "$LAB/shim" "$LAB/treehouse" "$PROJ"
touch "$LAB/state/.last-watcher-beat"
export TREEHOUSE_ROOT="$LAB/treehouse"
cat > "$LAB/shim/tmux" <<SH
#!/usr/bin/env bash
exec "$REAL_TMUX" -L "$SOCKET" "\$@"
SH
chmod +x "$LAB/shim/tmux"
PATH="$LAB/shim:$PATH"; export PATH
. "$ROOT/bin/fm-tmux-lib.sh"

printf 'Agy tall composer probe\n' > "$PROJ/README.md"
git -C "$PROJ" init -q -b main
git -C "$PROJ" config user.email 'agy-tall@example.invalid'
git -C "$PROJ" config user.name 'agy tall probe'
git -C "$PROJ" add README.md
git -C "$PROJ" commit -qm 'fixture: agy tall composer probe'

tmux new-session -d -s firstmate -x 200 -y 50 -c "$LAB" || { echo "no tmux server"; exit 1; }
FM_HOME="$LAB" "$ROOT/bin/fm-brief.sh" "$TASK" agytall --scout >/dev/null 2>&1
BRIEF="$LAB/data/$TASK/brief.md"
awk -v task="Composer height probe. Do nothing at all: reply with exactly the single line AGY_TALL_OK and stop. Run no commands." \
    -v spec="None beyond the captain's intent above: the probe is the whole task." \
    '$0 == "{TASK}" { print task; next } $0 == "{FIRSTMATE_SPEC}" { print spec; next } { print }' \
    "$BRIEF" > "$BRIEF.tmp" && mv "$BRIEF.tmp" "$BRIEF"

echo "# spawning agy $(agy --version)"
FM_HOME="$LAB" timeout 300 "$ROOT/bin/fm-spawn.sh" "$TASK" "$PROJ" \
  --scout --harness agy --model gemini-3.8-flash-low --effort low > "$LAB/spawn.log" 2>&1
echo "# spawn rc=$? : $(grep '^spawned ' "$LAB/spawn.log" | head -1)"
WINDOW=$(awk -F= '/^window=/ { print $2 }' "$LAB/state/$TASK.meta")
[ -n "$WINDOW" ] || { cat "$LAB/spawn.log"; exit 1; }

pane() { tmux capture-pane -p -t "$WINDOW" 2>/dev/null; }
state() { FM_COMPOSER_HARNESS=agy fm_tmux_composer_state "$WINDOW"; }

i=0; while [ $i -lt 120 ]; do [ "$(state)" = empty ] && break; sleep 1; i=$((i+1)); done
echo "# composer before paste: $(state)"

probe_paste() {  # <label> <n-lines>
  local label=$1 n=$2 i txt=''
  # clear whatever is in the composer
  local j=0; while [ $j -lt 400 ]; do tmux send-keys -t "$WINDOW" BSpace; j=$((j+1)); done
  sleep 2
  i=1; while [ $i -le "$n" ]; do
    if [ $i -eq 1 ]; then txt="pasted captain steer line $i"; else txt="$txt
line $i"; fi
    i=$((i+1))
  done
  printf '%s' "$txt" > "$LAB/draft.txt"
  tmux load-buffer -b agydraft "$LAB/draft.txt"
  tmux paste-buffer -p -b agydraft -t "$WINDOW"
  j=0; while [ $j -lt 30 ]; do pane | grep -Fq "line $n" && break; sleep 1; j=$((j+1)); done
  sleep 3
  echo ""
  echo "=== REAL AGY PANE: $label ($n rendered composer rows) ==="
  pane | grep -n '[^[:space:]]' | tail -"$((n+4))"
  echo "--- separator rows in the capture (1-indexed) ---"
  pane | awk '{ t=$0; gsub(/^[[:space:]]+|[[:space:]]+$/,"",t); p=t; gsub(/[\xe2\x94\x80\xe2\x94\x81\xe2\x95\x8c\xe2\x95\x90-]/,"",p); if (p=="" && length(t)>=20) print "  row "NR }'
  echo "--- product verdict (bin/fm-tmux-lib.sh fm_tmux_composer_state, FM_COMPOSER_HARNESS=agy) ---"
  echo "  default bound (unset -> 7)      : '$(state)'"
  echo "  raised  bound (=20)             : '$(FM_COMPOSER_AGY_MAX_LINES=20 state)'"
  echo "  clamped bound (=nonsense -> 7)  : '$(FM_COMPOSER_AGY_MAX_LINES=nonsense state)'"
}

probe_paste "six-line pasted draft" 6
probe_paste "seven-line pasted draft" 7
probe_paste "ten-line pasted draft" 10

PASSED=1
