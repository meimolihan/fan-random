"""
随机壁纸分类脚本
自动识别图片方向（横屏/竖屏），转换为 WebP 格式并保存到对应目录。

使用说明：
pc：桌面端（横屏）   mp：移动端（竖屏）

使用方法：
1. 将原始图片放入 photos/ 目录
2. 运行：python3 classify.py
3. 处理完成后，图片会出现在 public/pc/（桌面端）和 public/mp/（移动端）目录
"""

try:
    from PIL import Image, ImageOps
except ImportError:
    print("缺少 Pillow 依赖，请先安装：")
    print("  python3 -m pip install Pillow     # 或 apt install python3-pil")
    raise SystemExit(1)
import os

MAX_PIXELS = 178956970  # 约 1.79 亿像素（8K 级别），防止处理超大图片
# 由下方的 MAX_PIXELS 显式检查兜底，避免 PIL 默认的 DecompressionBomb 保护先于该检查触发
Image.MAX_IMAGE_PIXELS = None


def get_image_orientation(image_path):
    """检查图片方向（应用 EXIF 旋转后判定，与 classify.sh 的自动旋转一致）"""
    with Image.open(image_path) as img:
        img = ImageOps.exif_transpose(img)
        width, height = img.size
        return "landscape" if width > height else "portrait"


def convert_to_webp(image_path, output_folder, created_this_run):
    """转换图片为 WebP 格式"""
    try:
        with Image.open(image_path) as img:
            img = ImageOps.exif_transpose(img)
            width, height = img.size
            if width * height > MAX_PIXELS:
                print(f"跳过 {image_path}（分辨率过大）")
                return False

            base = os.path.splitext(os.path.basename(image_path))[0]
            # 同名不同格式输入时追加数字后缀，避免相互覆盖
            output_path = os.path.join(output_folder, base + ".webp")
            counter = 2
            while os.path.exists(output_path):
                output_path = os.path.join(output_folder, f"{base}-{counter}.webp")
                counter += 1
            img.save(output_path, "webp")
            created_this_run.add(os.path.abspath(output_path))
            return True
    except Exception as e:
        print(f"转换失败 {image_path}: {e}")
        return False


def already_processed(base, output_folder, created_this_run):
    """幂等检查：photos/ 中同一输入重复运行时跳过，避免每次重新生成 photo-2/photo-3
    若 base.webp 已存在且不是本次运行生成的，视为该输入已处理。"""
    existing = os.path.join(output_folder, base + ".webp")
    return os.path.exists(existing) and os.path.abspath(existing) not in created_this_run


def process_images(input_folder, output_pc, output_mp):
    """遍历输入目录，处理所有图片"""
    # 确保输出目录存在
    os.makedirs(output_pc, exist_ok=True)
    os.makedirs(output_mp, exist_ok=True)

    if not os.path.exists(input_folder):
        print(f"输入目录不存在：{input_folder}")
        print("请将原始图片放入 photos/ 目录后重新运行。")
        return

    image_files = sorted(
        f for f in os.listdir(input_folder)
        if os.path.isfile(os.path.join(input_folder, f))
        and f.lower().endswith(('.jpg', '.jpeg', '.png', '.webp'))
    )

    if not image_files:
        print(f"输入目录 {input_folder} 中没有找到图片（支持 .jpg/.jpeg/.png/.webp）")
        return

    print(f"找到 {len(image_files)} 张图片，开始处理...\n")

    # 记录本次运行生成的文件，用于幂等判断
    created_this_run = set()

    pc_count = 0
    mp_count = 0
    skipped_count = 0

    for filename in image_files:
        image_path = os.path.join(input_folder, filename)
        base = os.path.splitext(filename)[0]
        try:
            if already_processed(base, output_pc, created_this_run) or \
               already_processed(base, output_mp, created_this_run):
                print(f"跳过 {filename}（已处理过）")
                skipped_count += 1
                continue
            orientation = get_image_orientation(image_path)
            if orientation == "landscape":
                if convert_to_webp(image_path, output_pc, created_this_run):
                    pc_count += 1
                else:
                    skipped_count += 1
            else:
                if convert_to_webp(image_path, output_mp, created_this_run):
                    mp_count += 1
                else:
                    skipped_count += 1
        except Exception as e:
            print(f"处理失败 {filename}: {e}")
            skipped_count += 1

    print(f"✅ 处理完成！")
    print(f"   pc 桌面端 → {output_pc}（{pc_count} 张）")
    print(f"   mp 移动端 → {output_mp}（{mp_count} 张）")
    if skipped_count > 0:
        print(f"   跳过：{skipped_count} 张")


if __name__ == "__main__":
    # 定义路径（相对于脚本所在目录；可用 CLASSIFY_INPUT/CLASSIFY_OUTPUT 覆盖，与 classify.sh 一致）
    script_dir = os.path.dirname(os.path.abspath(__file__))
    input_folder = os.environ.get("CLASSIFY_INPUT", os.path.join(script_dir, "photos"))
    output_base = os.environ.get("CLASSIFY_OUTPUT", script_dir)
    output_pc = os.path.join(output_base, "public", "pc")
    output_mp = os.path.join(output_base, "public", "mp")

    print("=" * 40)
    print("  fan-random — 图片分类工具")
    print("  pc: 桌面端    mp: 移动端")
    print("=" * 40)
    print(f"  输入目录：{input_folder}")
    print(f"  输出目录：{output_pc}")
    print(f"            {output_mp}")
    print("=" * 40)
    print()

    process_images(input_folder, output_pc, output_mp)
