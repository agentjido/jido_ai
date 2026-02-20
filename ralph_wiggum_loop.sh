#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: ./ralph_wiggum_loop.sh [options]

Runs the "Ralph Wiggum" story loop:
- one Codex execution per story card
- one commit per successful story
- optional push after each commit

Options:
  --start-at ST-ID        Start at this story ID (inclusive)
  --end-at ST-ID          End at this story ID (inclusive)
  --only ST-ID            Run only one story ID
  --max N                 Process at most N selected stories
  --model MODEL           Pass model to codex exec
  --profile PROFILE       Pass profile to codex exec
  --codex-arg ARG         Extra codex exec argument (repeatable)
  --stories-dir DIR       Directory containing story markdown files (default: specs/stories)
  --traceability-file PATH Traceability matrix file (default: <stories-dir>/00_traceability_matrix.md)
  --remote NAME           Git remote for pushes (default: origin)
  --branch NAME           Remote branch name (default: current branch)
  --no-push               Commit each story but do not push
  --skip-precommit        Skip mix precommit gate (not recommended)
  --max-fix-attempts N    Max codex fix loops after precommit failure (default: 2)
  --include-completed     Do not skip stories already present in git log
  --no-auto-include-deps  Do not auto-include unmet dependencies from the backlog
  --dry-run               Print selected stories and exit
  -h, --help              Show this help

Environment variables:
  LOG_FILE                Log destination (default: .ralph_wiggum_loop.log)
  EXPECTED_STORY_COUNT    Optional warning threshold for discovered stories

Examples:
  ./ralph_wiggum_loop.sh --dry-run
  ./ralph_wiggum_loop.sh --start-at ST-OPS-001 --max 3
  ./ralph_wiggum_loop.sh --only ST-OPS-001 --no-push
USAGE
}

