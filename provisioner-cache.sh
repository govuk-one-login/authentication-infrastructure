#!/bin/bash
# Helper script to manage provisioner cache

CACHE_DIR="${HOME}/.cache/provisioner"
CACHE_FILE="${CACHE_DIR}/template-versions.cache"

function usage {
  cat << USAGE
  Manage provisioner template version cache

  Usage:
    $0 <command> [options]

  Commands:
    list                List all cached entries
    clear               Clear entire cache
    remove <key>        Remove specific cache entry
    stats               Show cache statistics
    search <pattern>    Search cache entries

  Examples:
    $0 list
    $0 clear
    $0 remove "template-storage:sam-deploy-pipeline/template.yaml:v2.87.0"
    $0 search "sam-deploy-pipeline"
    $0 stats
USAGE
}

function list_cache {
  if [ ! -f "${CACHE_FILE}" ]; then
    echo "Cache is empty (file doesn't exist)"
    return
  fi

  echo "Cached template versions:"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

  while IFS='=' read -r key value; do
    # Parse key: bucket:template:version
    local template
    local version
    template=$(echo "$key" | cut -d':' -f2)
    version=$(echo "$key" | cut -d':' -f3-)

    printf "%-40s %-15s %s\n" "$template" "$version" "$value"
  done < "${CACHE_FILE}" | sort

  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

function clear_cache {
  if [ ! -f "${CACHE_FILE}" ]; then
    echo "Cache is already empty"
    return
  fi

  local count
  count=$(wc -l < "${CACHE_FILE}")
  rm -f "${CACHE_FILE}"
  echo "Cleared cache ($count entries removed)"
}

function remove_entry {
  local key="$1"

  if [ -z "$key" ]; then
    echo "Error: No key specified"
    usage
    exit 1
  fi

  if [ ! -f "${CACHE_FILE}" ]; then
    echo "Cache is empty"
    return
  fi

  if grep -q "^${key}=" "${CACHE_FILE}"; then
    grep -v "^${key}=" "${CACHE_FILE}" > "${CACHE_FILE}.tmp"
    mv "${CACHE_FILE}.tmp" "${CACHE_FILE}"
    echo "Removed cache entry: $key"
  else
    echo "Entry not found: $key"
  fi
}

function search_cache {
  local pattern="$1"

  if [ -z "$pattern" ]; then
    echo "Error: No search pattern specified"
    usage
    exit 1
  fi

  if [ ! -f "${CACHE_FILE}" ]; then
    echo "Cache is empty"
    return
  fi

  echo "Searching for: $pattern"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

  grep -i "$pattern" "${CACHE_FILE}" | while IFS='=' read -r key value; do
    local template
    local version
    template=$(echo "$key" | cut -d':' -f2)
    version=$(echo "$key" | cut -d':' -f3-)

    printf "%-40s %-15s %s\n" "$template" "$version" "$value"
  done

  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

function show_stats {
  if [ ! -f "${CACHE_FILE}" ]; then
    echo "Cache Statistics:"
    echo "  Total entries: 0"
    echo "  Cache file: ${CACHE_FILE} (doesn't exist)"
    return
  fi

  local total
  local size
  local unique_templates
  local unique_versions
  total=$(wc -l < "${CACHE_FILE}")
  size=$(du -h "${CACHE_FILE}" | cut -f1)
  unique_templates=$(cut -d':' -f2 "${CACHE_FILE}" | sort -u | wc -l)
  unique_versions=$(cut -d':' -f3- "${CACHE_FILE}" | cut -d'=' -f1 | sort -u | wc -l)

  echo "Cache Statistics:"
  echo "  Total entries: $total"
  echo "  Unique templates: $unique_templates"
  echo "  Unique versions: $unique_versions"
  echo "  Cache file size: $size"
  echo "  Cache location: ${CACHE_FILE}"
  echo ""
  echo "Most cached templates:"
  cut -d':' -f2 "${CACHE_FILE}" | sort | uniq -c | sort -rn | head -5 \
    | awk '{printf "  %3d  %s\n", $1, $2}'
}

# Main
if [ $# -lt 1 ]; then
  usage
  exit 1
fi

case "$1" in
  list)
    list_cache
    ;;
  clear)
    clear_cache
    ;;
  remove)
    remove_entry "$2"
    ;;
  search)
    search_cache "$2"
    ;;
  stats)
    show_stats
    ;;
  *)
    echo "Unknown command: $1"
    usage
    exit 1
    ;;
esac
