#!/bin/bash
# Offline only: synthetic conversations and a temporary store; no API calls.
set -euo pipefail
task_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$task_root"
mkdir -p .build/ai-memory-qa .build/ai-qa-cache
memory_sources=(
  LifeOS/Features/Assistant/AIConversationService.swift
  LifeOS/Features/Assistant/AIConnectionStore.swift
  LifeOS/Features/Assistant/AIPlanProposal.swift
)
for task_check in AIHistoryRetrievalQA AIChatMemoryQA AIServiceQA; do
  task_extra=()
  if [ "$task_check" = AIChatMemoryQA ]; then
    task_extra=(LifeOS/Features/Assistant/AIChatMemory.swift)
  fi
  swiftc -disable-sandbox -module-cache-path .build/ai-qa-cache \
    "${memory_sources[@]}" ${task_extra[@]+"${task_extra[@]}"} "Tools/$task_check.swift" \
    -o ".build/ai-memory-qa/$task_check"
  ".build/ai-memory-qa/$task_check"
done
