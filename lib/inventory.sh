# shellcheck shell=bash
# lib/inventory.sh — read-only markdown scanner + 6-bucket classifier for Conjure adopt.
# Source this file; requires lib/mutate.sh, lib/log.sh, lib/caps.sh already sourced.
# POSIX bash 3.2+. No associative arrays, no mapfile, no local -n. Read-only: no mutations
# except manifest write via mutate_write.

# Module-level state: populated by inventory_scan; consumed by inventory_emit_manifest.
# Safe under set -u; idempotent on re-source.
CONJURE_INVENTORY_ITEMS="${CONJURE_INVENTORY_ITEMS:-}"
CONJURE_INVENTORY_TOTAL_FOUND="${CONJURE_INVENTORY_TOTAL_FOUND:-0}"
CONJURE_INVENTORY_SCAN_CAPPED="${CONJURE_INVENTORY_SCAN_CAPPED:-false}"

# extract_claude_md_links <target_abs>
# Extracts outbound ](path) links from CLAUDE.md at <target_abs>/CLAUDE.md.
# Writes one relative path per line to a temp file.
# Echoes the temp file path — caller is responsible for rm -f.
# If CLAUDE.md does not exist, produces an empty temp file.
extract_claude_md_links() {
  local target="$1"
  local links_file
  links_file="$(mktemp)"
  if [ -f "${target}/CLAUDE.md" ]; then
    grep -oE '\]\([^)]+\)' "${target}/CLAUDE.md" \
      | sed 's/^](\(.*\))$/\1/' \
      | grep -v '^http' \
      > "${links_file}" 2>/dev/null || true
  fi
  printf '%s' "${links_file}"
}