log() {
  printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

fail() {
  log "ERROR: $*" >&2
  exit 1
}

require_next_arg() {
  local opt="$1"
  local argc="$2"

  if [ "$argc" -lt 2 ]; then
    fail "Option ${opt} requires a value"
  fi
}

require_non_flag_value() {
  local opt="$1"
  local value="$2"

  if [ -z "$value" ] || [[ "$value" == -* ]]; then
    fail "Option ${opt} requires a non-flag value"
  fi
}

is_non_negative_integer() {
  [[ "$1" =~ ^[0-9]+$ ]]
}

assert_clean_tree() {
  local status
  status="$(git status --porcelain)"
  if [ -n "$status" ]; then
    fail "Working tree is not clean. Commit/stash changes before starting."
  fi
}

story_committed() {
  local story_id="$1"
  git log --format=%H -n 1 --extended-regexp --grep="^feat\\(story\\): ${story_id}( |$)" 2>/dev/null | grep -q .
}

story_in_records() {
  local story_id="$1"
  local record

  for record in "${selected_stories[@]}"; do
    if [ "${record%%|*}" = "$story_id" ]; then
      return 0
    fi
  done

  return 1
}

lookup_story_record() {
  local story_id="$1"
  local record

  for record in "${story_catalog[@]}"; do
    if [ "${record%%|*}" = "$story_id" ]; then
      printf '%s\n' "$record"
      return 0
    fi
  done

  return 1
}

extract_story_block() {
  local story_id="$1"
  local story_file="$2"

  awk -v story_id="$story_id" '
    BEGIN { capture = 0 }
    $0 ~ "^### " story_id " " { capture = 1 }
    capture {
      if ($0 ~ "^### ST-" && $0 !~ "^### " story_id " ") {
        exit
      }
      print
    }
  ' "$story_file"
}

extract_dependency_ids() {
  local story_id="$1"
  local story_file="$2"

  awk -v story_id="$story_id" '
    BEGIN { in_story = 0; in_deps = 0 }
    $0 ~ "^### " story_id " " { in_story = 1; next }
    in_story && $0 ~ "^### ST-" { exit }
    in_story && $0 == "#### Dependencies" { in_deps = 1; next }
    in_story && in_deps && $0 ~ "^#### " { exit }
    in_story && in_deps { print }
  ' "$story_file" \
    | tr '`' ' ' \
    | rg -o 'ST-[A-Z]+-[0-9]{3}' \
    | awk '!seen[$0]++' || true
}

validate_dependencies() {
  local story_id="$1"
  local story_file="$2"
  local dep
  local missing=()

  while IFS= read -r dep; do
    [ -z "$dep" ] && continue
    if ! story_committed "$dep"; then
      missing+=("$dep")
    fi
  done < <(extract_dependency_ids "$story_id" "$story_file")

  if [ "${#missing[@]}" -gt 0 ]; then
    printf '%s' "${missing[*]}"
    return 1
  fi

  return 0
}

build_codex_cmd() {
  CODEX_CMD=(codex exec --cd "$REPO_ROOT" --full-auto)

  if [ -n "$CODEX_MODEL" ]; then
    CODEX_CMD+=(--model "$CODEX_MODEL")
  fi

  if [ -n "$CODEX_PROFILE" ]; then
    CODEX_CMD+=(--profile "$CODEX_PROFILE")
  fi

  if [ "${#CODEX_EXTRA_ARGS[@]}" -gt 0 ]; then
    CODEX_CMD+=("${CODEX_EXTRA_ARGS[@]}")
  fi

  CODEX_CMD+=("-")
}

run_codex_prompt() {
  local prompt_file="$1"
  log "Running: ${CODEX_CMD[*]}"
  "${CODEX_CMD[@]}" < "$prompt_file" | tee -a "$LOG_FILE"
}

run_precommit_with_fix_loops() {
  local story_id="$1"
  local story_title="$2"
  local attempt=0
  local precommit_log
  local fix_prompt

  precommit_log="$(mktemp "${TMPDIR:-/tmp}/ralph-precommit.XXXXXX")"

  while true; do
    log "Running mix precommit for ${story_id}"

    if mix precommit >"$precommit_log" 2>&1; then
      cat "$precommit_log" >> "$LOG_FILE"
      rm -f "$precommit_log"
      return 0
    fi

    cat "$precommit_log" >> "$LOG_FILE"

    if [ "$attempt" -ge "$MAX_FIX_ATTEMPTS" ]; then
      log "mix precommit still failing for ${story_id} after $((attempt + 1)) run(s)"
      rm -f "$precommit_log"
      return 1
    fi

    attempt=$((attempt + 1))
    log "mix precommit failed for ${story_id}; running codex fix loop ${attempt}/${MAX_FIX_ATTEMPTS}"

    fix_prompt="$(mktemp "${TMPDIR:-/tmp}/ralph-fix-prompt.XXXXXX")"
    {
      echo "You are fixing precommit failures for one story implementation."
      echo
      echo "Story ID: ${story_id}"
      echo "Story title: ${story_title}"
      echo
      echo "Tasks:"
      echo "- fix all compile/format/test issues"
      echo "- run mix precommit and leave it passing"
      echo "- do not commit"
      echo "- do not push"
      echo "- do not implement new stories"
      echo
      echo "Latest mix precommit output:"
      echo '```text'
      tail -n 300 "$precommit_log"
      echo '```'
    } > "$fix_prompt"

    if ! run_codex_prompt "$fix_prompt"; then
      rm -f "$fix_prompt" "$precommit_log"
      return 1
    fi

    rm -f "$fix_prompt"
  done
}

