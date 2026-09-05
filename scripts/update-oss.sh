#!/usr/bin/env bash
# README.md의 OSS-LIST 마커 사이를 머지된 외부 OSS PR 목록으로 갱신한다.
# 팀/스터디 repo는 EXCLUDE_RE로 제외한다.
#
# 항목이 계속 늘어나므로 전부 펼쳐두지 않고 3단으로 압축한다:
#   1) 프로젝트별 요약 칩 (건수 내림차순)
#   2) 최근 활동 RECENT_COUNT건 (머지 최신순, 평문)
#   3) 나머지는 프로젝트별로 그룹핑해 <details> 접기 안에 (전체 건수 그대로 보존)
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

USERNAME="seonwooj0810"
EXCLUDE_RE='to-be-healthy|hanghae|PKSSUN|next-step|jinho-yoo-jack'
RECENT_COUNT=8

TSV=$(mktemp)
gh api "search/issues?q=author:${USERNAME}+type:pr+is:merged+-user:${USERNAME}&per_page=100" \
  --jq '.items | sort_by(.pull_request.merged_at) | reverse | .[] | [(.repository_url | sub(".*/repos/"; "")), .number, .title, .html_url, (.pull_request.merged_at | .[0:7] | sub("-"; "."))] | @tsv' \
  | grep -Ev "$EXCLUDE_RE" > "$TSV" || true

TMP_SECTION=$(mktemp)
{
  echo "<!-- OSS-LIST:START -->"
  echo ""
  awk -F'\t' -v recent="$RECENT_COUNT" '
    function trunc(t,    r) {
      r = t
      if (length(r) > 56) r = substr(r, 1, 55) "…"
      return r
    }
    !($1 in seen) { order[++n]=$1; seen[$1]=1 }
    {
      total++
      cnt[$1]++
      num[$1, cnt[$1]]=$2; ttl[$1, cnt[$1]]=$3; url[$1, cnt[$1]]=$4
      # TSV는 이미 머지 최신순 — 그대로 "최근 활동" 원본으로 쓴다
      grec[++nrec]=$1; grecnum[nrec]=$2; grecttl[nrec]=$3; grecurl[nrec]=$4
    }
    END {
      print "**🔀 " total " PRs merged · " n " projects**"
      print ""

      # 프로젝트를 건수 내림차순으로 재배열 (동률이면 최근 등장 순 유지)
      for (i = 1; i <= n; i++) rank[i] = order[i]
      for (i = 1; i <= n; i++) {
        for (j = i + 1; j <= n; j++) {
          if (cnt[rank[j]] > cnt[rank[i]]) {
            tmp = rank[i]; rank[i] = rank[j]; rank[j] = tmp
          }
        }
      }

      print "**프로젝트별 요약**"
      print ""
      line = ""
      for (i = 1; i <= n; i++) {
        r = rank[i]
        org = r; sub(/\/.*/, "", org)
        short = r; sub(/^[^\/]*\//, "", short)
        logo = "<img src=\"https://github.com/" org ".png\" width=\"14\" height=\"14\"/>"
        chip = logo " **" short "** `" cnt[r] "`"
        line = (line == "") ? chip : line " · " chip
      }
      print line
      print ""

      print "**최근 활동**"
      print ""
      lim = (nrec < recent) ? nrec : recent
      for (i = 1; i <= lim; i++) {
        r = grec[i]
        org = r; sub(/\/.*/, "", org)
        short = r; sub(/^[^\/]*\//, "", short)
        logo = "<img src=\"https://github.com/" org ".png\" width=\"18\" height=\"18\"/>"
        full = grecttl[i]; gsub(/"/, "\\&quot;", full)
        print logo " **[" short "](https://github.com/" r ")** [**#" grecnum[i] "**](" grecurl[i] " \"" full "\") " trunc(grecttl[i]) "<br>"
      }
      print ""

      if (nrec > lim) {
        print "<details>"
        print "<summary>프로젝트별 전체 보기 (" total "건)</summary>"
        print ""
        for (i = 1; i <= n; i++) {
          r = rank[i]
          org = r; sub(/\/.*/, "", org)
          short = r; sub(/^[^\/]*\//, "", short)
          logo = "<img src=\"https://github.com/" org ".png\" width=\"16\" height=\"16\"/>"
          print logo " **[" short "](https://github.com/" r ")** `" cnt[r] "`"
          print ""
          for (j = 1; j <= cnt[r]; j++) {
            full = ttl[r, j]; gsub(/"/, "\\&quot;", full)
            print "- [**#" num[r, j] "**](" url[r, j] " \"" full "\") " trunc(ttl[r, j])
          }
          print ""
        }
        print "</details>"
        print ""
      }
    }
  ' "$TSV"
  echo "<!-- OSS-LIST:END -->"
} > "$TMP_SECTION"

awk -v section="$TMP_SECTION" '
  /<!-- OSS-LIST:START -->/ {skip=1; while ((getline line < section) > 0) print line; next}
  /<!-- OSS-LIST:END -->/ {skip=0; next}
  !skip {print}
' README.md > README.md.tmp && mv README.md.tmp README.md
rm -f "$TSV" "$TMP_SECTION"
echo "OSS 목록 갱신 완료"
