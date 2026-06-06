#!/usr/bin/env bash
# README.md의 OSS-LIST 마커 사이를 머지된 외부 OSS PR 목록으로 갱신한다.
# 팀/스터디 repo는 EXCLUDE_RE로 제외한다.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

USERNAME="seonwooj0810"
EXCLUDE_RE='to-be-healthy|hanghae|PKSSUN|next-step|jinho-yoo-jack'

TSV=$(mktemp)
gh api "search/issues?q=author:${USERNAME}+type:pr+is:merged+-user:${USERNAME}&per_page=100" \
  --jq '.items | sort_by(.pull_request.merged_at) | reverse | .[] | [(.repository_url | sub(".*/repos/"; "")), .number, .title, .html_url, (.pull_request.merged_at | .[0:7] | sub("-"; "."))] | @tsv' \
  | grep -Ev "$EXCLUDE_RE" > "$TSV" || true

TMP_SECTION=$(mktemp)
{
  echo "<!-- OSS-LIST:START -->"
  echo ""
  # repo별로 묶어 테이블로 렌더링. repo 순서는 가장 최근 머지 순,
  # 같은 repo의 후속 PR은 Project 칸을 비워 그룹으로 보이게 한다.
  # Project 칸에는 org 아바타 + repo 링크, Merged 칸에는 머지 배지를 넣는다.
  awk -F'\t' '
    !($1 in seen) { order[++n]=$1; seen[$1]=1 }
    {
      cnt[$1]++
      num[$1, cnt[$1]]=$2; ttl[$1, cnt[$1]]=$3
      url[$1, cnt[$1]]=$4; dt[$1, cnt[$1]]=$5
    }
    END {
      print "| Project | Pull Request | Merged |"
      print "|:---|:---|:---:|"
      for (i=1; i<=n; i++) {
        r=order[i]
        org=r; sub(/\/.*/, "", org)
        proj = "<img src=\"https://github.com/" org ".png\" width=\"16\" height=\"16\"/> **[" r "](https://github.com/" r ")**"
        for (j=1; j<=cnt[r]; j++) {
          t=ttl[r, j]; gsub(/\|/, "\\|", t)
          badge = "![merged](https://img.shields.io/badge/merged-" dt[r, j] "-8957e5)"
          print "| " ((j==1) ? proj : "") " | [**#" num[r, j] "**](" url[r, j] ") " t " | " badge " |"
        }
      }
    }
  ' "$TSV"
  echo ""
  echo "<!-- OSS-LIST:END -->"
} > "$TMP_SECTION"

awk -v section="$TMP_SECTION" '
  /<!-- OSS-LIST:START -->/ {skip=1; while ((getline line < section) > 0) print line; next}
  /<!-- OSS-LIST:END -->/ {skip=0; next}
  !skip {print}
' README.md > README.md.tmp && mv README.md.tmp README.md
rm -f "$TSV" "$TMP_SECTION"
echo "OSS 목록 갱신 완료"
