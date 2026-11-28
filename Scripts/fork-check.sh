#!/bin/sh
# Monthly check of related projects and their forks (see the check file named in
# fork-check.conf, usually FORK-CHECK.md in the repository root).
#
#   fork-check.sh changed    list branches that are new or moved since the heads file,
#                            one line each: repository, branch, old head or "new"
#   fork-check.sh upstream   pull requests and issues of the ISSUES repositories opened
#                            or updated since the last check (before the first check:
#                            since ISSUES_SINCE): repository, kind, number, state, date,
#                            author, title
#   fork-check.sh ahead      every branch in the heads file with commits that the default
#                            branch of its fork network's root lacks: date of its head,
#                            commits ahead, commits behind, repository, branch - newest
#                            first. Asks GitHub's compare API, clones nothing
#   fork-check.sh repos      the watched repositories, one per line
#   fork-check.sh snapshot   rewrite the heads file with the current branch heads
#   fork-check.sh due        print "due since DATE" when the last check in the check
#                            file is more than a month old, "due (...)" when it has no
#                            date yet, else nothing
#   fork-check.sh hook       Claude Code SessionStart hook: the same as a context
#                            reminder, only in sessions inside this repository
#
# What is watched comes from fork-check.conf next to this script: every repository in
# NETWORKS with all its forks, the forks of those forks and so on (as deep as they go),
# plus the repositories in EXTRA (copies outside GitHub's fork network). Needs gh
# (logged in) and git.
#
# This script is generic; it comes from the fork-check skill. Keep project settings in
# fork-check.conf so that a newer version of the script can simply replace this file.
set -e
# Where the script was started and its own path, taken before the cd below changes $PWD
# and makes a relative $0 useless. The hook falls back to the first when Claude Code
# doesn't set CLAUDE_PROJECT_DIR.
started_in=$PWD
script_directory="$(cd "$(dirname "$0")" && pwd)"
self="$script_directory/$(basename "$0")"

# Defaults, overridden by fork-check.conf. Paths are relative to the repository root.
NAME=$(basename "$(git -C "$script_directory" rev-parse --show-toplevel)")
NETWORKS=""             # repositories whose forks are watched, recursively
EXTRA=""                # further repositories, not in a watched fork network
ISSUES=""               # repositories whose pull requests and issues are listed
ISSUES_SINCE=""         # start date for "upstream" before the first check
EXCLUDE_OWNERS=""       # owners left out (our own account)
CHECK_FILE=FORK-CHECK.md
HEADS="${script_directory#"$(git -C "$script_directory" rev-parse --show-toplevel)/"}/fork-heads.tsv"
. "$script_directory/fork-check.conf"

cd "$(git -C "$script_directory" rev-parse --show-toplevel)"

last_check() {   # the date after "Last check:" in the check file, if there is one
    sed -n 's/^Last check: \([0-9][0-9-]*\).*/\1/p' "$CHECK_FILE" 2>/dev/null | head -1
}

forks_of() {   # every fork of $1, and their forks, recursively
    gh api --paginate "repos/$1/forks?per_page=100" --jq '.[] | "\(.full_name) \(.forks_count)"' |
    while read -r fork fork_count; do
        echo "$fork"
        # Only repositories that have forks of their own cost another call.
        [ "$fork_count" -gt 0 ] && forks_of "$fork"
        true
    done
}

repos() {
    {
        for network in $NETWORKS; do
            echo "$network"
            forks_of "$network"
        done
        for repository in $EXTRA; do echo "$repository"; done
    } | while read -r repository; do
        # Leave out the excluded owners (case-insensitive, as GitHub treats them).
        owner=$(echo "${repository%%/*}" | tr '[:upper:]' '[:lower:]')
        excluded=no
        for exclude in $EXCLUDE_OWNERS; do
            [ "$owner" = "$(echo "$exclude" | tr '[:upper:]' '[:lower:]')" ] && excluded=yes
        done
        [ "$excluded" = no ] && echo "$repository"
        true
    done | sort -u
}

current() {   # repo <TAB> branch <TAB> sha, for every branch of every watched repo
    repos | while read -r r; do
        git ls-remote --heads "https://github.com/$r.git" 2>/dev/null |
            sed "s|^\([0-9a-f]*\)	refs/heads/\(.*\)|$r	\2	\1|"
    done | sort
}

