#!/usr/bin/env bash
#
# fan-random - 随机壁纸 API 卸载脚本
# 停止并移除 systemd 服务 / 后台进程，删除程序目录，可选删除图片目录与安装记录。
#
# Usage: bash scripts/uninstall.sh [-y] [--purge|--keep-data] [-q]

set -e

APP_NAME="fan-random"
DEFAULT_APP_DIR="/var/lib/${APP_NAME}"
DEFAULT_IMAGE_DIR="/var/lib/${APP_NAME}/public"
DEFAULT_PC_DIR="/var/lib/${APP_NAME}/public/pc"
DEFAULT_MP_DIR="/var/lib/${APP_NAME}/public/mp"
DEFAULT_PORT=8588
CONFIG_FILE="/etc/${APP_NAME}.conf"
SERVICE_FILE="/etc/systemd/system/${APP_NAME}.service"
CLI_BIN="/usr/local/bin/${APP_NAME}"

# ================== terminal colors ==================
list_color_init() {
    export gl_hui=$'\033[38;5;59m'
    export gl_hong=$'\033[38;5;9m'
    export gl_lv=$'\033[38;5;10m'
    export gl_huang=$'\033[38;5;11m'
    export gl_lan=$'\033[38;5;32m'
    export gl_bai=$'\033[38;5;15m'
    export gl_zi=$'\033[38;5;13m'
    export gl_bufan=$'\033[38;5;14m'
    export reset=$'\033[0m'
}
list_color_init

sep_line() {
  printf '%s' "$gl_bufan"
  printf '—%.0s' {1..32}
  printf '%s\n' "$reset"
}

section() {
  printf "  %s %s\n" "${gl_zi}▶${reset}" "$1"
}

ok() {
  printf "  %s %s\n" "${gl_lv}>>>${reset}" "$1"
}

skip() {
  printf "  %s %s\n" "${gl_hui}--${reset}" "$1"
}

print_banner() {
  local z="$gl_zi" r="$reset" b="$gl_bai" l="$gl_lan"
  printf '%s\n' \
    "" \
    "  ${z}┌─────────────────────────────────────────┐${r}" \
    "  ${z}│${r}   ${b}fan-random${r}  ${l}随机壁纸 API · 卸载${r}        ${z}│${r}" \
    "  ${z}└─────────────────────────────────────────┘${r}" \
    ""
}

error() { printf "  %s %s\n" "${gl_hong}[错误]${reset}" "$1" >&2; exit 1; }
[ "$(id -u)" != "0" ] && error "请以 root 身份运行（sudo bash scripts/uninstall.sh）"

UNINSTALL_YES=0
DELETE_DATA=0
KEEP_DATA=0
QUIET=0

usage() {
  printf '%s\n' \
    "用法: bash scripts/uninstall.sh [选项]" \
    "" \
    "选项:" \
    "  -y, --yes        免确认，自动同意卸载" \
    "      --purge      卸载时同时删除图片目录（全部壁纸图片）" \
    "      --keep-data  卸载时保留图片目录" \
    "  -q, --quiet      静默模式，仅输出关键信息" \
    "  -h, --help       显示帮助" \
    "" \
    "示例:" \
    "  bash scripts/uninstall.sh -y               免确认卸载，保留图片目录" \
    "  bash scripts/uninstall.sh -y --purge       免确认卸载，并删除图片目录"
  exit 0
}

# ---- bootstrap: support `bash -c "$(curl ...)" -y --purge` ----
case "$0" in
  -*) set -- "$0" "$@" ;;
esac

while [ $# -gt 0 ]; do
  case "$1" in
    -y|--yes) UNINSTALL_YES=1; shift ;;
    --purge|--delete-data) DELETE_DATA=1; shift ;;
    --keep-data) KEEP_DATA=1; shift ;;
    -q|--quiet) QUIET=1; shift ;;
    -h|--help) usage ;;
    *) error "未知参数: $1，使用 -h 查看帮助" ;;
  esac
done

[ "$QUIET" = "1" ] && {
  sep_line() { :; }
  section() { :; }
  ok() { :; }
  skip() { :; }
}

read_config() {
  [ -f "$CONFIG_FILE" ] || return 0
  while IFS='=' read -r KEY VALUE; do
    KEY=$(printf '%s' "$KEY" | tr -d ' ')
    VALUE=$(printf '%s' "$VALUE" | tr -d '\r')
    case "$KEY" in
      APP_DIR) [ -n "$VALUE" ] && APP_DIR="$VALUE" ;;
      PORT) [ -n "$VALUE" ] && PORT="$VALUE" ;;
      IMAGE_DIR) [ -n "$VALUE" ] && IMAGE_DIR="$VALUE" ;;
      PC_DIR) [ -n "$VALUE" ] && PC_DIR="$VALUE" ;;
      MP_DIR) [ -n "$VALUE" ] && MP_DIR="$VALUE" ;;
      NODE_BIN) [ -n "$VALUE" ] && NODE_BIN="$VALUE" ;;
    esac
  done < "$CONFIG_FILE"
}

