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
  # repo별로 묶어 "로고+repo 제목 줄 + PR 불릿" 형태로 렌더링한다.
  # repo 순서는 가장 최근 머지 순, 각 PR 줄 끝에 merged 배지를 붙인다.
  awk -F'\t' '
    !($1 in seen) { order[++n]=$1; seen[$1]=1 }
    {
      cnt[$1]++
      num[$1, cnt[$1]]=$2; ttl[$1, cnt[$1]]=$3
      url[$1, cnt[$1]]=$4; dt[$1, cnt[$1]]=$5
    }
    END {
      for (i=1; i<=n; i++) {
        r=order[i]
        org=r; sub(/\/.*/, "", org)
        if (i > 1) print ""
        print "<img src=\"https://github.com/" org ".png\" width=\"20\" height=\"20\"/>&nbsp; **[" r "](https://github.com/" r ")**"
        for (j=1; j<=cnt[r]; j++) {
          badge = "![merged](https://img.shields.io/badge/merged-" dt[r, j] "-8957e5)"
          print "- [**#" num[r, j] "**](" url[r, j] ") " ttl[r, j] " " badge
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