# inventory_classify <filepath_abs> <target_abs> <claude_md_links_file>
# Classifies a single markdown file into one of 6 deterministic buckets (D-01 through D-07).
# Classification is path-based and conservative (D-03) — never auto-promotes based on content.
# Returns bucket name via echo: core | skill | agent | planning-doc | reference-doc | unknown
# Returns "SKIP:symlink" for symlinks (not classified).
# Buckets emitted: exactly the 6 listed above — NEVER candidate-skill/candidate-agent/stale-candidate (D-02).
inventory_classify() {
  local filepath="$1"
  local target="$2"
  local links_file="$3"
  local rel

  # Skip symlinks first (M-2)
  if [ -L "${filepath}" ]; then
    echo "SKIP:symlink"
    return 0
  fi

  # Derive relative path from absolute path (strip target prefix)
  rel="${filepath#"${target}"/}"

  # Path-based decision tree per D-01 through D-07 (D-03: path-first, conservative)
  # core — root CLAUDE.md
  case "${rel}" in
    CLAUDE.md)
      echo "core"
      return 0
      ;;
  esac

  # skill — .claude/skills/*/SKILL.md
  case "${rel}" in
    .claude/skills/*/SKILL.md)
      echo "skill"
      return 0
      ;;
  esac

  # agent — .claude/agents/*.md
  case "${rel}" in
    .claude/agents/*.md)
      echo "agent"
      return 0
      ;;
  esac

  # planning-doc — .planning/**
  case "${rel}" in
    .planning/*)
      echo "planning-doc"
      return 0
      ;;
  esac

  # reference-doc by path (D-07)
  case "${rel}" in
    docs/*|README.md|CHANGELOG.md|CHANGELOG|*.adr.md|ARCHITECTURE.md|CONTRIBUTING.md)
      echo "reference-doc"
      return 0
      ;;
  esac

  # reference-doc by CLAUDE.md link (D-06/D-07)
  if grep -qxF "${rel}" "${links_file}" 2>/dev/null; then
    echo "reference-doc"
    return 0
  fi

  # Default: unknown (D-03 conservative — stays unknown, not auto-promoted)
  echo "unknown"
}

# emit_file_entry <rel_path> <classification> <line_count> <size_bytes> <cap_limit_or_null> <linked_from_json>
# Emits one JSON object (JSONL line) representing a single file in the manifest's files[] array.
# Computes size_cap_exceeded from line_count vs cap_limit.
# Uses jq -cn with --arg/--argjson for all fields (injection-safe; no shell string concat for JSON).
emit_file_entry() {
  local path="$1"
  local classification="$2"
  local line_count="$3"
  local size_bytes="$4"
  local cap_limit="$5"
  local linked_from_json="$6"
  local size_cap_exceeded="false"

  if [ -n "${cap_limit}" ] && [ "${cap_limit}" != "null" ]; then
    if [ "${line_count}" -gt "${cap_limit}" ]; then
      size_cap_exceeded="true"
    fi
  fi

  jq -cn \
    --arg path "${path}" \
    --arg classification "${classification}" \
    --argjson line_count "${line_count}" \
    --argjson size_bytes "${size_bytes}" \
    --argjson size_cap_exceeded "${size_cap_exceeded}" \
    --argjson size_cap_limit "${cap_limit:-null}" \
    --argjson linked_from "${linked_from_json}" \
    '{path: $path, classification: $classification,
      line_count: $line_count, size_bytes: $size_bytes,
      size_cap_exceeded: $size_cap_exceeded,
      size_cap_limit: $size_cap_limit,
      linked_from: $linked_from}'
}

# inventory_scan <target>
# Scans all markdown files under <target> and populates CONJURE_INVENTORY_ITEMS.
# Applies D-04 (markdown only), D-08 (500-file cap), D-10 (harness-first budget).
# Excludes: .git/, node_modules/, .conjure-adopt-backups/, .conjure-archive-*/
# Skips symlinks (M-2) and binary files.
# Sets: CONJURE_INVENTORY_ITEMS (newline-delimited), CONJURE_INVENTORY_TOTAL_FOUND, CONJURE_INVENTORY_SCAN_CAPPED
inventory_scan() {
  local target="$1"

  # D-08 two-step count: count total markdown files (before cap) using find | wc -l
  local total_found
  total_found="$(find "${target}" -name '*.md' \
    -not -path '*/.git/*' \
    -not -path '*/node_modules/*' \
    -not -path '*/.conjure-adopt-backups/*' \
    -not -path '*/.conjure-archive-*/*' \
    2>/dev/null | wc -l | tr -d ' ')"
  CONJURE_INVENTORY_TOTAL_FOUND="${total_found}"

  # D-10 harness-first budget: three separate find passes to ensure harness files take priority
  local _pass1 _pass2 _pass3 _combined _processing_list
  _pass1="$(mktemp)"
  _pass2="$(mktemp)"
  _pass3="$(mktemp)"
  _combined="$(mktemp)"
  _processing_list="$(mktemp)"

  # Pass 1: root CLAUDE.md (always first)
  find "${target}" -maxdepth 1 -name 'CLAUDE.md' \
    -not -path '*/.git/*' \
    2>/dev/null > "${_pass1}"

  # Pass 2: harness dirs — .claude/** and .planning/**
  find "${target}" -name '*.md' \
    \( -path '*/.claude/*' -o -path '*/.planning/*' \) \
    -not -path '*/.git/*' \
    -not -path '*/node_modules/*' \
    -not -path '*/.conjure-adopt-backups/*' \
    -not -path '*/.conjure-archive-*/*' \
    2>/dev/null > "${_pass2}"

  # Pass 3: all other markdown files (excluding harness dirs and root CLAUDE.md)
  find "${target}" -name '*.md' \
    -not -path '*/.claude/*' \
    -not -path '*/.planning/*' \
    -not -name 'CLAUDE.md' \
    -not -path '*/.git/*' \
    -not -path '*/node_modules/*' \
    -not -path '*/.conjure-adopt-backups/*' \
    -not -path '*/.conjure-archive-*/*' \
    2>/dev/null > "${_pass3}"

  # Also check for CLAUDE.md in subdirectories (not root level) to include in pass3
  # Note: root CLAUDE.md is in pass1; any other CLAUDE.md (e.g. in docs/) goes in pass3 via -not -name 'CLAUDE.md' exclusion above
  # That's correct per the spec — only root CLAUDE.md is special.

  # Concatenate pass1 + pass2 + pass3; deduplicate preserving order; take first 500 lines
  cat "${_pass1}" "${_pass2}" "${_pass3}" > "${_combined}"
  # Deduplicate (preserving order) using awk
  awk '!seen[$0]++' "${_combined}" | head -500 > "${_processing_list}"

  rm -f "${_pass1}" "${_pass2}" "${_pass3}" "${_combined}"

  # Set scan_capped flag
  if [ "${total_found}" -gt 500 ]; then
    CONJURE_INVENTORY_SCAN_CAPPED="true"
  else
    CONJURE_INVENTORY_SCAN_CAPPED="false"
  fi

  # Process each file: skip symlinks and binaries; accumulate into CONJURE_INVENTORY_ITEMS
  CONJURE_INVENTORY_ITEMS=""
  local _items_file
  _items_file="$(mktemp)"

  while IFS= read -r filepath; do
    [ -z "${filepath}" ] && continue
    # Skip symlinks (M-2)
    if [ -L "${filepath}" ]; then
      continue
    fi
    # Skip binary files (LC_ALL=C grep for null bytes)
    if LC_ALL=C grep -Pc '\x00' "${filepath}" 2>/dev/null | grep -q '^[1-9]'; then
      continue
    fi
    printf '%s\n' "${filepath}" >> "${_items_file}"
  done < "${_processing_list}"

  rm -f "${_processing_list}"

  # Read accumulated items into CONJURE_INVENTORY_ITEMS (newline-delimited)
  CONJURE_INVENTORY_ITEMS="$(cat "${_items_file}")"
  rm -f "${_items_file}"
}

