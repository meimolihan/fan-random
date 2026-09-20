#!/usr/bin/env bash
#
# fan-random 图片分类脚本（classify.py 的纯 Shell 等价实现，基于 ffmpeg/ffprobe）
#
# 使用方法：
#   1. 将原始图片放入 photos/ 目录
#   2. 运行：bash classify.sh           （缺依赖时自动询问安装）
#           bash classify.sh --install  （强制安装/更新 ffmpeg 依赖）
#           bash classify.sh -q 90      （自定义 WebP 压缩质量，默认 80）
#   3. 处理完成后，图片会出现在 public/pc/（桌面端）和 public/mp/（移动端）目录
#
# 依赖：ffmpeg / ffprobe（同属 ffmpeg 软件包，支持 apt/yum/dnf/apk/pacman/brew）
# 说明：pc = 桌面端（横屏），mp = 移动端（竖屏）
set -euo pipefail

# ================== 终端配色（与安装脚本一致） ==================
gl_hui=$'\033[38;5;59m'
gl_hong=$'\033[38;5;9m'
gl_lv=$'\033[38;5;10m'
gl_huang=$'\033[38;5;11m'
gl_lan=$'\033[38;5;32m'
gl_bai=$'\033[38;5;15m'
gl_zi=$'\033[38;5;13m'
gl_bufan=$'\033[38;5;14m'
reset=$'\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INPUT_FOLDER="${CLASSIFY_INPUT:-$SCRIPT_DIR/photos}"
OUTPUT_BASE="${CLASSIFY_OUTPUT:-$SCRIPT_DIR}"
OUTPUT_PC="$OUTPUT_BASE/public/pc"
OUTPUT_MP="$OUTPUT_BASE/public/mp"
MAX_PIXELS=178956970        # 约 1.79 亿像素（8K 级别），防止处理超大图片
DEFAULT_QUALITY=80          # 与 classify.py 的 PIL WebP 默认质量一致

err()  { printf "  %s %s\n" "${gl_hong}[错误]${reset}" "$1"; }
warn() { printf "  %s %s\n" "${gl_huang}[警告]${reset}" "$1"; }
ok()   { printf "  %s %s\n" "${gl_lv}>>>${reset}" "$1"; }
skip() { printf "  %s %s\n" "${gl_hui}--${reset}" "$1"; }

# ================== 系统/缓存配置文件 ==================
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/fan-random"
INSTALL_STAMP="$CACHE_DIR/ffmpeg-installed.stamp"

# ================== 依赖检测 ==================
has_cmd() { command -v "$1" >/dev/null 2>&1; }

# 检测系统包管理器
detect_pkg_manager() {
  if   command -v apt-get >/dev/null 2>&1; then echo "apt"
  elif command -v dnf     >/dev/null 2>&1; then echo "dnf"
  elif command -v yum     >/dev/null 2>&1; then echo "yum"
  elif command -v apk     >/dev/null 2>&1; then echo "apk"
  elif command -v pacman  >/dev/null 2>&1; then echo "pacman"
  elif command -v brew    >/dev/null 2>&1; then echo "brew"
  else echo "unknown"; fi
}

