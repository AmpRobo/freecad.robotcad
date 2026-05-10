#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPOS_FILE="${ROOT}/module.repos"
MODULES_DIR="${ROOT}/modules"

usage() {
  cat <<'EOF'
Install git repositories from module.repos into ./modules using git clone.

Usage:
  install-modules.sh [--skip-existing]

Options:
  --skip-existing   Skip clone if the target directory already exists.

Requires: git
EOF
}

SKIP_EXISTING=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    --skip-existing)
      SKIP_EXISTING=1
      shift
      ;;
    *)
      echo "error: unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ ! -f "$REPOS_FILE" ]]; then
  echo "error: missing $REPOS_FILE" >&2
  exit 1
fi

if ! command -v git >/dev/null 2>&1; then
  echo "error: 'git' not found." >&2
  exit 1
fi

# vcstool-style module.repos (YAML subset): repositories -> name -> type, url, version
flush_repo() {
  if [[ -z "$current_name" ]]; then
    return 0
  fi
  if [[ -z "$url" ]]; then
    echo "warning: repository '$current_name' has no url, skipping" >&2
  elif [[ "$repo_type" != "git" ]]; then
    echo "warning: repository '$current_name' type '$repo_type' is not supported, skipping" >&2
  else
    local dest="${MODULES_DIR}/${current_name}"
    if [[ "$SKIP_EXISTING" -eq 1 ]] && [[ -e "$dest" ]]; then
      echo "skip existing: ${current_name}"
    else
      mkdir -p "$MODULES_DIR"
      if [[ -n "$version" ]]; then
        git clone --branch "$version" --single-branch "$url" "$dest"
      else
        git clone "$url" "$dest"
      fi
    fi
  fi
  current_name=""
  repo_type="git"
  url=""
  version=""
}

current_name=""
repo_type="git"
url=""
version=""
in_repositories=0

while IFS= read -r raw_line || [[ -n "$raw_line" ]]; do
  line="${raw_line%%#*}"
  line="${line%"${line##*[![:space:]]}"}"

  if [[ -z "$line" ]]; then
    continue
  fi

  if [[ "$line" == "repositories:" ]]; then
    in_repositories=1
    continue
  fi
  [[ "$in_repositories" -eq 0 ]] && continue

  # Top-level repo key: exactly two leading spaces, third char not space, ends with ':'
  if [[ "${#line}" -ge 3 && "${line:0:2}" == "  " && "${line:2:1}" != " " && "$line" =~ ^[^:]+:[[:space:]]*$ ]]; then
    flush_repo
    current_name="${line#  }"
    current_name="${current_name%%:*}"
    repo_type="git"
    url=""
    version=""
    continue
  fi

  if [[ -z "$current_name" ]]; then
    continue
  fi

  if [[ "$line" =~ ^[[:space:]]*url:[[:space:]]*(.*)$ ]]; then
    url="${BASH_REMATCH[1]}"
    url="${url%"${url##*[![:space:]]}"}"
  elif [[ "$line" =~ ^[[:space:]]*version:[[:space:]]*(.*)$ ]]; then
    version="${BASH_REMATCH[1]}"
    version="${version%"${version##*[![:space:]]}"}"
  elif [[ "$line" =~ ^[[:space:]]*type:[[:space:]]*(.*)$ ]]; then
    repo_type="${BASH_REMATCH[1]}"
    repo_type="${repo_type%"${repo_type##*[![:space:]]}"}"
  fi
done <"$REPOS_FILE"

flush_repo