START_AT=""
END_AT=""
ONLY_STORY=""
MAX_STORIES=0
CODEX_MODEL=""
CODEX_PROFILE=""
CODEX_EXTRA_ARGS=()
STORIES_DIR="specs/stories"
TRACEABILITY_FILE=""
REMOTE_NAME="origin"
TARGET_BRANCH=""
DO_PUSH=1
RUN_PRECOMMIT=1
MAX_FIX_ATTEMPTS=2
SKIP_COMPLETED=1
AUTO_INCLUDE_DEPS=1
DRY_RUN=0
LOG_FILE="${LOG_FILE:-.ralph_wiggum_loop.log}"
EXPECTED_STORY_COUNT="${EXPECTED_STORY_COUNT:-}"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --start-at)
      require_next_arg "$1" "$#"
      require_non_flag_value "$1" "$2"
      START_AT="$2"
      shift 2
      ;;
    --end-at)
      require_next_arg "$1" "$#"
      require_non_flag_value "$1" "$2"
      END_AT="$2"
      shift 2
      ;;
    --only)
      require_next_arg "$1" "$#"
      require_non_flag_value "$1" "$2"
      ONLY_STORY="$2"
      shift 2
      ;;
    --max)
      require_next_arg "$1" "$#"
      require_non_flag_value "$1" "$2"
      MAX_STORIES="$2"
      shift 2
      ;;
    --model)
      require_next_arg "$1" "$#"
      require_non_flag_value "$1" "$2"
      CODEX_MODEL="$2"
      shift 2
      ;;
    --profile)
      require_next_arg "$1" "$#"
      require_non_flag_value "$1" "$2"
      CODEX_PROFILE="$2"
      shift 2
      ;;
    --codex-arg)
      require_next_arg "$1" "$#"
      CODEX_EXTRA_ARGS+=("$2")
      shift 2
      ;;
    --stories-dir)
      require_next_arg "$1" "$#"
      require_non_flag_value "$1" "$2"
      STORIES_DIR="$2"
      shift 2
      ;;
    --traceability-file)
      require_next_arg "$1" "$#"
      require_non_flag_value "$1" "$2"
      TRACEABILITY_FILE="$2"
      shift 2
      ;;
    --remote)
      require_next_arg "$1" "$#"
      require_non_flag_value "$1" "$2"
      REMOTE_NAME="$2"
      shift 2
      ;;
    --branch)
      require_next_arg "$1" "$#"
      require_non_flag_value "$1" "$2"
      TARGET_BRANCH="$2"
      shift 2
      ;;
    --no-push)
      DO_PUSH=0
      shift
      ;;
    --skip-precommit)
      RUN_PRECOMMIT=0
      shift
      ;;
    --max-fix-attempts)
      require_next_arg "$1" "$#"
      require_non_flag_value "$1" "$2"
      MAX_FIX_ATTEMPTS="$2"
      shift 2
      ;;
    --include-completed)
      SKIP_COMPLETED=0
      shift
      ;;
    --no-auto-include-deps)
      AUTO_INCLUDE_DEPS=0
      shift
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      fail "Unknown option: $1"
      ;;
  esac
done

is_non_negative_integer "$MAX_STORIES" || fail "--max must be a non-negative integer"
is_non_negative_integer "$MAX_FIX_ATTEMPTS" || fail "--max-fix-attempts must be a non-negative integer"
if [ -n "$EXPECTED_STORY_COUNT" ]; then
  is_non_negative_integer "$EXPECTED_STORY_COUNT" || fail "EXPECTED_STORY_COUNT must be a non-negative integer"
fi

command -v rg >/dev/null 2>&1 || fail "ripgrep (rg) is required"
command -v git >/dev/null 2>&1 || fail "git is required"
if [ "$DRY_RUN" -eq 0 ]; then
  command -v codex >/dev/null 2>&1 || fail "codex CLI is required"
fi
if [ "$RUN_PRECOMMIT" -eq 1 ] && [ "$DRY_RUN" -eq 0 ]; then
  command -v mix >/dev/null 2>&1 || fail "mix is required unless --skip-precommit is set"
fi

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || fail "Must run inside a git repository"
cd "$REPO_ROOT"

if [ -z "$TRACEABILITY_FILE" ]; then
  TRACEABILITY_FILE="${STORIES_DIR}/00_traceability_matrix.md"
fi
if [ "$DRY_RUN" -eq 0 ] && [ ! -f "$TRACEABILITY_FILE" ]; then
  fail "Traceability matrix not found: $TRACEABILITY_FILE"
fi

if [ -z "$TARGET_BRANCH" ]; then
  TARGET_BRANCH="$(git symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
fi

if [ -z "$TARGET_BRANCH" ]; then
  fail "Unable to determine current branch; checkout or create a branch first"
fi

