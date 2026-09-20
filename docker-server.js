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

  function scanImages(dir) {
    try {
      if (!fs.existsSync(dir)) {
        console.warn(`Directory not found: ${dir}`);
        return [];
      }
      return fs.readdirSync(dir).filter(f => IMAGE_REGEX.test(f));
    } catch (err) {
      console.error(`Scan failed ${dir}: ${err.message}`);
      return [];
    }
  }

  function getRandomImage(type) {
    const cat = CATEGORIES[type];
    if (!cat) return null;
    const images = scanImages(cat.dir);
    if (images.length === 0) return null;
    return images[Math.floor(Math.random() * images.length)];
  }

  function serveImage(res, imagePath) {
    const fullPath = path.join(BASE_DIR, 'public', imagePath);
    if (!fs.existsSync(fullPath)) {
      res.writeHead(404, { 'Content-Type': 'text/plain' });
      res.end('Not Found');
      return;
    }
    const ext = path.extname(fullPath).toLowerCase();
    const contentType = MIME_TYPES[ext] || 'application/octet-stream';
    const stat = fs.statSync(fullPath);
    res.writeHead(200, {
      'Content-Type': contentType,
      'Content-Length': stat.size,
      'Cache-Control': 'no-cache, no-store, must-revalidate',
    });
    fs.createReadStream(fullPath).pipe(res);
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
    const params = new URL(req.url, `http://${req.headers.host}`).searchParams;
    const noCache = { 'Cache-Control': 'no-cache, no-store, must-revalidate' };

    if (params.get('type') === 'json') {
      const images = scanImages(CATEGORIES[type].dir);
      res.writeHead(200, { 'Content-Type': 'application/json', ...noCache });
      res.end(JSON.stringify({ url: imageUrl, type, count: images.length }));
      return;
    }

    serveImage(res, imageUrl);
  }

  const server = http.createServer((req, res) => {
    const url = new URL(req.url, `http://${req.headers.host}`);
    const pathname = url.pathname.replace(/\/$/, '');

    if (pathname === '' || pathname === '/api/index') {
      const type = detectMobile(req.headers['user-agent'] || '') ? 'mp' : 'pc';
      handleApiRequest(req, res, type);
    } else if (pathname === '/pc' || pathname === '/api/pc') {
      handleApiRequest(req, res, 'pc');
    } else if (pathname === '/mp' || pathname === '/api/mp') {
      handleApiRequest(req, res, 'mp');
    } else if (pathname.startsWith('/pc/') || pathname.startsWith('/mp/')) {
      serveImage(res, pathname);
    } else {
      res.writeHead(404, { 'Content-Type': 'text/plain' });
      res.end('Not Found');
    }
  });

  server.listen(PORT, () => {
    const publicHost = process.env.PUBLIC_HOST || `http://0.0.0.0:${PORT}`;
    console.log(`fan-random 壁纸服务已启动: ${publicHost}`);
    console.log(`pc 桌面端（横屏）: ${scanImages(CATEGORIES.pc.dir).length} 张`);
    console.log(`mp 移动端（竖屏）: ${scanImages(CATEGORIES.mp.dir).length} 张`);
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