case "$1" in
repos)
    repos
    ;;
snapshot)
    current > "$HEADS.new" && mv "$HEADS.new" "$HEADS"
    echo "$(wc -l < "$HEADS" | tr -d ' ') branches in $(cut -f1 "$HEADS" | sort -u | wc -l | tr -d ' ') repositories in $HEADS"
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
upstream)
    since=$(last_check)
    since=${since:-$ISSUES_SINCE}
    [ -n "$since" ] || { echo "no last check and no ISSUES_SINCE in fork-check.conf" >&2; exit 1; }
    for repository in $ISSUES; do
        for kind in pr issue; do
            gh "$kind" list -R "$repository" --state all --limit 200 --search "updated:>=$since" \
                --json number,state,updatedAt,title,author \
                --jq ".[] | \"$repository\t$kind\t#\\(.number)\t\\(.state)\t\\(.updatedAt[:10])\t\\(.author.login)\t\\(.title)\""
        done
    done
    ;;
ahead)
    [ -f "$HEADS" ] || { echo "no $HEADS yet: run snapshot" >&2; exit 1; }
    # One line "repository branch sha" per branch (branch names contain no spaces),
    # then eight at a time: find the root of the repository's fork network and its
    # default branch, and compare. The head is given by its sha, which GitHub resolves
    # across the fork network, so branch names with "/" need no escaping.
    tr '\t' ' ' < "$HEADS" |
    xargs -n 3 -P 8 sh -c '
        repository=$1 branch=$2 sha=$3
        base=$(gh api "repos/$repository" --jq "(.source // .) | \"\(.full_name) \(.default_branch)\"" 2>/dev/null) || {
            printf "?\t?\t?\t%s\t%s\t(repository not found)\n" "$repository" "$branch"; exit 0; }
        set -- $base
        root=$1 default_branch=$2
        compare() {
            gh api "repos/$root/compare/$default_branch...$1?per_page=1" \
                --jq "\"\(.ahead_by) \(.behind_by)\"" 2>/dev/null
        }
        # GitHub does not find every sha in the network (404); then name the head
        # as owner:repository:branch, with "/" in the branch escaped. Repositories
        # outside the network (EXTRA) cannot be compared at all.
        owner_head="$(echo "$repository" | tr / :):$(echo "$branch" | sed "s|/|%2F|g")"
        counts=$(compare "$sha") || counts=$(compare "$owner_head") || {
            printf "?\t?\t?\t%s\t%s\t(compare failed)\n" "$repository" "$branch"; exit 0; }
        set -- $counts
        ahead=$1 behind=$2
        [ "$ahead" -gt 0 ] || exit 0
        date=$(gh api "repos/$repository/commits/$sha" --jq ".commit.committer.date[:10]" 2>/dev/null || echo "?")
        printf "%s\t%s\t%s\t%s\t%s\n" "$date" "$ahead" "$behind" "$repository" "$branch"
    ' sh | sort -r
    ;;
due)
    last=$(last_check)
    [ -n "$last" ] || { echo "due (no date in $CHECK_FILE yet)"; exit 0; }
    limit=$(date -v-1m +%Y-%m-%d 2>/dev/null || date -d '1 month ago' +%Y-%m-%d)
    if [ "$last" \< "$limit" ] || [ "$last" = "$limit" ]; then echo "due since $last"; fi
    ;;
hook)
    # Claude Code SessionStart hook: in a session inside this repository, add a
    # reminder to the context when the check is due.
    case "${CLAUDE_PROJECT_DIR:-$started_in}/" in
    "$(pwd)"/*) ;;
    *) exit 0 ;;
    esac
    msg=$("$self" due)
    [ -n "$msg" ] || exit 0
    printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"The monthly %s fork check is %s. Tell the user and offer to run it now; how: %s/%s."}}\n' \
        "$NAME" "$msg" "$(pwd)" "$CHECK_FILE"
    ;;
*)
    echo "usage: fork-check.sh changed|upstream|ahead|repos|snapshot|due|hook" >&2; exit 2
    ;;
esac
