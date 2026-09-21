#!/usr/bin/env node
'use strict'
const http = require('http');
const fs = require('fs');
const path = require('path');

// 带子命令时走 CLI 管理命令（fan-random status/start/... ），无参数启动壁纸服务
const [, , sub] = process.argv;
if (sub) {
  loadCliModule();
} else {
  mainServer();
}

function isSea() {
  try {
    return !process.pkg && require('node:sea').isSea() === true;
  } catch {
    return false;
  }
}

// 加载内置 CLI（bin/fan-random.js）
// - Node / pkg: require 直接解析（pkg 静态跟随依赖）
// - SEA: require 无法解析嵌入资产，改用 fs 读取 + Module._compile 原地执行
function loadCliModule() {
  if (!isSea()) {
    require('./bin/fan-random.js');
    return;
  }
  const Module = require('module');
  const { getAsset } = require('node:sea');
  const source = Buffer.from(getAsset('bin/fan-random.js')).toString('utf8');
  const cliPath = path.join(__dirname, 'bin', 'fan-random.js');
  const m = new Module(cliPath, module);
  m.filename = cliPath;
  m.paths = Module._nodeModulePaths(path.dirname(cliPath));
  m._compile(source, cliPath);
}

// 任何未捕获异常都不应拖垮整个服务：记录日志并让进程继续存活。
// 请求处理中的异常都在 handler 内 try/catch，这里只兜底保险。
process.on('uncaughtException', (err) => {
  console.error(`Uncaught exception (service continues): ${err.stack || err}`);
});