# inventory_emit_manifest <target_abs> <output_path>
# Builds and emits adopt-manifest.json with all required top-level keys.
# Calls inventory_scan if CONJURE_INVENTORY_ITEMS is empty.
# DRY_RUN=1: writes to /tmp/adopt-manifest-dryrun.json instead of output_path.
# Calls log_step INVENTORY after writing.
inventory_emit_manifest() {
  local target="$1"
  local output_path="$2"

  # Internal guard: scan if not yet done
  if [ -z "${CONJURE_INVENTORY_ITEMS}" ]; then
    inventory_scan "${target}"
  fi

  # Extract CLAUDE.md outbound links for D-06/D-07 reference-doc classification
  local links_file
  links_file="$(extract_claude_md_links "${target}")"

  # Temp files for JSONL accumulation (avoids ARG_MAX issue — Pitfall 6)
  local _items_jsonl _violations_jsonl
  _items_jsonl="$(mktemp)"
  _violations_jsonl="$(mktemp)"

  # Per-bucket counters
  local core_count=0 skill_count=0 agent_count=0
  local planning_count=0 reference_count=0 unknown_count=0
  local total_files=0

  # Iterate CONJURE_INVENTORY_ITEMS (mktemp + while IFS= read -r — POSIX bash 3.2 compatible)
  local _scan_list
  _scan_list="$(mktemp)"
  printf '%s\n' "${CONJURE_INVENTORY_ITEMS}" > "${_scan_list}"

  while IFS= read -r filepath; do
    [ -z "${filepath}" ] && continue
    [ ! -f "${filepath}" ] && continue

    # Derive relative path
    local rel
    rel="${filepath#"${target}"/}"

    # Classify
    local classification
    classification="$(inventory_classify "${filepath}" "${target}" "${links_file}")"

    # Skip symlinks (already filtered in inventory_scan but double-check)
    if [ "${classification}" = "SKIP:symlink" ]; then
      continue
    fi

    # Get line count (redirect form — no filename noise)
    local line_count
    line_count="$(wc -l < "${filepath}" | tr -d ' ')"

    # Get size in bytes (cross-platform: wc -c)
    local size_bytes
    size_bytes="$(wc -c < "${filepath}" | tr -d ' ')"

    # Determine cap limit based on classification
    local cap_limit="null"
    case "${classification}" in
      core)    cap_limit="${CLAUDE_MD_CAP:-100}" ;;
      skill)   cap_limit="${SKILL_MD_CAP:-200}" ;;
      agent)   cap_limit="${AGENT_MD_CAP:-80}" ;;
      *)       cap_limit="null" ;;
    esac

    # Determine linked_from (D-06: check if this file's rel path is in CLAUDE.md links)
    local linked_from_json="[]"
    if grep -qxF "${rel}" "${links_file}" 2>/dev/null; then
      linked_from_json='["CLAUDE.md"]'
    fi

    # Emit file entry to JSONL accumulator
    emit_file_entry "${rel}" "${classification}" "${line_count}" "${size_bytes}" "${cap_limit}" "${linked_from_json}" \
      >> "${_items_jsonl}"

    # Check size_cap_exceeded and accumulate violations
    local size_cap_exceeded="false"
    if [ "${cap_limit}" != "null" ] && [ "${line_count}" -gt "${cap_limit}" ]; then
      size_cap_exceeded="true"
      local overage=$((line_count - cap_limit))
      jq -cn \
        --arg path "${rel}" \
        --argjson line_count "${line_count}" \
        --argjson cap "${cap_limit}" \
        --argjson overage "${overage}" \
        '{path: $path, line_count: $line_count, cap: $cap, overage: $overage}' \
        >> "${_violations_jsonl}"
    fi

    # Increment bucket counters
    case "${classification}" in
      core)          core_count=$((core_count + 1)) ;;
      skill)         skill_count=$((skill_count + 1)) ;;
      agent)         agent_count=$((agent_count + 1)) ;;
      planning-doc)  planning_count=$((planning_count + 1)) ;;
      reference-doc) reference_count=$((reference_count + 1)) ;;
      unknown)       unknown_count=$((unknown_count + 1)) ;;
    esac
    total_files=$((total_files + 1))

  done < "${_scan_list}"
  rm -f "${_scan_list}"

  # Determine harness_missing_layers
  local _missing_layers_jsonl
  _missing_layers_jsonl="$(mktemp)"
  [ ! -f "${target}/CLAUDE.md" ]          && printf '"CLAUDE.md"\n' >> "${_missing_layers_jsonl}"
  [ ! -d "${target}/.claude/skills" ]     && printf '"skills"\n'   >> "${_missing_layers_jsonl}"
  [ ! -d "${target}/.claude/agents" ]     && printf '"agents"\n'   >> "${_missing_layers_jsonl}"
  [ ! -d "${target}/.claude/hooks" ]      && printf '"hooks"\n'    >> "${_missing_layers_jsonl}"

  # Get conjure version
  local conjure_version="unknown"
  if [ -n "${CONJURE_HOME:-}" ] && [ -f "${CONJURE_HOME}/VERSION" ]; then
    conjure_version="$(cat "${CONJURE_HOME}/VERSION")"
  fi

  local generated_at
  generated_at="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

  local scan_capped="${CONJURE_INVENTORY_SCAN_CAPPED:-false}"
  local total_found="${CONJURE_INVENTORY_TOTAL_FOUND:-${total_files}}"

  # Build manifest using jq -cn with --slurpfile for large arrays (Pitfall 6)
  local manifest_content
  manifest_content="$(jq -cn \
    --slurpfile files "${_items_jsonl}" \
    --slurpfile violations "${_violations_jsonl}" \
    --slurpfile missing_layers "${_missing_layers_jsonl}" \
    --arg schema_version "1" \
    --arg generated_at "${generated_at}" \
    --arg conjure_version "${conjure_version}" \
    --arg target "$(cd "${target}" && pwd)" \
    --arg snapshot_path "" \
    --argjson scan_capped "${scan_capped}" \
    --argjson total_found "${total_found}" \
    --argjson total_files "${total_files}" \
    --argjson core "${core_count}" \
    --argjson skill "${skill_count}" \
    --argjson agent "${agent_count}" \
    --argjson planning_doc "${planning_count}" \
    --argjson reference_doc "${reference_count}" \
    --argjson unknown "${unknown_count}" \
    '{
      schema_version: $schema_version,
      generated_at: $generated_at,
      conjure_version: $conjure_version,
      target: $target,
      snapshot_path: $snapshot_path,
      summary: {
        total_files: $total_files,
        scan_capped: $scan_capped,
        total_found: $total_found,
        core: $core,
        skill: $skill,
        agent: $agent,
        "planning-doc": $planning_doc,
        "reference-doc": $reference_doc,
        unknown: $unknown
      },
      files: $files,
      size_cap_violations: $violations,
      harness_missing_layers: $missing_layers,
      restructure_steps: []
    }')"

  rm -f "${_items_jsonl}" "${_violations_jsonl}" "${_missing_layers_jsonl}" "${links_file}"

  # DRY_RUN=1: redirect to /tmp path; otherwise use caller-supplied output_path
  local actual_output_path="${output_path}"
  if [ "${DRY_RUN:-0}" = "1" ]; then
    actual_output_path="/tmp/adopt-manifest-dryrun.json"
  fi

  mutate_write "${actual_output_path}" "${manifest_content}"

  # Log the inventory operation
  if [ -n "${RESTRUCTURE_LOG_PATH:-}" ]; then
    log_step INVENTORY "scanned ${CONJURE_INVENTORY_TOTAL_FOUND:-?} files → ${actual_output_path}"
  fi

  # Print summary to stdout
  printf 'Inventoried %s files (%s core, %s skill, %s agent, %s planning-doc, %s reference-doc, %s unknown)\n' \
    "${total_files}" "${core_count}" "${skill_count}" "${agent_count}" \
    "${planning_count}" "${reference_count}" "${unknown_count}"

  if [ "${scan_capped}" = "true" ]; then
    printf '%s found, scanned 500 — rerun with --full-inventory to process all files\n' "${total_found}"
  fi
}