find_fan_random_pids() {
  # 按 argv 整词匹配，避免把 vim/tail/grep 等恰好含路径的无关进程误杀
  local d pid t
  local match_a match_b match_c
  match_a="${APP_DIR}/docker-server.js"
  match_b="${APP_DIR}/bin/docker-server.js"
  match_c="${APP_DIR}/fan-random"
  for d in /proc/[0-9]*; do
    [ -d "$d" ] || continue
    pid="${d#/proc/}"
    [ "$pid" = "$$" ] && continue
    if [ -d "$d" ] && [ -r "$d/cmdline" ]; then
      while IFS= read -r -d '' t; do
        matched="n"
        case "$t" in
          "$match_a"|"$match_b"|"$match_c") matched="y" ;;
        esac
        [ "$matched" = "y" ] && { echo "$pid"; break; }
      done < "$d/cmdline"
    fi
  done
}

close_firewall_port() {
  local PORT="$1"
  [ -z "$PORT" ] && return 0

  # 1. firewalld
  if command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --state >/dev/null 2>&1; then
    firewall-cmd --permanent --remove-port="${PORT}/tcp" >/dev/null 2>&1 || true
    firewall-cmd --reload >/dev/null 2>&1 || true
    ok "已通过 ${gl_bai}firewalld${reset} 关闭端口 ${gl_lan}${PORT}/tcp${reset}"
  # 2. ufw
  elif command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q "Status: active"; then
    ufw delete allow "${PORT}/tcp" >/dev/null 2>&1 || true
    ok "已通过 ${gl_bai}ufw${reset} 关闭端口 ${gl_lan}${PORT}/tcp${reset}"
  # 3. iptables
  elif command -v iptables >/dev/null 2>&1; then
    if iptables -D INPUT -p tcp --dport "${PORT}" -j ACCEPT >/dev/null 2>&1; then
      ok "已通过 ${gl_bai}iptables${reset} 关闭端口 ${gl_lan}${PORT}/tcp${reset}"
    fi
  fi
}

[ "$QUIET" = "1" ] || print_banner
sep_line
section "卸载确认"
if [ "$UNINSTALL_YES" = "1" ]; then
  ok "开始卸载 ${APP_NAME} ..."
else
  while :; do
    read -r -p "${gl_huang}卸载将停止并移除 ${APP_NAME} 服务与程序，是否继续？${gl_bai}[y/N]${reset}: " CONFIRM
    case "$CONFIRM" in
      y|Y|yes|YES)
        ok "开始卸载 ${APP_NAME} ..."
        break
        ;;
      n|N|no|NO|"")
        printf "  %s\n" "${gl_huang}已取消卸载。${reset}"
        exit 0
        ;;
      *)
        printf "  %s\n" "${gl_huang}输入无效，请输入 y 或 n。${reset}"
        ;;
    esac
  done
fi

PORT="$DEFAULT_PORT"
IMAGE_DIR=""
PC_DIR=""
MP_DIR=""
APP_DIR="/var/lib/${APP_NAME}"
read_config

# 从 service 文件回退读取安装参数（config 缺失时），兼容引号包裹的路径
if [ -f "$SERVICE_FILE" ]; then
  [ -z "$PORT" ] && PORT=$(grep -oE 'PORT=[0-9]+' "$SERVICE_FILE" | head -n1 | cut -d= -f2)
  [ -z "$PORT" ] && PORT="$DEFAULT_PORT"
  if [ -z "$APP_DIR" ]; then
    APP_DIR=$(grep -oE 'WorkingDirectory="?[^"]+' "$SERVICE_FILE" | head -n1 | sed 's/WorkingDirectory="\?//')
  fi
fi

