#!/bin/bash
#
# import-upstream.sh - Import upstream picolibc commits with copyleft files
# filtered out.
#
# Usage:
#   scripts/import-upstream.sh <from-tag> <to-tag>
#
# Arguments should be upstream picolibc version tags (e.g., 1.8.11, 1.9.0).
#
# Cherry-picks each upstream commit, removing copyleft files listed in
# COPYLEFT_EXCLUSIONS. Copyleft-only commits are skipped. Known fork
# divergences (deleted copyleft files, renamed README) are auto-resolved.

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
UPSTREAM_REMOTE="upstream"
UPSTREAM_URL="https://github.com/picolibc/picolibc.git"

# Read exclusion paths into an associative array for O(1) lookup
declare -A EXCLUDED
declare -a EXCLUDED_PATHS
while IFS= read -r line; do
	case "$line" in
	"#"* | "") continue ;;
	esac
	EXCLUDED["$line"]=1
	EXCLUDED_PATHS+=("$line")
done <"${REPO_ROOT}/COPYLEFT_EXCLUSIONS"

# Build pathspec exclude args for git diff-tree
PATHSPEC_EXCLUDES=()
for path in "${EXCLUDED_PATHS[@]}"; do
	PATHSPEC_EXCLUDES+=(":(exclude)${path}")
done

# Check if a file path is in the exclusion list.
is_excluded() {
	[[ -n "${EXCLUDED[$1]+x}" ]]
}

# Remove all excluded files from the git index and working tree.
remove_excluded_files() {
	for path in "${EXCLUDED_PATHS[@]}"; do
		git rm -rf --quiet "$path" 2>/dev/null || true
	done
}

# Return true if a commit touches at least one non-excluded file.
has_non_excluded_files() {
	[ -n "$(git diff-tree --no-commit-id --name-only -r "$1" -- . "${PATHSPEC_EXCLUDES[@]}" 2>/dev/null)" ]
}

# If a cherry-pick modifies README.md, redirect the upstream change to
# README.upstream.md and keep our fork README intact.
redirect_readme() {
	commit="$1"
	git diff --cached --name-only | grep -qx "README.md" || return 0

	staged=$(git show :README.md 2>/dev/null || true)
	ours=$(git show HEAD:README.md 2>/dev/null || true)
	if [ "$staged" != "$ours" ]; then
		git show "${commit}:README.md" >README.upstream.md 2>/dev/null || return 0
		git checkout HEAD -- README.md 2>/dev/null || true
		git add README.md README.upstream.md
	fi
}

# Try to auto-resolve cherry-pick conflicts caused by known fork
# divergences: excluded files are deleted, README.md changes are
# redirected. Returns 1 if any conflict requires manual resolution.
try_auto_resolve() {
	commit="$1"
	conflicts=$(git diff --name-only --diff-filter=U 2>/dev/null || true)
	if [ -z "$conflicts" ]; then
		return 0
	fi

	while IFS= read -r file; do
		if is_excluded "$file"; then
			git rm --quiet "$file" 2>/dev/null || true
		elif [ "$file" = "README.md" ]; then
			git show "${commit}:README.md" >README.upstream.md 2>/dev/null || return 1
			git checkout --ours README.md 2>/dev/null || true
			git add README.md README.upstream.md
		else
			echo "Manual resolution needed: $file" >&2
			return 1
		fi
	done <<<"$conflicts"
}

# Resolve a user-supplied ref to a commit SHA. Tries tag, remote
# branch, and bare SHA in that order.
resolve_ref() {
	git rev-parse --verify "refs/tags/${1}^{commit}" 2>/dev/null ||
		git rev-parse --verify "${UPSTREAM_REMOTE}/${1}" 2>/dev/null ||
		git rev-parse --verify "${1}^{commit}" 2>/dev/null ||
		{
			echo "Cannot resolve ref '${1}'" >&2
			exit 1
		}
}

# Cherry-pick each upstream commit in the given range, filtering out
# copyleft files and auto-resolving known divergences.
main() {
	if [ $# -ne 2 ]; then
		echo "Usage: $0 <from-ref> <to-ref>" >&2
		exit 1
	fi

	cd "${REPO_ROOT}"

	if ! git remote get-url "${UPSTREAM_REMOTE}" >/dev/null 2>&1; then
		git remote add "${UPSTREAM_REMOTE}" "${UPSTREAM_URL}"
	fi

	git fetch "${UPSTREAM_REMOTE}" --tags --quiet

	from_sha=$(resolve_ref "$1")
	to_sha=$(resolve_ref "$2")

	echo "Range: $1 (${from_sha:0:12}) .. $2 (${to_sha:0:12})"

	mapfile -t commits < <(git log --reverse --format="%H" "${from_sha}..${to_sha}")
	total=${#commits[@]}
	if [ "$total" -eq 0 ]; then
		echo "No commits found in range $1..$2" >&2
		exit 1
	fi

	echo "Found ${total} commits to process"

	imported=0
	skipped=0

	for i in "${!commits[@]}"; do
		commit="${commits[$i]}"
		subject=$(git log --format="%s" -1 "$commit")
		echo "--- [$((i + 1))/${total}] ${commit:0:12} ${subject}"

		if ! has_non_excluded_files "$commit"; then
			echo "  Skipping (copyleft-only)"
			skipped=$((skipped + 1))
			continue
		fi

		if ! git cherry-pick --no-commit "$commit" 2>/dev/null; then
			if ! try_auto_resolve "$commit"; then
				echo "Unresolvable conflict on ${commit:0:12}." >&2
				echo "Fix manually, then re-run with remaining range." >&2
				exit 1
			fi
		fi

		remove_excluded_files
		redirect_readme "$commit"

		if git diff --cached --quiet 2>/dev/null; then
			echo "  Skipping (empty after filtering)"
			git cherry-pick --abort 2>/dev/null || git reset --hard HEAD 2>/dev/null || true
			skipped=$((skipped + 1))
			continue
		fi

		orig_msg=$(git log --format="%B" -1 "$commit")
		footer="(cherry picked from commit ${commit})"
		GIT_AUTHOR_NAME=$(git log --format="%an" -1 "$commit") \
		GIT_AUTHOR_EMAIL=$(git log --format="%ae" -1 "$commit") \
		GIT_AUTHOR_DATE=$(git log --format="%aI" -1 "$commit") \
			git commit -m "$orig_msg" -m "$footer" --allow-empty-message 2>/dev/null

		imported=$((imported + 1))
	done

	echo ""
	echo "Done! Imported: ${imported}, Skipped: ${skipped}"
}

main "$@"
