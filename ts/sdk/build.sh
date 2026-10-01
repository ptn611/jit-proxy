#!/usr/bin/env bash
# Build jit-proxy TypeScript SDK (`ts/sdk/lib`) và cài vào consumer.
#
# VÌ SAO CẦN SCRIPT NÀY
# `keeper-bots-v2` phụ thuộc `@velocity-exchange/jit-proxy` qua
# `file:../jit-proxy/ts/sdk`. Package đó **không commit** `lib/` (gitignore) và
# `package.json` của nó **không có** `main`/`types`, nên consumer chỉ resolve được
# sau khi `tsc` đã build ra `lib/`. Trước đây phải build tay bằng symlink
# `node_modules` — dễ quên, và CI/localnet mới sẽ vỡ tsc.
#
# CÁCH DÙNG
#   bash jit-proxy/ts/sdk/build.sh                 # chỉ build lib
#   bash jit-proxy/ts/sdk/build.sh --install       # build + copy vào consumer
#   bash jit-proxy/ts/sdk/build.sh --install keeper-bots-v2
#
# OFFLINE: ưu tiên `tsc` của chính `ts/sdk/node_modules`; nếu chưa cài thì tìm
# `typescript` ở repo anh em (keeper-bots-v2) để không cần network. Nếu không tìm
# thấy ở đâu cả ⇒ hướng dẫn cài deps, KHÔNG tự chạy network.
set -euo pipefail

SDK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SDK_DIR/../.." && pwd)"        # jit-proxy/
MONOREPO_ROOT="$(cd "$SDK_DIR/../../.." && pwd)"  # drift-dex/

INSTALL=0
CONSUMERS=()
for arg in "$@"; do
  case "$arg" in
    --install) INSTALL=1 ;;
    -*) echo "unknown flag: $arg" >&2; exit 2 ;;
    *) CONSUMERS+=("$arg") ;;
  esac
done
if [ "$INSTALL" -eq 1 ] && [ "${#CONSUMERS[@]}" -eq 0 ]; then
  CONSUMERS=("keeper-bots-v2")
fi

# --- 1. chọn tsc -------------------------------------------------------------
TSC=""
if [ -x "$SDK_DIR/node_modules/.bin/tsc" ]; then
  TSC="$SDK_DIR/node_modules/.bin/tsc"
else
  # offline fallback: dùng typescript đã cài ở repo anh em
  for cand in keeper-bots-v2 dlob-server swift keep-rs; do
    if [ -x "$MONOREPO_ROOT/$cand/node_modules/.bin/tsc" ]; then
      TSC="$MONOREPO_ROOT/$cand/node_modules/.bin/tsc"
      echo "info: dùng tsc của $cand (ts/sdk chưa cài deps)"
      break
    fi
  done
fi

if [ -z "$TSC" ]; then
  cat >&2 <<'EOF'
error: không tìm thấy `tsc`.

Cách 1 (khuyến nghị, cần network):
  cd jit-proxy/ts/sdk && yarn install
Cách 2 (offline): cài `typescript` ở ít nhất một repo anh em, ví dụ
  cd keeper-bots-v2 && yarn install
Sau đó chạy lại script này.
EOF
  exit 1
fi

# --- 2. build ----------------------------------------------------------------
# `tsc` cần resolve `@coral-xyz/anchor`, `@velocity-exchange/sdk`, `@solana/web3.js`.
# Nếu `ts/sdk/node_modules` chưa có, trỏ tạm tới node_modules của repo đã cài sẵn
# (không sửa file trong repo, chỉ tạo symlink tạm rồi xoá).
TEMP_LINK=0
if [ ! -d "$SDK_DIR/node_modules" ] && [ -n "$TSC" ]; then
  CANDIDATE_NM="$(dirname "$(dirname "$TSC")")"
  if [ -d "$CANDIDATE_NM" ]; then
    ln -sfn "$CANDIDATE_NM" "$SDK_DIR/node_modules"
    TEMP_LINK=1
    echo "info: symlink tạm node_modules -> $CANDIDATE_NM"
  fi
fi
cleanup() {
  if [ "$TEMP_LINK" -eq 1 ] && [ -L "$SDK_DIR/node_modules" ]; then
    rm -f "$SDK_DIR/node_modules"
  fi
}
trap cleanup EXIT

rm -rf "$SDK_DIR/lib"
echo "==> tsc -p $SDK_DIR/tsconfig.json"
(cd "$SDK_DIR" && "$TSC" -p tsconfig.json)

if [ ! -f "$SDK_DIR/lib/index.d.ts" ]; then
  echo "error: build không tạo lib/index.d.ts" >&2
  exit 1
fi
echo "==> build OK: $SDK_DIR/lib ($(find "$SDK_DIR/lib" -name '*.js' | wc -l) file js)"

# --- 3. cài vào consumer -----------------------------------------------------
if [ "$INSTALL" -eq 0 ]; then
  exit 0
fi

for c in "${CONSUMERS[@]}"; do
  DEST="$MONOREPO_ROOT/$c/node_modules/@velocity-exchange/jit-proxy"
  if [ ! -d "$DEST" ]; then
    echo "warn: $DEST chưa tồn tại (chạy \`yarn install\` trong $c trước) — bỏ qua $c" >&2
    continue
  fi
  rm -rf "$DEST/lib"
  cp -r "$SDK_DIR/lib" "$DEST/lib"
  # package.json của jit-proxy/ts/sdk không khai `main`/`types`; consumer resolve
  # `@velocity-exchange/jit-proxy/lib` (deep import) nên không cần sửa ở đây.
  echo "==> đã cài lib vào $c"
done
