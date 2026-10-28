#!/usr/bin/env bash
# README.md의 OSS-LIST 마커 사이를 머지된 외부 OSS PR 목록으로 갱신한다.
# 팀/스터디 repo는 EXCLUDE_RE로 제외한다.
#
# 항목이 계속 늘어나므로 전부 펼쳐두지 않는다: 머지 건수 배지 아래 <details> 접기 안에
# 프로젝트별(건수 내림차순)로 그룹핑한 전체 목록을 둔다.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

USERNAME="seonwooj0810"
EXCLUDE_RE='to-be-healthy|hanghae|PKSSUN|next-step|jinho-yoo-jack|ddak[-_]league'
# 본인이 멤버인 조직은 검색 쿼리에서 바로 뺀다. grep으로 나중에 거르면 per_page=100 한도를
# 본인 조직 PR이 먼저 차지해 외부 OSS PR이 잘린다.
# ponytail: 단일 페이지(100건) 조회. 외부 PR이 100건을 넘으면 페이지네이션 필요
#
# 비공개 멤버십까지 보려면 read:org 토큰이 필요하다. Actions 기본 GITHUB_TOKEN으로는
# user/orgs를 못 읽으므로 CI에서는 ORG_READ_TOKEN 시크릿(classic PAT, read:org)을 쓰고,
# 로컬에서는 gh 로그인 토큰을 그대로 쓴다.
# 조회가 실패하면 set -e로 여기서 중단된다 — 조직 필터 없이 갱신되면 본인 조직 PR이 다시 섞인다.
OWN_ORGS=$(GH_TOKEN="${ORG_READ_TOKEN:-${GH_TOKEN:-$(gh auth token)}}" gh api --paginate user/orgs --jq '.[].login')
if [ -z "$OWN_ORGS" ]; then
  echo "갱신 실패: 소속 조직 목록이 비어 있다(ORG_READ_TOKEN 만료 여부 확인). README.md를 유지한다." >&2
  exit 1
fi
ORG_FILTER=$(printf '+-org:%s' $OWN_ORGS)

TSV=$(mktemp)
# 제목 자르기는 여기(jq)에서 끝낸다. awk의 length()/substr()는 바이트 기준이라
# 한글 같은 멀티바이트 문자를 중간에서 잘라 깨뜨린다(3바이트 중 2바이트만 남음).
# jq는 코드포인트 기준이라 문자 경계를 지킨다.
gh api "search/issues?q=author:${USERNAME}+type:pr+is:merged+-user:${USERNAME}${ORG_FILTER}&per_page=100" \
  --jq '.items | sort_by(.pull_request.merged_at) | reverse | .[]
        | [ (.repository_url | sub(".*/repos/"; ""))
          , .number
          , .title
          , (if (.title | length) > 56 then (.title[0:55] + "…") else .title end)
          , .html_url
          , (.pull_request.merged_at | .[0:7] | sub("-"; "."))
          ] | @tsv' \
  | grep -Ev "$EXCLUDE_RE" > "$TSV" || true

TMP_SECTION=$(mktemp)
{
  echo "<!-- OSS-LIST:START -->"
  echo ""
  # TSV 컬럼: 1=repo 2=번호 3=제목(전체, 툴팁용) 4=제목(잘림, 표시용) 5=URL 6=머지월
  # LC_ALL=C: awk를 바이트 모드로 돌린다. 여기서 쓰는 정규식·구분자는 전부 ASCII라
  # 문자 단위 해석이 필요 없고, UTF-8 본문은 바이트 그대로 통과시키는 게 안전하다.
  LC_ALL=C awk -F'\t' '
    !($1 in seen) { order[++n]=$1; seen[$1]=1 }
    {
      total++
      cnt[$1]++
      num[$1, cnt[$1]]=$2; ttl[$1, cnt[$1]]=$3; cut[$1, cnt[$1]]=$4; url[$1, cnt[$1]]=$5
    }
    END {
      print "<p>"
      print "  <img alt=\"Merged PRs: " total "\" src=\"https://img.shields.io/badge/Merged_PRs-" total "-704ad1?style=for-the-badge&amp;labelColor=242438\"/>"
      print "  <img alt=\"Projects contributed: " n "\" src=\"https://img.shields.io/badge/Projects-" n "-704ad1?style=for-the-badge&amp;labelColor=242438\"/>"
      print "</p>"
      print ""
      print "<details>"
      print "<summary>전체 기여 내역 · " total " PRs / " n " projects</summary>"
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

      for (i = 1; i <= n; i++) {
        r = rank[i]
        org = r; sub(/\/.*/, "", org)
        short = r; sub(/^[^\/]*\//, "", short)
        logo = "<img src=\"https://github.com/" org ".png\" width=\"16\" height=\"16\"/>"
        print logo " **[" short "](https://github.com/" r ")** `" cnt[r] "`"
        print ""
        for (j = 1; j <= cnt[r]; j++) {
          full = ttl[r, j]; gsub(/"/, "\\&quot;", full)
          print "- [**#" num[r, j] "**](" url[r, j] " \"" full "\") " cut[r, j]
        }
        print ""
      }
      print "</details>"
      print ""
    }
  ' "$TSV"
  echo "<!-- OSS-LIST:END -->"
} > "$TMP_SECTION"

# LC_ALL=C 없이 돌리면 README에 깨진 바이트가 한 번이라도 섞였을 때
# awk가 towc 실패로 죽어(exit 2) 갱신이 조용히 no-op이 된다.
LC_ALL=C awk -v section="$TMP_SECTION" '
  /<!-- OSS-LIST:START -->/ {skip=1; while ((getline line < section) > 0) print line; next}
  /<!-- OSS-LIST:END -->/ {skip=0; next}
  !skip {print}
' README.md > README.md.tmp

# 갱신 결과를 실제로 검증한 뒤에만 교체한다. "에러 없음"은 성공의 증거가 아니다.
for marker in '<!-- OSS-LIST:START -->' '<!-- OSS-LIST:END -->' '<!-- BLOG-POST-LIST:START -->'; do
  if ! LC_ALL=C grep -qF "$marker" README.md.tmp; then
    echo "갱신 실패: 결과물에 '$marker' 가 없다. README.md를 유지한다." >&2
    rm -f README.md.tmp; exit 1
  fi
done
# 이 스크립트가 만든 섹션은 반드시 유효해야 한다 — 여기가 깨지면 갱신을 중단한다.
if ! iconv -f UTF-8 -t UTF-8 "$TMP_SECTION" > /dev/null 2>&1; then
  echo "갱신 실패: 생성한 OSS 섹션에 잘못된 UTF-8 바이트가 있다. README.md를 유지한다." >&2
  rm -f README.md.tmp; exit 1
fi
# 섹션 밖(블로그 등 다른 워크플로 관리 영역)의 기존 손상까지 이 스크립트가 고칠 수는
# 없다. 남의 영역 문제로 OSS 갱신을 매일 실패시키지 말고, 경고만 남기고 진행한다.
if ! iconv -f UTF-8 -t UTF-8 README.md.tmp > /dev/null 2>&1; then
  echo "경고: OSS 섹션 밖에 잘못된 UTF-8 바이트가 있다. 확인이 필요하다." >&2
fi
mv README.md.tmp README.md

rm -f "$TSV" "$TMP_SECTION"
echo "OSS 목록 갱신 완료"