# 安装 ffmpeg 依赖（apt/dnf/yum/apk/pacman/brew）
install_deps() {
  echo ""
  printf "  %s\n" "${gl_zi}▶${reset} 检测到需要安装依赖 ${gl_bai}ffmpeg${reset}（含 ffprobe）"

  if [ "$(id -u)" != "0" ]; then
    if [ "$(detect_pkg_manager)" = "brew" ]; then
      : # brew 不需要 root
    else
      err "安装依赖需要 root 权限，请使用 sudo bash classify.sh $* 重新运行"
      return 1
    fi
  fi

  case "$(detect_pkg_manager)" in
    apt)
      ok "使用 apt 安装（在发行版软件源中查找 ffmpeg）..."
      export DEBIAN_FRONTEND=noninteractive
      apt-get update -y
      apt-get install -y ffmpeg
      ;;
    dnf)
      ok "使用 dnf 安装 ffmpeg..."
      dnf install -y ffmpeg || {
        warn "默认源未找到 ffmpeg，尝试启用 EPEL + RPM Fusion 源..."
        dnf install -y epel-release
        dnf config-manager --set-enabled crb || true
        dnf install -y https://mirrors.rpmfusion.org/free/el/rpmfusion-free-release-$(rpm -E %rhel).noarch.rpm || true
        dnf install -y ffmpeg
      }
      ;;
    yum)
      ok "使用 yum 安装 ffmpeg..."
      yum install -y epel-release
      yum install -y --nogpgcheck https://mirrors.rpmfusion.org/free/el/rpmfusion-free-release-$(rpm -E %rhel).noarch.rpm || true
      yum install -y ffmpeg
      ;;
    apk)
      ok "使用 apk 安装 ffmpeg..."
      apk add --no-cache ffmpeg
      ;;
    pacman)
      ok "使用 pacman 安装 ffmpeg..."
      pacman -Sy --noconfirm ffmpeg
      ;;
    brew)
      ok "使用 brew 安装 ffmpeg..."
      brew install ffmpeg
      ;;
    *)
      err "无法识别包管理器，请手动安装 ffmpeg 后重试"
      return 1
      ;;
  esac

  if ! has_cmd ffmpeg || ! has_cmd ffprobe; then
    err "ffmpeg/ffprobe 安装失败，请检查软件源或手动安装后重试"
    return 1
  fi

  mkdir -p "$CACHE_DIR"
  : > "$INSTALL_STAMP"
  ok "依赖安装完成: ffmpeg $(ffmpeg -version 2>/dev/null | head -n1 | awk '{print $3}')"
}

ensure_deps() {
  if has_cmd ffmpeg && has_cmd ffprobe; then
    return 0
  fi
  # 未安装：询问（非交互默认安装）
  if [ -t 0 ]; then
    read -r -p "${gl_huang}未检测到 ffmpeg（用于图片转换），是否现在安装？${gl_bai}[Y/n]${reset}: " ANS
    case "$ANS" in
      n|N|no|NO) err "缺少依赖 ffmpeg，已取消处理"; return 1 ;;
      *) install_deps || return 1 ;;
    esac
  else
    install_deps || return 1
  fi
}

# ================== ffmpeg 是否支持 libwebp 编码器 ==================
have_libwebp() {
  local enc
  enc=$(ffmpeg -hide_banner -encoders 2>/dev/null) || true
  case "$enc" in
    *libwebp*) return 0 ;;
    *) return 1 ;;
  esac
}

# ================== 图片处理 ==================
# 获取图片宽高（找不到视频流时返回空）
get_image_size() {
  ffprobe -v error -select_streams v:0 \
    -show_entries stream=width,height \
    -of csv=p=0:s=x "$1" 2>/dev/null || true
}