function mainServer() {
  // 程序根目录：pkg 打包产物 __dirname 指向快照目录，用可执行文件所在目录
  const BASE_DIR = process.pkg ? path.dirname(process.execPath) : __dirname;

  const PORT = process.env.PORT || 3000;

  const MIME_TYPES = {
    '.webp': 'image/webp',
    '.jpg': 'image/jpeg',
    '.jpeg': 'image/jpeg',
    '.png': 'image/png',
    '.gif': 'image/gif',
  };

  const IMAGE_REGEX = /\.(webp|jpg|jpeg|png|gif)$/i;

  // pc = 桌面端（横屏），mp = 移动端（竖屏）
  const CATEGORIES = {
    pc: { dir: path.join(BASE_DIR, 'public', 'pc'), label: '桌面端（横屏）' },
    mp: { dir: path.join(BASE_DIR, 'public', 'mp'), label: '移动端（竖屏）' },
  };

  // 公开图片根目录（所有图片文件都必须位于该目录下）
  const PUBLIC_ROOT = path.join(BASE_DIR, 'public');

  // 图片列表缓存：NAS/网络盘上 readdirSync 代价高，切换壁纸的核心瓶颈。
  // 首次请求扫描一次并缓存，之后通过目录 stat（廉价）判断是否需重扫，
  // 避免每次刷新都全量扫描 800+ 文件。stat 失败时不覆盖有效缓存。
  const imageCache = {}; // type -> { list, key, ok }

  function getImageList(type) {
    const cat = CATEGORIES[type];
    if (!cat) return [];
    let key = null;
    let statOk = true;
    try {
      key = String(fs.statSync(cat.dir).mtimeMs);
    } catch {
      statOk = false;
    }
    const cached = imageCache[type];
    // stat 失败（NAS 抖动/目录临时不可读）：沿用上次有效缓存，避免误清空
    if (!statOk) return (cached && cached.ok) ? cached.list : [];
    if (cached && cached.ok && cached.key === key) return cached.list;
    const list = scanImages(cat.dir);
    imageCache[type] = { list, key, ok: true };
    return list;
  }

  // 将请求的图片路径安全解析为公开目录内的绝对路径；越界/非法返回 null
  function resolvePublicImage(imagePath) {
    if (!imagePath || typeof imagePath !== 'string') return null;
    // 只接受 /pc/... 或 /mp/... 常规请求，且不能包含路径穿越
    if (!/^\/(?:pc|mp)\//.test(imagePath) || imagePath.includes('..')) return null;
    const fullPath = path.normalize(path.join(PUBLIC_ROOT, imagePath));
    if (fullPath !== PUBLIC_ROOT && !fullPath.startsWith(PUBLIC_ROOT + path.sep)) return null;
    return fullPath;
  }

  // 只接受安全性可预期的文件名：普通字母数字/下划线/中点/连字符。
  // 防止包含 CR/LF/控制字符的文件名在 302 Location / JSON url 中造成头部注入。
  const SAFE_NAME_REGEX = /^[A-Za-z0-9._-]+$/;

  function scanImages(dir) {
    try {
      if (!fs.existsSync(dir)) {
        console.warn(`Directory not found: ${dir}`);
        return [];
      }
      return fs.readdirSync(dir).filter(f => IMAGE_REGEX.test(f) && SAFE_NAME_REGEX.test(f));
    } catch (err) {
      console.error(`Scan failed ${dir}: ${err.message}`);
      return [];
    }
  }

  function getRandomImage(type) {
    const cat = CATEGORIES[type];
    if (!cat) return null;
    const images = getImageList(type);
    if (images.length === 0) return null;
    return images[Math.floor(Math.random() * images.length)];
  }

  // 直接读取内存中的图片列表（不触碰磁盘），用于 JSON 计数
  function imageCount(type) {
    return imageCache[type] ? imageCache[type].list.length : getImageList(type).length;
  }

  function serveImage(req, res, imagePath, opts) {
    const immutable = !opts || opts.immutable !== false;
    const fullPath = resolvePublicImage(imagePath);
    let stat;
    try {
      stat = fs.statSync(fullPath);
    } catch {
      res.writeHead(404, { 'Content-Type': 'text/plain' });
      res.end('Not Found');
      return;
    }
    if (!stat.isFile()) {
      res.writeHead(404, { 'Content-Type': 'text/plain' });
      res.end('Not Found');
      return;
    }
    const ext = path.extname(fullPath).toLowerCase();
    const contentType = MIME_TYPES[ext] || 'application/octet-stream';
    const etag = `"${stat.size.toString(16)}-${stat.mtimeMs.toString(16)}"`;

    const headers = {
      'Content-Type': contentType,
      'Accept-Ranges': 'bytes',
      // 静态图片文件名不可变（新增图片使用新文件名），可长缓存：
      // 浏览器缓存后，重复图片直接从本地加载，刷新切换壁纸近乎瞬时。
      // 随机端点（/ /pc /mp）每次内容不同，关闭缓存 + 直接返回内容，客户端无需跟随跳转。
      'Cache-Control': immutable
        ? 'public, max-age=31536000, immutable'
        : 'no-cache, no-store, must-revalidate',
    };
    if (immutable) {
      headers.ETag = etag;
      headers['Last-Modified'] = stat.mtime.toUTCString();
    }

    // 处理 If-None-Match：支持列表 / 通配符 * / 弱校验 W/（仅静态 immutable 路径）
    if (immutable && req.headers['if-none-match']) {
      const inm = req.headers['if-none-match'];
      const list = Array.isArray(inm) ? inm : String(inm).split(',');
      const trimmed = list.map(s => s.trim());
      if (trimmed.includes('*') || trimmed.some(t => t.replace(/^W\//, '') === etag)) {
        res.writeHead(304, { ETag: etag, 'Cache-Control': headers['Cache-Control'] });
        res.end();
        return;
      }
    }

    if (req.method !== 'GET' && req.method !== 'HEAD') {
      res.writeHead(405, { 'Content-Type': 'text/plain', Allow: 'GET, HEAD' });
      res.end('Method Not Allowed');
      return;
    }

    // 支持 Range（视频/断点续传类客户端友好）
    const range = req.headers.range;
    if (range && req.method === 'GET') {
      const m = /^bytes=(\d*)-(\d*)$/.exec(range.trim());
      if (m && m[1] !== '' && m[2] !== '') {
        const start = parseInt(m[1], 10);
        const end = Math.min(parseInt(m[2], 10), stat.size - 1);
        if (start <= end && start < stat.size) {
          res.writeHead(206, {
            ...headers,
            'Content-Range': `bytes ${start}-${end}/${stat.size}`,
            'Content-Length': end - start + 1,
          });
          fs.createReadStream(fullPath, { start, end })
            .on('error', () => { try { res.end(); } catch { /* ignore */ } })
            .pipe(res);
          return;
        }
      }
    }

    const outHeaders = { ...headers, 'Content-Length': stat.size };
    if (req.method === 'HEAD') {
      res.writeHead(200, outHeaders);
      res.end();
      return;
    }
    res.writeHead(200, outHeaders);
    const stream = fs.createReadStream(fullPath);
    stream.on('error', () => {
      try {
        if (!res.headersSent) {
          res.writeHead(500, { 'Content-Type': 'text/plain' });
        }
        res.end();
      } catch { /* ignore */ }
    });
    stream.pipe(res);
  }

  function detectMobile(ua) {
    return /android|iphone|ipad|ipod|blackberry|windows phone/i.test(ua);
  }

  function handleApiRequest(req, res, type) {
    const image = getRandomImage(type);
    if (!image) {
      res.writeHead(500, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ error: `No images found in ${type}` }));
      return;
    }

const imageUrl = `/${type}/${image}`;
    const noCache = { 'Cache-Control': 'no-cache, no-store, must-revalidate' };

    // 解析查询参数，畸形 URL 按无参数处理（不能抛异常拉垮服务）
    let typeParam = '';
    try {
      typeParam = new URL(req.url, `http://api.local`).searchParams.get('type') || '';
    } catch { /* ignore */ }

    if (typeParam === 'json') {
      res.writeHead(200, { 'Content-Type': 'application/json', ...noCache });
      res.end(JSON.stringify({ url: imageUrl, type, count: imageCount(type) }));
      return;
    }

    // 直接返回图片内容（200）：客户端（壁纸App/curl/browser）首次请求即拿到图片，
    // 无需跟随跳转也无需二次请求；真实图片请求走 serveImage 的缓存头。
    // 随机端点内容每次不同，Cache-Control 关闭缓存，保证每次刷新都能换到新图。
    serveImage(req, res, imageUrl, { immutable: false });
  }

  const server = http.createServer((req, res) => {
    let url;
    try {
      url = new URL(req.url, `http://${req.headers.host}`);
    } catch {
      // 畸形 Host / URL 头直接 400，不能因此拖垮整个服务
      res.writeHead(400, { 'Content-Type': 'text/plain' });
      res.end('Bad Request');
      return;
    }
    const pathname = url.pathname.replace(/\/$/, '');

    if (pathname === '' || pathname === '/api/index') {
      const type = detectMobile(req.headers['user-agent'] || '') ? 'mp' : 'pc';
      handleApiRequest(req, res, type);
    } else if (pathname === '/pc' || pathname === '/api/pc') {
      handleApiRequest(req, res, 'pc');
    } else if (pathname === '/mp' || pathname === '/api/mp') {
      handleApiRequest(req, res, 'mp');
    } else if (pathname.startsWith('/pc/') || pathname.startsWith('/mp/')) {
      serveImage(req, res, pathname);
    } else {
      res.writeHead(404, { 'Content-Type': 'text/plain' });
      res.end('Not Found');
    }
  });

  server.listen(PORT, () => {
    const publicHost = process.env.PUBLIC_HOST || `http://0.0.0.0:${PORT}`;
    console.log(`fan-random 壁纸服务已启动: ${publicHost}`);
    console.log(`pc 桌面端（横屏）: ${getImageList('pc').length} 张`);
    console.log(`mp 移动端（竖屏）: ${getImageList('mp').length} 张`);
    console.log('');
    console.log('接口列表:');
    console.log(`  ${publicHost}/       - 自适应（电脑/手机）`);
    console.log(`  ${publicHost}/pc     - pc 桌面端（随机横屏）`);
    console.log(`  ${publicHost}/mp     - mp 移动端（随机竖屏）`);
    console.log('  ?type=json   - 返回 JSON');
    console.log('');
    console.log('提示: 管理命令 fan-random --help');
  });
}