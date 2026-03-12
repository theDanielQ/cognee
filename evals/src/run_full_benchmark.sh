#!/usr/bin/env bash
set -euo pipefail

# End-to-end runner for the 24-question / 45-run comparative benchmark.
# It runs benchmark generation on Modal, evaluates generated answers,
# and optionally runs cross-benchmark aggregation locally.

RUNS="${RUNS:-45}"
COGNEE_QA_ENGINE="${COGNEE_QA_ENGINE:-cognee_graph_completion_cot}"
GRAPHITI_RUNS="${GRAPHITI_RUNS:-45}"
VOLUME_NAME="${VOLUME_NAME:-qa-benchmarks}"
SKIP_GRAPHITI="${SKIP_GRAPHITI:-0}"
SKIP_ANALYSIS="${SKIP_ANALYSIS:-0}"

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "❌ Missing required command: $1"
    exit 1
  fi
}

print_header() {
  echo
  echo "============================================================"
  echo "$1"
  echo "============================================================"
}

extract_folder_name() {
  local line="$1"
  # Prints content after "Created benchmark folder: "
  echo "$line" | sed -n 's/^.*Created benchmark folder: \(.*\)$/\1/p' | sed 's#^/##'
}

run_modal_benchmark() {
  local system="$1"
  shift

  print_header "Running ${system} benchmark on Modal"

  local tmp
  tmp="$(mktemp)"

  # Capture output while still printing it.
  modal run "$@" 2>&1 | tee "$tmp"

  local folder
  folder="$(grep -E "Created benchmark folder:" "$tmp" | tail -n1 || true)"
  rm -f "$tmp"

  if [[ -z "$folder" ]]; then
    echo "⚠️  Could not detect benchmark folder for ${system}."
    echo "    You can still evaluate manually by running:"
    echo "    modal volume ls ${VOLUME_NAME}"
    return 1
  fi

  folder="$(extract_folder_name "$folder")"
  if [[ -z "$folder" ]]; then
    echo "⚠️  Failed to parse benchmark folder name for ${system}."
    return 1
  fi

  echo "✅ ${system} benchmark folder: ${folder}"
  BENCHMARK_FOLDERS+=("$folder")
  return 0
}

require_cmd modal
require_cmd grep
require_cmd sed

BENCHMARK_FOLDERS=()

print_header "Launching benchmark runs"

echo "Runs: ${RUNS}"
echo "Cognee QA engine: ${COGNEE_QA_ENGINE}"
echo "Graphiti runs: ${GRAPHITI_RUNS}"

echo
run_modal_benchmark "Mem0" \
  modal_apps/modal_qa_benchmark_mem0.py \
  --runs "$RUNS"

echo
run_modal_benchmark "LightRAG" \
  modal_apps/modal_qa_benchmark_lightrag.py \
  --runs "$RUNS"

echo
run_modal_benchmark "Cognee" \
  modal_apps/modal_qa_benchmark_cognee.py \
  --runs "$RUNS" \
  --qa-engine "$COGNEE_QA_ENGINE"

if [[ "$SKIP_GRAPHITI" != "1" ]]; then
  echo
  run_modal_benchmark "Graphiti" \
    modal_apps/modal_qa_benchmark_graphiti.py \
    --runs "$GRAPHITI_RUNS" \
    --corpus-limit null \
    --qa-limit null
else
  echo "⚠️  Skipping Graphiti benchmark because SKIP_GRAPHITI=1"
fi

if [[ "${#BENCHMARK_FOLDERS[@]}" -eq 0 ]]; then
  echo "❌ No benchmark folders captured; aborting evaluation stage."
  exit 1
fi

print_header "Submitting evaluation jobs"
for folder in "${BENCHMARK_FOLDERS[@]}"; do
  echo "🔄 Evaluating benchmark folder: ${folder}"
  modal run modal_apps/modal_evaluate_qa.py --benchmark-folder "$folder"
done

echo
cat <<MSG
✅ Evaluation jobs submitted.

Next steps:
1) Wait for Modal jobs to finish (dashboard/CLI).
2) Optionally run aggregation after jobs are done:
   python run_cross_benchmark_analysis.py
MSG

if [[ "$SKIP_ANALYSIS" != "1" ]]; then
  print_header "Running cross-benchmark aggregation"
  python run_cross_benchmark_analysis.py
else
  echo "⚠️  Skipping aggregation because SKIP_ANALYSIS=1"
fi
