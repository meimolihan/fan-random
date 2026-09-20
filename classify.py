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

from PIL import Image
import os

MAX_PIXELS = 178956970  # 约 1.79 亿像素（8K 级别），防止处理超大图片


def get_image_orientation(image_path):
    """检查图片方向"""
    with Image.open(image_path) as img:
        width, height = img.size
        return "landscape" if width > height else "portrait"


def convert_to_webp(image_path, output_folder):
    """转换图片为 WebP 格式"""
    try:
        with Image.open(image_path) as img:
            width, height = img.size
            if width * height > MAX_PIXELS:
                print(f"跳过 {image_path}（分辨率过大）")
                return

            filename = os.path.splitext(os.path.basename(image_path))[0] + ".webp"
            output_path = os.path.join(output_folder, filename)
            img.save(output_path, "webp")
    except Exception as e:
        print(f"转换失败 {image_path}: {e}")


def process_images(input_folder, output_pc, output_mp):
    """遍历输入目录，处理所有图片"""
    # 确保输出目录存在
    os.makedirs(output_pc, exist_ok=True)
    os.makedirs(output_mp, exist_ok=True)

    if not os.path.exists(input_folder):
        print(f"输入目录不存在：{input_folder}")
        print("请将原始图片放入 photos/ 目录后重新运行。")
        return

    image_files = [
        f for f in os.listdir(input_folder)
        if f.lower().endswith(('.jpg', '.jpeg', '.png', '.webp'))
    ]

    if not image_files:
        print(f"输入目录 {input_folder} 中没有找到图片（支持 .jpg/.jpeg/.png/.webp）")
        return

    print(f"找到 {len(image_files)} 张图片，开始处理...\n")

    pc_count = 0
    mp_count = 0
    skipped_count = 0

    for filename in image_files:
        image_path = os.path.join(input_folder, filename)
        try:
            orientation = get_image_orientation(image_path)
            if orientation == "landscape":
                convert_to_webp(image_path, output_pc)
                pc_count += 1
            else:
                convert_to_webp(image_path, output_mp)
                mp_count += 1
        except Exception as e:
            print(f"处理失败 {filename}: {e}")
            skipped_count += 1

    print(f"✅ 处理完成！")
    print(f"   pc 桌面端 → {output_pc}（{pc_count} 张）")
    print(f"   mp 移动端 → {output_mp}（{mp_count} 张）")
    if skipped_count > 0:
        print(f"   跳过：{skipped_count} 张")


if __name__ == "__main__":
    # 定义路径（相对于脚本所在目录）
    script_dir = os.path.dirname(os.path.abspath(__file__))
    input_folder = os.path.join(script_dir, "photos")
    output_pc = os.path.join(script_dir, "public", "pc")
    output_mp = os.path.join(script_dir, "public", "mp")

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
