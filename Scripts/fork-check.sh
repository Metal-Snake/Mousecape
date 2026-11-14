#!/bin/sh
# Monthly check of related projects and their forks (see FORK-CHECK.md).
#
#   fork-check.sh changed    list branches that are new or moved since fork-heads.tsv,
#                            one line each: repository, branch, old head or "new"
#   fork-check.sh snapshot   rewrite fork-heads.tsv with the current branch heads
#   fork-check.sh due        print "due since DATE" when the last check in
#                            FORK-CHECK.md is more than a month old, else nothing
#   fork-check.sh hook       Claude Code SessionStart hook: the same as a context
#                            reminder, only in sessions in this repository
#
# Watched: the original Mousecape and all its forks, Mousecape-swiftUI and its forks,
# MaCursor and its forks, Cursie and macOS27-Cursors. Needs gh (logged in) and git.
set -e
cd "$(dirname "$0")/.."
HEADS=Scripts/fork-heads.tsv

repos() {
    {
        echo alexzielenski/Mousecape
        gh api --paginate 'repos/alexzielenski/Mousecape/forks?per_page=100' --jq '.[].full_name'
        echo sdmj76/Mousecape-swiftUI
        gh api --paginate 'repos/sdmj76/Mousecape-swiftUI/forks?per_page=100' --jq '.[].full_name'
        echo writronic/MaCursor
        gh api --paginate 'repos/writronic/MaCursor/forks?per_page=100' --jq '.[].full_name'
        echo kwd421/macOS_Cursie
        echo Juwan-Hwang/macOS27-Cursors
    } | grep -v '^Metal-Snake/' | sort -u
}

current() {   # repo <TAB> branch <TAB> sha, for every branch of every watched repo
    repos | while read -r r; do
        git ls-remote --heads "https://github.com/$r.git" 2>/dev/null |
            sed "s|^\([0-9a-f]*\)	refs/heads/\(.*\)|$r	\2	\1|"
    done | sort
}

case "$1" in
snapshot)
    current > "$HEADS.new" && mv "$HEADS.new" "$HEADS"
    echo "$(wc -l < "$HEADS" | tr -d ' ') branches in $HEADS"
    ;;
changed)
    [ -f "$HEADS" ] || { echo "no $HEADS yet: run snapshot" >&2; exit 1; }
    current > "$HEADS.now"
    # Lines that are new or changed, reduced to the repository and branch.
    comm -13 "$HEADS" "$HEADS.now" | cut -f1,2 | while IFS="$(printf '\t')" read -r r b; do
        old=$(awk -F'\t' -v r="$r" -v b="$b" '$1==r && $2==b {print $3}' "$HEADS")
        echo "$r $b ${old:-new}"
    done
    rm -f "$HEADS.now"
    ;;
due)
    last=$(sed -n 's/^Last check: \([0-9-]*\).*/\1/p' FORK-CHECK.md | head -1)
    [ -n "$last" ] || { echo "due (no date in FORK-CHECK.md)"; exit 0; }
    limit=$(date -v-1m +%Y-%m-%d 2>/dev/null || date -d '1 month ago' +%Y-%m-%d)
    if [ "$last" \< "$limit" ] || [ "$last" = "$limit" ]; then echo "due since $last"; fi
    ;;
hook)
    # Claude Code SessionStart hook: in a session in this repository, add a reminder
    # to the context when the check is due.
    case "${CLAUDE_PROJECT_DIR:-$PWD}/" in
    "$(pwd)"/*) ;;
    *) exit 0 ;;
    esac
    msg=$("$0" due)
    [ -n "$msg" ] || exit 0
    printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"The monthly Mousecape and MaCursor fork check is %s. Tell the user and offer to run it now; how: %s/FORK-CHECK.md."}}\n' \
        "$msg" "$(pwd)"
    ;;
*)
    echo "usage: fork-check.sh changed|snapshot|due|hook" >&2; exit 2
    ;;
esac
