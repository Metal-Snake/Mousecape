#!/bin/zsh
# Runs frame-limit-probe on another Mac (e.g. a macOS 27 VM) and writes a report next to
# this script: frame-limit-report-<build>.txt. Put the built probe next to it:
#
#   cc -fobjc-arc -mmacosx-version-min=14.0 Scripts/frame-limit-probe.m -o frame-limit-probe \
#      -F/System/Library/PrivateFrameworks -framework SkyLight -framework CoreGraphics \
#      -framework AppKit
#
# Step 1 is harmless: it registers test cursors for the probe's own connection only.
# Step 2, the playback test, asks first; it changes the arrow on screen. Afterwards the
# script applies the cape that was applied before (or resets) with Mousecape's mousecloak.

cd "${0:A:h}" || exit 1
build=$(sw_vers -buildVersion)
report="frame-limit-report-$build.txt"
mousecloak=/Applications/Mousecape.app/Contents/MacOS/mousecloak

{
    echo "Frame-limit test, $(date '+%Y-%m-%d %H:%M')"
    echo
    echo "== Step 1: compare the public and the internal registration call"
} > "$report"

./frame-limit-probe 2>&1 | tee -a "$report"
probe_status=${pipestatus[1]}
if (( probe_status != 0 )); then
    echo "Probe stopped (status $probe_status). No playback test." | tee -a "$report"
    echo "Report: ${0:A:h}/$report"
    exit 1
fi

echo
read -q "answer?Run the playback test? The arrow shows a numbered animation until the cape is applied again. [y/N] "
echo
if [[ $answer != y ]]; then
    echo "Playback test skipped." | tee -a "$report"
    echo "Report: ${0:A:h}/$report"
    exit 0
fi

echo "\n== Step 2: playback with 48 frames" >> "$report"
./frame-limit-probe --play 48 2>&1 | tee -a "$report"
if (( ${pipestatus[1]} == 0 )); then
    echo
    echo "Watch the arrow for at least 12 seconds (move it a little to be sure it is the arrow)."
    echo "Does it count 1 to 48 without gaps, then start again at 1?"
    read "seen?Describe what you see (e.g. 'yes, 1 to 48', 'only to 24', 'stays at 1'): "
    echo "Seen: $seen" >> "$report"
fi

# Back to the state before the test.
applied=$(defaults -currentHost read com.alexzielenski.Mousecape MCAppliedCursor 2>/dev/null)
cape="$HOME/Library/Application Support/Mousecape/capes/$applied.cape"
if [[ -x $mousecloak && -n $applied && -f $cape ]]; then
    echo "Applying $applied again." | tee -a "$report"
    "$mousecloak" --apply "$cape" > /dev/null 2>&1
elif [[ -x $mousecloak ]]; then
    echo "Resetting the cursors." | tee -a "$report"
    "$mousecloak" --reset > /dev/null 2>&1
else
    echo "Mousecape isn't in /Applications: apply a cape or log out to get the arrow back." | tee -a "$report"
fi
echo "Report: ${0:A:h}/$report"
