<div align="center">

# fan-random 🖼️

_✨ 一个随机壁纸 API — 支持 Vercel / Docker / 单文件二进制 / Systemd 全场景部署 ✨_

</div>

<p align="center">
  <a href="https://github.com/meimolihan/fan-random/releases/latest">
    <img src="https://img.shields.io/github/v/release/meimolihan/fan-random?color=brightgreen" alt="release">
  </a>
  <a href="https://github.com/meimolihan/fan-random/actions">
    <img src="https://img.shields.io/github/actions/workflow/status/meimolihan/fan-random/release.yml?branch=main" alt="deployment status">
  </a>
  <a href="https://hub.docker.com/repository/docker/mobufan/fan-random">
    <img src="https://img.shields.io/docker/pulls/mobufan/fan-random?color=brightgreen" alt="docker pull">
  </a>
  <a href="https://github.com/meimolihan/fan-random/releases/latest">
    <img src="https://img.shields.io/github/downloads/meimolihan/fan-random/total?color=brightgreen&include_prereleases" alt="release">
  </a>
</p>

## 功能

+ [x] `pc` 桌面端、`mp` 移动端，自动识别设备类型返回对应壁纸
+ [x] 支持 WebP / JPG / PNG / GIF 格式，全链路禁止缓存
+ [x] `?type=json` 返回 JSON（含图片 URL、类型、总数）
+ [x] 内置 836 张壁纸（pc 桌面端 418 张 + mp 移动端 418 张）
+ [x] 零第三方运行时依赖（仅 Node.js 内置模块）
+ [x] `fan-random` 内置 CLI 管理命令 + systemd 服务
+ [x] GitHub Actions 自动发版：二进制 + 图片包 + Docker 镜像

## 🖼️ 在线预览

| 类型 | 地址 | 说明 |
|------|------|------|
| pc 桌面端 | `http://你的域名/pc` | 随机返回一张桌面端（横屏）壁纸 |
| mp 移动端 | `http://你的域名/mp` | 随机返回一张移动端（竖屏）壁纸 |
| 自适应 | `http://你的域名/` | 自动识别设备类型返回对应壁纸 |

> 💡 直接在浏览器打开以上链接即可查看效果，每次刷新随机返回不同图片。

## 🌐 API 端点

| 端点 | 说明 |
|------|------|
| `/` | 自适应（自动识别手机/电脑） |
| `/pc` | pc 桌面端（随机横屏壁纸） |
| `/mp` | mp 移动端（随机竖屏壁纸） |

### 附加参数

- `?type=json` — 返回 JSON 格式（包含图片 URL、类型、总数）

```bash
# 直接获取随机图片
curl http://your-domain:8588/pc

# 获取 JSON 格式
curl "http://your-domain:8588/pc?type=json"
# {"url":"/pc/pc-117.webp","type":"pc","count":418}
```

## 🚀 部署方式

### 方式一：Vercel 部署（Serverless）