# 获取图片方向：landscape（宽>高）/ portrait
get_image_orientation() {
  local size width height
  size=$(get_image_size "$1")
  width=${size%%x*}
  height=${size##*x}
  if [ -z "$width" ] || [ -z "$height" ] || ! [[ "$width" =~ ^[0-9]+$ ]] || ! [[ "$height" =~ ^[0-9]+$ ]] \
     || [ "$width" -le 0 ] || [ "$height" -le 0 ]; then
    echo "unknown"
    return
  fi
  if [ "$width" -gt "$height" ]; then echo "landscape"; else echo "portrait"; fi
}

# 转换单张图片为 WebP
convert_to_webp() {
  local image_path="$1" output_folder="$2" width height
  # 检查分辨率上限（与 classify.py 的 MAX_PIXELS 一致），0 尺寸视为无效
  local size
  size=$(get_image_size "$image_path")
  width=${size%%x*}
  height=${size##*x}
  if [[ "$width" =~ ^[0-9]+$ ]] && [[ "$height" =~ ^[0-9]+$ ]] && \
     [ $((width * height)) -gt "$MAX_PIXELS" ]; then
    printf "  跳过 %s（分辨率过大）\n" "$(basename "$image_path")"
    return
  fi
  if [ "$width" -le 0 ] || [ "$height" -le 0 ]; then
    printf "  跳过 %s（无法读取图片信息）\n" "$(basename "$image_path")"
    return
  fi

  local filename base output_path stderr_log
  filename=$(basename "$image_path")
  base="${filename%.*}"
  output_path="$output_folder/${base}.webp"
  stderr_log="$(mktemp)"

  if ! ffmpeg -y -hide_banner -loglevel error \
       -i "$image_path" \
       -c:v libwebp -quality "$DEFAULT_QUALITY" "$output_path" 2>"$stderr_log"; then
    rm -f "$output_path"
    if [ -s "$stderr_log" ]; then
      warn "转换失败: $filename（$(tr '\n' ' ' <"$stderr_log" | sed 's/  */ /g')）"
    else
      warn "转换失败: $filename"
    fi
  fi
  rm -f "$stderr_log"
}

# 遍历输入目录，处理所有图片（pc=桌面端横屏，mp=移动端竖屏）
process_images() {
  mkdir -p "$OUTPUT_PC" "$OUTPUT_MP"

  if [ ! -d "$INPUT_FOLDER" ]; then
    err "输入目录不存在：$INPUT_FOLDER"
    echo "请将原始图片放入 photos/ 目录后重新运行。"
    return
  fi

  # 收集图片文件（支持 .jpg/.jpeg/.png/.webp，与 classify.py 一致）
  local image_files=()
  while IFS= read -r -d '' f; do
    image_files+=("$f")
  done < <(find "$INPUT_FOLDER" -maxdepth 1 -type f \
      \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \) -print0 2>/dev/null)

  if [ "${#image_files[@]}" -eq 0 ]; then
    skip "输入目录 $INPUT_FOLDER 中没有找到图片（支持 .jpg/.jpeg/.png/.webp）"
    return
  fi

  echo "找到 ${#image_files[@]} 张图片，开始处理..."
  echo ""

  local pc_count=0 mp_count=0 skipped_count=0
  local i=0 total=${#image_files[@]}
  local orientation

  for image_path in "${image_files[@]}"; do
    i=$((i + 1))
    printf "  [%s/%s] %s ...\n" "$i" "$total" "$(basename "$image_path")"
    orientation=$(get_image_orientation "$image_path")
    case "$orientation" in
      landscape)
        convert_to_webp "$image_path" "$OUTPUT_PC"
        pc_count=$((pc_count + 1))
        ;;
      portrait)
        convert_to_webp "$image_path" "$OUTPUT_MP"
        mp_count=$((mp_count + 1))
        ;;
      *)
        warn "无法读取图片信息，跳过: $image_path"
        skipped_count=$((skipped_count + 1))
        ;;
    esac
  done

  echo ""
  ok "处理完成！"
  echo "   pc 桌面端 → $OUTPUT_PC（$pc_count 张）"
  echo "   mp 移动端 → $OUTPUT_MP（$mp_count 张）"
  if [ "$skipped_count" -gt 0 ]; then
    echo "   跳过：$skipped_count 张"
  fi
}

# ================== 入口 ==================
QUALITY_OR_ARG=""
while [ $# -gt 0 ]; do
  case "$1" in
    --install|--install-deps)
      install_deps && exit 0
      ;;
    -q|--quality)
      shift
      [[ "$1" =~ ^[0-9]+$ ]] || { err "-q/--quality 需要数字参数（1-100）"; exit 1; }
      [ "$1" -ge 1 ] && [ "$1" -le 100 ] || { err "压缩质量需在 1-100 之间"; exit 1; }
      DEFAULT_QUALITY="$1"
      shift
      ;;
    -h|--help)
      echo "用法: bash classify.sh [选项]"
      echo ""
      echo "选项:"
      echo "      --install       安装/更新 ffmpeg 依赖（含 ffprobe），然后退出"
      echo "  -q, --quality N     WebP 压缩质量（1-100，默认 80）"
      echo "  -h, --help          显示本帮助"
      echo ""
      echo "说明: 将原始图片放入 photos/，运行后自动横竖屏分类并转 WebP 到 public/pc（桌面端）与 public/mp（移动端）"
      exit 0
      ;;
    *)
      err "未知参数: $1，使用 -h 查看帮助"
      exit 1
      ;;
  esac
done

printf '%s\n' \
  "========================================" \
  "  fan-random — 图片分类工具" \
  "========================================" \
  "  输入目录：$INPUT_FOLDER" \
  "  输出目录：$OUTPUT_PC" \
  "            $OUTPUT_MP" \
  "========================================"
echo ""

ensure_deps || exit 1

if ! have_libwebp; then
  err "当前 ffmpeg 未编译 libwebp 编码器，无法输出 WebP 图片。"
  err "请使用系统包管理器安装 ffmpeg（如 apt install ffmpeg）或换用包含 libwebp 的构建版本。"
  exit 1
fi

process_images