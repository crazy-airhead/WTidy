#!/bin/bash
# 同步发布：从 GitHub Release 下载产物并发布到 CNB Release（云端 Alpine 容器执行）。
# TAG 解析顺序：
#   1) tag_push 自动触发：CNB_IS_TAG=true 时取 CNB_BRANCH（即 tag 名）
#   2) web_trigger 手动触发：按钮里填了 SYNC_TAG 则同步指定 tag（GitHub 检测失败时的可靠兜底）
#   3) 都没有时自动探测 GitHub 最新 Release（HTML 重定向 → API 兜底）
# 网络弱点已考虑：GitHub 直连可能慢或抖动，所有 curl 带超时；HEAD 探测失败走重试而非挂死。
# 依赖 curl / python3（云端 Alpine 由流水线前置 stage 安装），发布细节见 upload-cnb-release.sh。
set -euo pipefail

GH_REPO="crazy-airhead/WTidy"
BASE="https://github.com/$GH_REPO"

# 探测 GitHub 最新 Release 的 tag：先取 /releases/latest 的 GET 重定向目标（HEAD 无 302），
# 失败再走 API（匿名按 IP 限流 60 次/时，仅此单次调用）。两级都失败则输出为空。
resolve_latest_tag() {
  local url
  url="$(curl -fsL --connect-timeout 10 --max-time 30 -o /dev/null -w '%{url_effective}' \
    "$BASE/releases/latest" 2> /dev/null || true)"
  case "$url" in
    */releases/tag/*)
      printf '%s\n' "$url" | sed -E 's|.*/releases/tag/([^/?#]+).*|\1|'
      return
      ;;
  esac
  curl -fsL --connect-timeout 10 --max-time 30 \
    "https://api.github.com/repos/$GH_REPO/releases/latest" 2> /dev/null \
    | python3 -c 'import json,sys
try:
    print(json.load(sys.stdin)["tag_name"])
except Exception:
    pass' || true
}

if [ "${CNB_IS_TAG:-}" = "true" ] && [ -n "${CNB_BRANCH:-}" ]; then
  TAG="$CNB_BRANCH"
elif [ -n "${SYNC_TAG:-}" ]; then
  TAG="$SYNC_TAG"
else
  TAG="$(resolve_latest_tag)"
fi

[ -n "$TAG" ] || { echo "✗ 无法确定要同步的 tag：自动探测 GitHub 失败时，请在按钮里手动填 tag 名"; exit 1; }
VERSION="${TAG#v}"
[ "$VERSION" != "$TAG" ] || { echo "✗ tag 必须以 v 开头，实际: $TAG"; exit 1; }
ZIP="WTidy-${VERSION}-macos-arm64.zip"
URL="$BASE/releases/download/$TAG/$ZIP"

echo "==> 目标 tag: $TAG"
if [ -f "$ZIP" ]; then
  echo "==> 产物已存在，跳过下载: $ZIP"
else
  echo "==> 等待 GitHub 产物: $URL"
  ok=""
  for i in $(seq 1 40); do
    # HEAD 探测（该直链支持 HEAD）；网络抖动/404 都会进重试分支，30 秒一轮
    if curl -fsIL --connect-timeout 10 --max-time 20 -o /dev/null "$URL" 2> /dev/null; then
      echo "==> 产物已就绪（第 $i 次探测），开始下载"
      curl -fL --connect-timeout 10 --max-time 600 --retry 3 -o "$ZIP" "$URL"
      ok=1
      break
    fi
    echo "  [$i/40] GitHub 侧尚未就绪（未发布、仍在构建或网络抖动），30 秒后重试"
    sleep 30
  done
  [ -n "$ok" ] || { echo "✗ 等待超时：GitHub 上 $TAG 的产物 20 分钟内未取到（可点按钮重试，或确认该 tag 已发布）"; exit 1; }
fi
echo "✓ 下载完成: $ZIP（$(wc -c < "$ZIP") 字节）"

# upload-cnb-release.sh 默认读 CNB_BRANCH（tag_push 场景），手动/兜底场景在此显式传入
export CNB_RELEASE_TAG="$TAG"
exec bash scripts/upload-cnb-release.sh "$ZIP"