# 危险路径防护：拒绝删除 / 、空路径或非绝对路径
assert_safe_rm() {
  local p="$1"
  [ -n "$p" ] || return 1
  case "$p" in
    "/"|"") printf '%s\n' "${gl_hong}[错误]${reset} 拒绝删除根目录或空路径: '${p}'" >&2; return 1 ;;
    /*) return 0 ;;
    *) printf '%s\n' "${gl_hong}[错误]${reset} 拒绝删除非绝对路径: '${p}'" >&2; return 1 ;;
  esac
}

rm_ok() {
  assert_safe_rm "$1" || return 1
  rm -rf "$1"
}
[ -z "$IMAGE_DIR" ] && IMAGE_DIR="$APP_DIR/public"
[ -z "$PC_DIR" ] && PC_DIR="$APP_DIR/public/pc"
[ -z "$MP_DIR" ] && MP_DIR="$APP_DIR/public/mp"

sep_line
section "停止服务"
if command -v systemctl >/dev/null 2>&1 && [ -f "$SERVICE_FILE" ]; then
  ok "正在停止并移除 systemd 服务 ${gl_bai}${APP_NAME}${reset} ..."
  systemctl stop "${APP_NAME}" 2>/dev/null || true
  systemctl disable "${APP_NAME}" 2>/dev/null || true
  rm -f "$SERVICE_FILE"
  systemctl daemon-reload 2>/dev/null || true
else
  skip "未发现 systemd 服务，跳过。"
fi

sep_line
section "停止进程"
PIDS=$(find_fan_random_pids)
if [ -n "$PIDS" ]; then
  ok "正在停止 ${APP_NAME} 进程: ${gl_bai}$PIDS${reset} ..."
  for PID in $PIDS; do
    [ -d "/proc/$PID" ] || continue
    kill "$PID" 2>/dev/null || true
  done
  sleep 1
  for PID in $PIDS; do
    [ -d "/proc/$PID" ] || continue
    kill -9 "$PID" 2>/dev/null || true
  done
else
  skip "未发现运行中的 ${APP_NAME} 进程，跳过。"
fi

sep_line
section "删除程序目录"
if [ -n "$APP_DIR" ] && [ -d "$APP_DIR" ]; then
  # 若壁纸目录在程序目录内部（默认 /var/lib/fan-random/public）先摘除软链，避免被整体删除（默认保留图片）
  rm -f "${APP_DIR}/app/public" 2>/dev/null || true
  rm -f "${APP_DIR}/public/pc" 2>/dev/null || true
  rm -f "${APP_DIR}/public/mp" 2>/dev/null || true
  rm -f "${APP_DIR}/public" 2>/dev/null || true
  rm_ok "$APP_DIR"
  ok "已删除程序目录 ${gl_bai}${APP_DIR}${reset}"
else
  skip "未找到程序目录 ${gl_bai}${APP_DIR}${reset}，跳过。"
fi

sep_line
section "删除 CLI 命令"
if [ -f "$CLI_BIN" ] || [ -L "$CLI_BIN" ]; then
  rm -f "$CLI_BIN"
  ok "已删除命令 ${gl_bai}${CLI_BIN}${reset}"
else
  skip "未找到命令 ${gl_bai}${CLI_BIN}${reset}，跳过。"
fi

sep_line
section "删除图片目录"
# 集合待处理的壁纸目录（pc/mp；兼容旧版 IMAGE_DIR，去重，仅处理程序目录外部的独立目录，
# 默认位于 APP_DIR/public 内的壁纸随程序目录一并删除）
DATA_DIRS=()
collect_data_dirs() {
  local d x is_dup
  for d in "$PC_DIR" "$MP_DIR" "$IMAGE_DIR"; do
    [ -n "$d" ] || continue
    [ "$d" = "$APP_DIR" ] && continue
    case "${d}" in "${APP_DIR}/"*) continue ;; esac
    is_dup="n"
    for x in "${DATA_DIRS[@]:-}"; do [ "$x" = "$d" ] && is_dup="y"; done
    [ "$is_dup" = "y" ] && continue
    DATA_DIRS+=("$d")
  done
}
collect_data_dirs

if [ "${#DATA_DIRS[@]}" -eq 0 ]; then
  skip "未发现独立的壁纸目录（默认位于程序目录内的壁纸已随程序目录删除），跳过。"
else
  for IMAGE_DIR in "${DATA_DIRS[@]}"; do
    [ -d "$IMAGE_DIR" ] || continue
    ok "检测到壁纸目录: ${gl_bai}${IMAGE_DIR}${reset}"
    if [ "$KEEP_DATA" = "1" ]; then
      skip "已保留壁纸目录 ${gl_bai}${IMAGE_DIR}${reset}"
    elif [ "$DELETE_DATA" = "1" ]; then
      rm_ok "$IMAGE_DIR"
      ok "已删除壁纸目录 ${gl_bai}${IMAGE_DIR}${reset}"
    elif [ -t 0 ]; then
      read -r -p "${gl_huang}是否删除壁纸目录 ${IMAGE_DIR}？（全部壁纸图片）${gl_bai}[Y/n]${reset}: " DEL_DATA
      case "$DEL_DATA" in
        n|N|no|NO)
          skip "已保留壁纸目录 ${gl_bai}${IMAGE_DIR}${reset}"
          ;;
        *)
          rm_ok "$IMAGE_DIR"
          ok "已删除壁纸目录 ${gl_bai}${IMAGE_DIR}${reset}"
          ;;
      esac
    else
      skip "非交互模式下默认保留壁纸目录 ${gl_bai}${IMAGE_DIR}${reset}"
    fi
  done
fi

sep_line
section "删除安装记录"
if [ -f "$CONFIG_FILE" ]; then
  rm -f "$CONFIG_FILE"
  ok "已删除安装记录 ${gl_bai}$CONFIG_FILE${reset}"
  rmdir "$(dirname "$CONFIG_FILE")" 2>/dev/null || true
  rmdir "/etc/${APP_NAME}" 2>/dev/null || true
else
  skip "未找到安装记录 ${gl_bai}$CONFIG_FILE${reset}，跳过。"
fi

sep_line
section "关闭防火墙"
close_firewall_port "$PORT"

sep_line
printf "  %s\n" "${gl_lv}✔ ${APP_NAME} 已卸载完成${reset}"
printf "  %s\n" "${gl_hui}如需重新安装，请再次运行 scripts/install.sh 安装脚本。${reset}"
sep_line