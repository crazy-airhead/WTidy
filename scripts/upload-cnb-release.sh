#!/bin/bash
# 发布 zip 到 CNB Release：创建/更新 Release → 预签名 URL 上传附件 → 确认关联。
# 运行环境：CNB 云端流水线（Alpine，curl/python3 由前置 stage 安装），本地 macOS 亦可调试。
# 用法: scripts/upload-cnb-release.sh <zip 文件>
# 依赖 CNB 流水线内置环境变量：
#   CNB_TOKEN      临时令牌（tag_push 下含 repo-release:rw，日志自动打码）
#   CNB_REPO_SLUG  仓库路径（如 goldsyear/allblue/WTidy）
#   CNB_BRANCH     tag_push 事件下为触发的 tag 名
# API 定义见 https://api.cnb.cool/swagger.json（Releases / asset-upload-url / asset-upload-confirmation）。
set -euo pipefail

API="https://api.cnb.cool"
ZIP="${1:?用法: upload-cnb-release.sh <zip 文件>}"
[ -f "$ZIP" ] || { echo "✗ 找不到 $ZIP"; exit 1; }
: "${CNB_TOKEN:?CNB_TOKEN 未设置（仅限 CNB tag_push 流水线内运行）}"
: "${CNB_REPO_SLUG:?CNB_REPO_SLUG 未设置}"
# tag 来源：tag_push 事件读内置 CNB_BRANCH；web_trigger 手动场景由 sync 脚本传 CNB_RELEASE_TAG
TAG="${CNB_RELEASE_TAG:-${CNB_BRANCH:-}}"
[ -n "$TAG" ] || { echo "✗ 无法确定 tag（CNB_RELEASE_TAG / CNB_BRANCH 均未设置）"; exit 1; }
AUTH="Authorization: Bearer $CNB_TOKEN"
NAME="$(basename "$ZIP")"

# 正文含中文与反引号，统一用 python3 组 JSON 保证转义正确
mk_json() { python3 -I -c "$1" "${@:2}"; }

BODY="$(cat <<EOF
WTidy ${TAG} —— 原生重制的 macOS 窗口分屏工具

下载下方 \`${NAME}\`，解压后将 \`WTidy.app\` 拖入「应用程序」。

> **macOS 未公证提示**：应用为 ad-hoc 签名，首次打开若提示无法验证开发者，
> **右键 App →「打开」**，或执行 \`xattr -d com.apple.quarantine /Applications/WTidy.app\` 后再打开。

- Apple Silicon（arm64）原生，需 macOS 13.0 及以上
- 首次启动请在 系统设置 → 隐私与安全性 → 辅助功能 中授权 WTidy
- 使用文档：https://crazy-airhead.github.io/WTidy/
- 完整变更：https://crazy-airhead.github.io/WTidy/changelog
- GitHub 同步发布：https://github.com/crazy-airhead/WTidy/releases/tag/${TAG}
EOF
)"

# Release 已存在则复用 id 并更新标题与描述，否则创建（tag_push 下令牌含 repo-release:rw）
EXISTING="$(curl -sf --connect-timeout 10 --max-time 30 -H "$AUTH" "$API/$CNB_REPO_SLUG/-/releases/tags/$TAG" || true)"
if [ -n "$EXISTING" ]; then
  RELEASE_ID="$(printf '%s' "$EXISTING" | mk_json 'import json,sys; print(json.load(sys.stdin)["id"])')"
  echo "==> Release $TAG 已存在（id=$RELEASE_ID），更新标题与描述"
  PAYLOAD="$(mk_json 'import json,sys; print(json.dumps({"name":sys.argv[1],"body":sys.argv[2]}))' "WTidy ${TAG}" "$BODY")"
  curl -sf --connect-timeout 10 --max-time 30 -X PATCH -H "$AUTH" -H "Content-Type: application/json" \
    "$API/$CNB_REPO_SLUG/-/releases/$RELEASE_ID" -d "$PAYLOAD" > /dev/null
else
  echo "==> 创建 Release $TAG"
  PAYLOAD="$(mk_json 'import json,sys; print(json.dumps({"tag_name":sys.argv[1],"name":sys.argv[2],"body":sys.argv[3],"prerelease":False,"make_latest":"true"}))' "$TAG" "WTidy ${TAG}" "$BODY")"
  CREATED="$(curl -sf --connect-timeout 10 --max-time 30 -X POST -H "$AUTH" -H "Content-Type: application/json" \
    "$API/$CNB_REPO_SLUG/-/releases" -d "$PAYLOAD")"
  RELEASE_ID="$(printf '%s' "$CREATED" | mk_json 'import json,sys; print(json.load(sys.stdin)["id"])')"
fi

# 附件三步走：申请预签名上传地址（overwrite=true 幂等重跑）→ PUT 上传 → 确认
# wc -c 是为了可移植（云端 Alpine 容器与本地 macOS 均可用）
SIZE="$(wc -c < "$ZIP" | tr -d ' ')"
echo "==> 申请附件上传地址（$NAME，$SIZE 字节）"
PAYLOAD="$(mk_json 'import json,sys; print(json.dumps({"asset_name":sys.argv[1],"size":int(sys.argv[2]),"overwrite":True}))' "$NAME" "$SIZE")"
RESP="$(curl -sf --connect-timeout 10 --max-time 30 -X POST -H "$AUTH" -H "Content-Type: application/json" \
  "$API/$CNB_REPO_SLUG/-/releases/$RELEASE_ID/asset-upload-url" -d "$PAYLOAD")"
UPLOAD_URL="$(printf '%s' "$RESP" | mk_json 'import json,sys; print(json.load(sys.stdin)["upload_url"])')"
VERIFY_URL="$(printf '%s' "$RESP" | mk_json 'import json,sys; print(json.load(sys.stdin)["verify_url"])')"

echo "==> 上传附件"
curl -sf --connect-timeout 10 --max-time 600 -X PUT \
  -H "Content-Type: application/octet-stream" --upload-file "$ZIP" "$UPLOAD_URL"

# verify_url 为确认接口（/asset-upload-confirmation/...），补全域名并追加 ttl=0（0=永久保留，最大 180 天）
case "$VERIFY_URL" in
  http*) ;;
  *) VERIFY_URL="$API/$VERIFY_URL" ;;
esac
case "$VERIFY_URL" in
  *\?*) VERIFY_URL="$VERIFY_URL&ttl=0" ;;
  *) VERIFY_URL="$VERIFY_URL?ttl=0" ;;
esac
echo "==> 确认附件上传"
curl -sf --connect-timeout 10 --max-time 30 -X POST -H "$AUTH" "$VERIFY_URL" > /dev/null

echo "✓ 已发布 $TAG：附件 $NAME 可在 CNB 仓库 Release 页下载"