if [ "$TARGET_BRANCH" = "HEAD" ]; then
  fail "Detached HEAD is not supported; checkout a branch first"
fi

build_codex_cmd

story_rows="$(rg -n -H --no-heading '^### ST-[A-Z]+-[0-9]{3}' "${STORIES_DIR}"/[0-9][0-9]_*.md | sort -t: -k1,1 -k2,2n || true)"
[ -n "$story_rows" ] || fail "No stories found under ${STORIES_DIR}"

story_catalog=()
while IFS= read -r row; do
  [ -z "$row" ] && continue

  story_file="${row%%:*}"
  heading="${row#*:*:}"
  rest="${heading#\#\#\# }"
  story_id="${rest%% *}"
  story_title="${rest#"$story_id" }"
  story_title="$(printf '%s' "$story_title" | sed -E 's/^[^[:alnum:]]+[[:space:]]*//')"

  story_catalog+=("${story_id}|${story_file}|${story_title}")
done <<< "$story_rows"

if [ -n "$EXPECTED_STORY_COUNT" ] && [ "${#story_catalog[@]}" -ne "$EXPECTED_STORY_COUNT" ]; then
  log "Warning: expected ${EXPECTED_STORY_COUNT} stories, found ${#story_catalog[@]}"
fi

selected_stories=()
start_found=0
end_found=0

if [ -z "$START_AT" ]; then
  start_found=1
fi

for record in "${story_catalog[@]}"; do
  story_id="${record%%|*}"

  if [ -n "$ONLY_STORY" ] && [ "$story_id" != "$ONLY_STORY" ]; then
    continue
  fi

  if [ "$start_found" -eq 0 ]; then
    if [ "$story_id" = "$START_AT" ]; then
      start_found=1
    else
      continue
    fi
  fi

  selected_stories+=("$record")

  if [ -n "$END_AT" ] && [ "$story_id" = "$END_AT" ]; then
    end_found=1
    break
  fi

  if [ "$MAX_STORIES" -gt 0 ] && [ "${#selected_stories[@]}" -ge "$MAX_STORIES" ]; then
    break
  fi

done

if [ -n "$ONLY_STORY" ] && [ "${#selected_stories[@]}" -eq 0 ]; then
  fail "Story not found: $ONLY_STORY"
fi

if [ -n "$START_AT" ] && [ "$start_found" -eq 0 ]; then
  fail "Start story not found: $START_AT"
fi

if [ -n "$END_AT" ] && [ "$end_found" -eq 0 ]; then
  fail "End story not found in selected range: $END_AT"
fi

[ "${#selected_stories[@]}" -gt 0 ] || fail "No stories selected"

if [ "$AUTO_INCLUDE_DEPS" -eq 1 ]; then
  changed=1

  while [ "$changed" -eq 1 ]; do
    changed=0

    for record in "${selected_stories[@]}"; do
      story_id="${record%%|*}"
      remainder="${record#*|}"
      story_file="${remainder%%|*}"

      while IFS= read -r dep; do
        [ -z "$dep" ] && continue

        if story_committed "$dep"; then
          continue
        fi

        if story_in_records "$dep"; then
          continue
        fi

        dep_record="$(lookup_story_record "$dep" || true)"
        if [ -z "$dep_record" ]; then
          fail "Dependency $dep required by $story_id was not found in ${STORIES_DIR}"
        fi

        selected_stories+=("$dep_record")
        log "Auto-including dependency $dep required by $story_id"
        changed=1
      done < <(extract_dependency_ids "$story_id" "$story_file")
    done
  done
fi

log "Repository: $REPO_ROOT"
log "Remote/branch: $REMOTE_NAME/$TARGET_BRANCH"
log "Selected stories: ${#selected_stories[@]}"
log "Log file: $LOG_FILE"

if [ "$DRY_RUN" -eq 1 ]; then
  idx=0
  for record in "${selected_stories[@]}"; do
    idx=$((idx + 1))
    story_id="${record%%|*}"
    remainder="${record#*|}"
    story_file="${remainder%%|*}"
    story_title="${remainder#*|}"
    status="pending"

    if [ "$SKIP_COMPLETED" -eq 1 ] && story_committed "$story_id"; then
      status="already-committed"
    fi

    printf '%3d. %s [%s] %s (%s)\n' "$idx" "$story_id" "$status" "$story_title" "$story_file"
  done
  exit 0
