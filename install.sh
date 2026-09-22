#!/usr/bin/env bash
set -euo pipefail

REPOSITORY="KaworuNagisa-hhl/ModelSentinel"
VERSION="${MODEL_SENTINEL_VERSION:-0.2.0}"
INSTALL_DIRECTORY="${MODEL_SENTINEL_INSTALL_DIR:-$HOME/Applications}"
ASSET_NAME="ModelSentinel-v${VERSION}-macOS-arm64.zip"
RELEASE_BASE_URL="https://github.com/${REPOSITORY}/releases/download/v${VERSION}"
TEMP_DIRECTORY="$(mktemp -d)"
STAGED_APP="$INSTALL_DIRECTORY/.ModelSentinel.installing.$$"

cleanup() {
  rm -rf "$TEMP_DIRECTORY" "$STAGED_APP"
}
trap cleanup EXIT

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "ModelSentinel 目前只支持 macOS。" >&2
  exit 1
fi

if [[ "$(uname -m)" != "arm64" ]]; then
  echo "当前 Release 只支持 Apple Silicon（arm64）。" >&2
  exit 1
fi

for command_name in curl shasum ditto codesign; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "缺少系统命令：$command_name" >&2
    exit 1
  fi
done

echo "正在下载 ModelSentinel v${VERSION}…"
curl --fail --location --silent --show-error --retry 3 \
  "$RELEASE_BASE_URL/$ASSET_NAME" \
  --output "$TEMP_DIRECTORY/$ASSET_NAME"
curl --fail --location --silent --show-error --retry 3 \
  "$RELEASE_BASE_URL/SHA256SUMS.txt" \
  --output "$TEMP_DIRECTORY/SHA256SUMS.txt"

if ! grep -F "  $ASSET_NAME" "$TEMP_DIRECTORY/SHA256SUMS.txt" >/dev/null; then
  echo "校验文件中没有当前安装包记录，安装已停止。" >&2
  exit 1
fi

(
  cd "$TEMP_DIRECTORY"
  shasum -a 256 -c SHA256SUMS.txt
)

ditto -x -k "$TEMP_DIRECTORY/$ASSET_NAME" "$TEMP_DIRECTORY/unpacked"
SOURCE_APP="$TEMP_DIRECTORY/unpacked/ModelSentinel Release/ModelSentinel.app"
if [[ ! -d "$SOURCE_APP" ]]; then
  echo "安装包结构无效：找不到 ModelSentinel.app。" >&2
  exit 1
fi

if ! codesign --verify --deep --strict "$SOURCE_APP"; then
  echo "应用签名结构校验失败，安装已停止。" >&2
  exit 1
fi

mkdir -p "$INSTALL_DIRECTORY"
ditto "$SOURCE_APP" "$STAGED_APP"

DESTINATION_APP="$INSTALL_DIRECTORY/ModelSentinel.app"
BACKUP_APP=""
if [[ -e "$DESTINATION_APP" ]]; then
  BACKUP_APP="$INSTALL_DIRECTORY/ModelSentinel.backup-$(date +%Y%m%d-%H%M%S)-$$.app"
  mv "$DESTINATION_APP" "$BACKUP_APP"
  echo "旧版本已备份到：$BACKUP_APP"
fi

if ! mv "$STAGED_APP" "$DESTINATION_APP"; then
  if [[ -n "$BACKUP_APP" && -e "$BACKUP_APP" ]]; then
    mv "$BACKUP_APP" "$DESTINATION_APP"
  fi
  echo "安装失败，原版本已恢复。" >&2
  exit 1
fi

echo "安装完成：$DESTINATION_APP"
echo "说明：当前预览版尚未 Apple 公证；如果被 macOS 拦截，请在“系统设置 → 隐私与安全性”中选择“仍要打开”。"

if [[ "${MODEL_SENTINEL_NO_LAUNCH:-0}" != "1" ]]; then
  open "$DESTINATION_APP" || true
fi