1. Fork 或 clone 本仓库
2. 在 [Vercel](https://vercel.com) 中导入项目
3. 点击 Deploy — 自动完成构建和部署（`vercel-build` 生成图片清单）

```bash
npm i -g vercel
vercel --prod
```

### 方式二：Docker 部署

#### 使用 Docker Compose（推荐）

```bash
git clone https://github.com/meimolihan/fan-random.git
cd fan-random

# 方式 A：拉取最新镜像并启动
docker compose pull && docker compose up -d

# 方式 B：本地构建镜像并启动（修改代码后需要此方式）
docker compose build && docker compose up -d
```

服务将在 `http://localhost:8588` 启动。

| 参数 | 说明 |
|------|------|
| pc 桌面端壁纸目录 | `./public/pc` |
| mp 移动端壁纸目录 | `./public/mp` |
| 原始图片目录 | `./photos` |
| 端口映射 | `8588:3000` |
| 对外访问地址 | `PUBLIC_HOST=http://10.10.10.251:8588` |

> 💡 添加或替换图片后只需 `docker restart fan-random` 即可生效，**无需重新构建镜像**。
> 💡 图片目录映射出来后可在宿主机直接管理图片文件，容器内外实时同步。

#### 使用 Docker Hub 镜像直接运行

```bash
docker run -d \
  --name fan-random \
  --restart always \
  -p 8588:3000 \
  -e TZ=Asia/Shanghai \
  mobufan/fan-random:latest
```

#### 自定义壁纸图片

```bash
docker run -d \
  --name fan-random \
  --restart always \
  -p 8588:3000 \
  -e TZ=Asia/Shanghai \
  -v /path/to/your/pc:/fan-random/public/pc \
  -v /path/to/your/mp:/fan-random/public/mp \
  -v /path/to/your/photos:/fan-random/photos \
  mobufan/fan-random:latest
```

> 💡 也可以在容器内运行 `python3 classify.py` 批量处理 `photos/` 目录中的原始图片（需先安装 Pillow）。

### 方式三：一键脚本安装（systemd，推荐生产环境）

适用于直接部署在 Linux 服务器（非 Docker），脚本自动探测二进制/源码、注册 systemd 服务、开放防火墙端口，并安装内置命令 `fan-random`。

```bash
# 默认端口 8588，程序目录 /var/lib/fan-random，壁纸目录 {安装目录}/public/{pc,mp}
bash scripts/install.sh

# 自定义安装目录、端口、pc/mp 壁纸目录，免交互
bash scripts/install.sh -d /opt/fan-random -p 9000 -pc /data/wallpapers/pc -mp /data/wallpapers/mp -y
```

> 可用参数：
>
> | 参数 | 说明 |
> |------|------|
> | `-d, --install-dir` | 安装目录（默认 `/var/lib/fan-random`，二进制的可执行文件也放在这里；旧别名 `-a/--appdir`） |
> | `-p, --port` | 监听端口（默认 8588） |
> | `-pc, --pc-dir` | pc 桌面端壁纸目录（默认 `{APP_DIR}/public/pc`） |
> | `-mp, --mp-dir` | mp 移动端壁纸目录（默认 `{APP_DIR}/public/mp`） |
> | `-s, --src` | 本地源码仓库路径（默认自动探测脚本上级目录） |
> | `-b, --binary` | 强制使用预编译二进制（无需 Node.js/git） |
> | `-y, --yes` | 免交互，未指定项全部使用默认值 |

> 💡 pc / mp 可分别指定任意绝对路径，壁纸目录不在安装目录内时自动通过 `{安装目录}/public/{pc,mp}` 软链接接入。

也可以直接用远程脚本安装（无需克隆仓库）：

```bash
# 国内网络可加 FAN_RANDOM_REPO=https://ghfast.top/https://github.com/meimolihan/fan-random.git
bash -c "$(curl -sSL https://raw.githubusercontent.com/meimolihan/fan-random/main/scripts/install.sh)" -p 8288 -d /data/fan-random -pc /data/wallpapers/pc -mp /data/wallpapers/mp -y
```

> 脚本支持两种安装方式：
> - **预编译二进制**（默认优先）：从 GitHub Releases 下载单文件二进制，无需 Node.js/git，含内置 CLI。
> - **源码编译**：本地存在源码仓库时自动使用，仅需 Node.js >= 18，无需构建任何前端依赖。

#### systemctl 服务命令

```bash
systemctl status fan-random     # 查看服务状态
systemctl restart fan-random    # 重启服务
systemctl stop fan-random       # 停止服务
systemctl enable fan-random     # 设置开机自启（安装时默认已启用）

journalctl -u fan-random -n 50  # 查看服务日志
```

#### 卸载

```bash
bash scripts/uninstall.sh              # 交互式卸载（默认保留图片目录）
bash scripts/uninstall.sh -y --purge   # 免确认卸载并删除图片目录
# 或使用 CLI：sudo fan-random uninstall -y --purge
```

### 方式四：编译单文件二进制（Node.js SEA）

> 编译产物是一个独立的可执行文件，无需安装 Node.js、无需 Docker，直接运行即可。

```bash
npm run build:sea
```

编译产物输出到 `dist/fan-random`（约 125MB，内含 Node.js 运行时和全部服务代码）。图片通过 `public/` 目录按需读取，与二进制放在一起：

```bash
my-deploy/
├── fan-random    # 编译产物（含内置 CLI）
└── public/
    ├── pc/       # 桌面端壁纸
    └── mp/       # 移动端壁纸

PORT=8000 ./fan-random   # 启动服务（默认端口 3000）
./fan-random --help      # 直接运行也可执行 CLI 管理命令
```

> ⚠️ **平台限制**：二进制内嵌当前平台的 Node 运行时，无法跨平台交叉编译（发布流水线使用 `@yao-pkg/pkg` 交叉编译 amd64/arm64）。

## 🛠️ 内置 CLI 管理命令

安装后可直接使用 `fan-random` 命令管理服务（二进制或源码安装均内置）：

| 命令 | 说明 |
|------|------|
| `fan-random status` | 查看运行方式（systemd / Docker / 直接运行）、PID、端口、访问地址、图片统计、运行时长、内存与路径 |
| `fan-random start` / `stop` / `restart` | 启动 / 停止 / 重启 systemd 服务 |
| `fan-random uninstall [-y] [--purge\|--keep-data]` | 停止并移除服务/容器/进程，删除程序与安装记录，可选删除图片目录 |
| `fan-random version` | 查看版本号 |
| `fan-random help` | 查看帮助 |

```bash
# 查看服务状态（含端口、图片数量与访问地址）
fan-random status

# 重启服务
sudo fan-random restart

# 免确认卸载，保留图片目录
sudo fan-random uninstall -y

# 免确认卸载，并删除图片目录
sudo fan-random uninstall -y --purge
```

## 📦 发布流程

### 手动发版（一键触发 Actions 流水线）

```bash
bash scripts/build-and-push.sh v1.0.1 --yes -m "本次新增 xxx"
```

推送 tag 后由 `.github/workflows/release.yml` 自动完成：

1. **编译二进制**：`fan-random_linux_amd64 / fan-random_linux_arm64`（`@yao-pkg/pkg` 交叉编译）
2. **打包图片**：`fan-random_public.tar.gz`
3. **发布 Release**：附带以上产物，供 `install.sh -b` 下载
4. **构建 Docker 镜像**：Docker Hub + GHCR（amd64/arm64 双架构）
5. **同步 CNB**（可选，需配置 `CNB_ACCESS_TOKEN` secrets）

### 本地编译

```bash
npm run build        # 生成 api/_manifest.js（Vercel 构建产物，CI 自动执行）
npm run build:sea    # 本地 SEA 单文件编译 → dist/fan-random
npm run lint         # 语法检查
```

## 📁 项目结构

```
├── api/
│   ├── index.js        # 自适应端点（UA 检测）— Vercel Serverless
│   ├── pc.js           # pc 桌面端壁纸端点 — Vercel Serverless
│   ├── mp.js           # mp 移动端壁纸端点 — Vercel Serverless
│   └── _manifest.js    # 构建时自动生成（图片列表）
├── public/
│   ├── pc/             # pc 桌面端壁纸（418 张）
│   └── mp/             # mp 移动端壁纸（418 张）
├── photos/             # 原始图片目录（用于 classify.py 输入）
├── bin/
│   └── fan-random.js   # 内置 CLI 管理命令
├── scripts/
│   ├── build.js            # 构建脚本（生成 manifest）
│   ├── build-sea.sh        # SEA 单文件编译（npm run build:sea）
│   ├── build-and-push.sh   # 发版脚本（打 tag 触发 Actions 流水线）
│   ├── install.sh          # 一键安装脚本（systemd + CLI）
│   └── uninstall.sh        # 卸载脚本
├── .github/workflows/
│   └── release.yml     # GitHub Actions 发布流水线
├── docker-server.js     # Docker/SEA/Systemd 通用 Node.js HTTP 服务器
├── docker-compose.yml
├── Dockerfile
├── sea-config.json      # SEA 编译配置
├── vercel.json          # Vercel 配置
├── classify.py          # 本地图片分类脚本
├── classify.sh          # 本地图片分类脚本（ffmpeg 版）
└── package.json
```

## 🔧 工作原理

### Vercel 部署

1. **构建时**：`scripts/build.js` 扫描图片目录，生成 `api/_manifest.js`
2. **请求时**：Serverless Function 从 manifest 中随机选择一张图片
3. **响应**：直接返回图片数据（无重定向）

### Docker / Systemd / 单文件部署

1. **启动时**：HTTP 服务器动态扫描 `public/` 目录下所有图片
2. **请求时**：每次请求随机选取一张图片，直接返回图片数据流
3. **更新图片**：放入新图片后重启服务即可生效（`docker restart fan-random` / `systemctl restart fan-random`），**无需重新构建**

## 🖼️ 添加/替换图片

> ⚡ **重要更新**：所有部署方式均支持运行时动态扫描图片，新增或替换图片后只需重启服务即可生效。

```bash
# Docker
docker restart fan-random

# Systemd
systemctl restart fan-random
```

### 方式一：手动放置

```bash
# pc 桌面端壁纸
public/pc/my-photo-1.webp

# mp 移动端壁纸
public/mp/my-photo-3.png
```

### 方式二：使用分类脚本自动分类（二选一）

分类脚本自动识别横屏/竖屏、转换为 WebP 格式并保存到对应目录，两种实现功能等价：

**📂 图片存放目录（脚本同级）**

| 目录 | 用途 |
|------|------|
| `photos/` | **输入**：把要处理的原始图片放这里（支持 `.jpg/.jpeg/.png/.webp`） |
| `public/pc/` | 输出：自动生成的 pc 桌面端（横屏）壁纸 |
| `public/mp/` | 输出：自动生成的 mp 移动端（竖屏）壁纸 |

> 💡 目录不存在会自动创建；也可用 `CLASSIFY_INPUT=/mnt/my-photos` 指定其他输入目录（输出跟随 `CLASSIFY_OUTPUT`）。

```bash
# 1. 将要处理的图片放入 photos/ 目录
cp /path/to/your/*.jpg photos/

# 2. 运行分类脚本
# 方式 A：classify.sh（基于 ffmpeg，无需 Python，缺依赖时自动询问/安装）
bash classify.sh                  # 自动检测依赖，缺失时询问安装
bash classify.sh --install        # 仅安装 ffmpeg 依赖后退出
bash classify.sh -q 90            # 自定义 WebP 压缩质量（1-100，默认 80）

# 方式 B：classify.py（基于 Pillow）
pip install Pillow
python3 classify.py
```

输出示例：

```
========================================
  fan-random — 图片分类工具
  pc: 桌面端    mp: 移动端
========================================
  输入目录：/path/to/project/photos
  输出目录：/path/to/project/public/pc
            /path/to/project/public/mp
========================================

找到 5 张图片，开始处理...

✅ 处理完成！
   pc 桌面端 → /path/to/project/public/pc/（2 张）
   mp 移动端 → /path/to/project/public/mp/（3 张）
```

## 📄 使用示例

### HTML

```html
<img src="http://your-domain:8588/pc" alt="随机壁纸" />
```

### CSS 背景

```css
body {
  background: url('http://your-domain:8588/') no-repeat center/cover;
}
```

### JavaScript

```javascript
// 获取随机壁纸 URL
fetch('http://your-domain:8588/mp?type=json')
  .then(r => r.json())
  .then(data => console.log(data.url));
```

## 📜 License

MIT