#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
demo_source="$repo_root/Examples/Demo/main.swift"
demo_output="$repo_root/Examples/Demo/output.txt"
scratch_path="${SWIFT_SCRATCH_PATH:-$HOME/Library/Caches/tzf-swift/swiftpm}"

usage() {
  cat <<'EOF'
Usage: scripts/update-demo-docs.sh [--output-only]

  --output-only   Only refresh Examples/Demo/output.txt.
EOF
}

require_marker() {
  local target="$1"
  local marker="$2"

  if [[ "$(grep -Fxc "$marker" "$target")" -ne 1 ]]; then
    echo "Expected marker '$marker' exactly once in $target" >&2
    exit 1
  fi
}

render_demo_output() {
  swift run --scratch-path "$scratch_path" demo 2>&1 \
    | awk 'BEGIN { capture = 0 } /^Beijing timezone:/ { capture = 1 } capture { print }' \
    | awk '
      /^\{"type":"FeatureCollection"/ {
        print substr($0, 1, 80) "..."
        next
      }
      { print }
    '
}

write_fenced_block() {
  local language="$1"
  local source_file="$2"
  local block_file="$3"

  {
    printf '```%s\n' "$language"
    cat "$source_file"
    printf '```\n'
  } > "$block_file"
}

replace_block() {
  local target="$1"
  local start_marker="$2"
  local end_marker="$3"
  local replacement_file="$4"
  local tmp_file

  require_marker "$target" "$start_marker"
  require_marker "$target" "$end_marker"

  tmp_file="$(mktemp)"
  awk -v start="$start_marker" -v end="$end_marker" -v replacement="$replacement_file" '
    $0 == start {
      print
      while ((getline line < replacement) > 0) {
        print line
      }
      close(replacement)
      in_block = 1
      next
    }
    $0 == end {
      in_block = 0
    }
    !in_block { print }
  ' "$target" > "$tmp_file"
  mv "$tmp_file" "$target"
}

refresh_output() {
  render_demo_output > "$demo_output"
}

refresh_docs() {
  local code_block
  local output_block

  code_block="$(mktemp)"
  output_block="$(mktemp)"

  write_fenced_block swift "$demo_source" "$code_block"
  write_fenced_block txt "$demo_output" "$output_block"

  replace_block "$repo_root/README.md" '<!-- demo-main:start -->' '<!-- demo-main:end -->' "$code_block"
  replace_block "$repo_root/README.md" '<!-- demo-output:start -->' '<!-- demo-output:end -->' "$output_block"
  replace_block "$repo_root/Sources/tzf/Documentation.docc/GettingStarted.md" '<!-- demo-main:start -->' '<!-- demo-main:end -->' "$code_block"
  replace_block "$repo_root/Sources/tzf/Documentation.docc/GettingStarted.md" '<!-- demo-output:start -->' '<!-- demo-output:end -->' "$output_block"

  rm -f "$code_block" "$output_block"
}

main() {
  case "${1:-}" in
    "")
      refresh_output
      refresh_docs
      ;;
    --output-only)
      refresh_output
      ;;
    -h|--help)
      usage
      ;;
    *)
      usage >&2
      exit 1
      ;;
  esac
}

main "$@"