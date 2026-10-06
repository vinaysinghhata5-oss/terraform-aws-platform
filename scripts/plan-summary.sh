#!/usr/bin/env bash
# Render a Markdown summary of a saved Terraform plan: counts per action plus a
# resource table, with a loud warning when anything is destroyed or replaced.
# Usage: plan-summary.sh <environment> <planfile>   (run inside the env directory)
set -euo pipefail
ENVIRONMENT="${1:?environment}"
PLAN="${2:?planfile}"
TF="${TF:-terraform}"

"$TF" show -json "$PLAN" | jq -r --arg env "$ENVIRONMENT" '
  def kind:
    if   .change.actions == ["create"] then "add"
    elif .change.actions == ["update"] then "change"
    elif .change.actions == ["delete"] then "destroy"
    elif (.change.actions | length) == 2 then "replace"
    else "noop" end;
  def icon: {add: "➕", change: "🔄", replace: "♻️", destroy: "🗑️"}[.];

  [ .resource_changes[]? | {address, kind: kind} | select(.kind != "noop") ] as $rc
  | ($rc | map(select(.kind == "add"))     | length) as $add
  | ($rc | map(select(.kind == "change"))  | length) as $chg
  | ($rc | map(select(.kind == "replace")) | length) as $rep
  | ($rc | map(select(.kind == "destroy")) | length) as $del
  | [
      "### `\($env)`: ➕ \($add) to add · 🔄 \($chg) to change · ♻️ \($rep) to replace · 🗑️ \($del) to destroy",
      "",
      ( if ($rep + $del) > 0 then
          "> [!WARNING]\n> **This plan destroys or replaces \($rep + $del) resource(s)** - check for data loss:\n"
          + ($rc | map(select(.kind == "destroy" or .kind == "replace")) | map("> - \(.kind | icon) `\(.address)`") | join("\n"))
          + "\n"
        else empty end ),
      ( if ($rc | length) == 0 then "✅ No changes - infrastructure matches the code."
        else
          "| | Action | Resource |\n|---|---|---|\n"
          + ($rc | sort_by(.kind) | .[:60] | map("| \(.kind | icon) | \(.kind) | `\(.address)` |") | join("\n"))
          + (if ($rc | length) > 60 then "\n\n_…and \(($rc | length) - 60) more_" else "" end)
        end )
    ] | join("\n")
'