fi

assert_clean_tree

loop_count=0
pending_stories=("${selected_stories[@]}")
pass=0

while [ "${#pending_stories[@]}" -gt 0 ]; do
  pass=$((pass + 1))
  progress_made=0
  next_pending=()
  blocked_details=()

  for record in "${pending_stories[@]}"; do
    story_id="${record%%|*}"
    remainder="${record#*|}"
    story_file="${remainder%%|*}"
    story_title="${remainder#*|}"

    if [ "$SKIP_COMPLETED" -eq 1 ] && story_committed "$story_id"; then
      log "Skipping $story_id (already in git history)"
      continue
    fi

    assert_clean_tree

    missing_deps=""
    if ! missing_deps="$(validate_dependencies "$story_id" "$story_file")"; then
      next_pending+=("$record")
      blocked_details+=("${story_id}:${missing_deps}")
      continue
    fi

    loop_count=$((loop_count + 1))
    progress_made=1
    log "Loop ${loop_count}: ${story_id} - ${story_title}"

    story_block="$(extract_story_block "$story_id" "$story_file")"
    [ -n "$story_block" ] || fail "Could not extract story block for $story_id from $story_file"

    trace_row="$(rg --no-heading "^\\| .*${story_id}.*\\|" "$TRACEABILITY_FILE" || true)"
    [ -n "$trace_row" ] || fail "Traceability row not found for $story_id"

    prompt_file="$(mktemp "${TMPDIR:-/tmp}/ralph-story-prompt.XXXXXX")"
    {
      echo "Implement exactly one backlog story in this repository."
      echo
      echo "Story ID: ${story_id}"
      echo "Story title: ${story_title}"
      echo "Story file: ${story_file}"
      echo
      echo "Traceability row:"
      echo "${trace_row}"
      echo
      echo "Story card:"
      echo '```markdown'
      printf '%s\n' "$story_block"
      echo '```'
      echo
      echo "Execution rules:"
      echo "- Follow AGENTS.md and repository conventions."
      echo "- Implement only this story."
      echo "- Do not work on other stories."
      echo "- Add or update tests for acceptance criteria."
      echo "- Run mix precommit and leave it passing."
      echo "- Do not commit."
      echo "- Do not push."
      echo "- Do not open a PR."
      echo
      echo "Final response format:"
      echo "1) changed files"
      echo "2) tests/commands executed"
      echo "3) acceptance criteria coverage"
      echo "4) blockers/assumptions"
    } > "$prompt_file"

    if ! run_codex_prompt "$prompt_file"; then
      rm -f "$prompt_file"
      fail "codex exec failed for $story_id"
    fi
    rm -f "$prompt_file"

    if [ -z "$(git status --porcelain)" ]; then
      fail "No changes detected after codex loop for $story_id"
    fi

    if [ "$RUN_PRECOMMIT" -eq 1 ]; then
      if ! run_precommit_with_fix_loops "$story_id" "$story_title"; then
        fail "mix precommit failed for $story_id"
      fi
    fi

    git add -A
    git commit -m "feat(story): ${story_id} ${story_title}" -m "Story-File: ${story_file}"

    if [ "$DO_PUSH" -eq 1 ]; then
      git push "$REMOTE_NAME" "HEAD:${TARGET_BRANCH}"
    fi

    log "Completed ${story_id}"
  done

  if [ "${#next_pending[@]}" -eq 0 ]; then
    break
  fi

  if [ "$progress_made" -eq 0 ]; then
    log "Unresolved dependency set after pass ${pass}:"
    for detail in "${blocked_details[@]}"; do
      log "  ${detail}"
    done
    fail "No progress can be made due to missing dependencies"
  fi

  log "Pass ${pass} deferred ${#next_pending[@]} story(ies) for dependency satisfaction; retrying deferred set"
  pending_stories=("${next_pending[@]}")
done

log "Story loops complete."
