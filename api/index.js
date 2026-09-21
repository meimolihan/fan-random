const fs = require('fs');
const path = require('path');
const manifest = require('./_manifest');

const MIME_TYPES = {
  '.webp': 'image/webp',
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.png': 'image/png',
  '.gif': 'image/gif',
};

module.exports = (req, res) => {
  const ua = req.headers['user-agent'] || '';
  const isMobile = /android|iphone|ipad|ipod|blackberry|windows phone/i.test(ua);
  const type = isMobile ? 'mp' : 'pc';
  const images = manifest[type];

  if (!images || images.length === 0) {
    res.status(500).json({ error: `No images found in ${type}` });
    return;
  }

  const randomImage = images[Math.floor(Math.random() * images.length)];
  const imageUrl = `/${type}/${randomImage}`;

  if (req.query && req.query.type === 'json') {
    res.setHeader('Cache-Control', 'no-cache, no-store, must-revalidate');
    res.status(200).json({
      url: imageUrl,
      type,
      count: images.length
    });
    return;
  }

  // 直接返回图片内容（200）：客户端首次请求即拿到图片，无需跟随跳转。
  // 随机端点每次内容不同，关闭缓存，保证每次刷新都能换到新图。
  const filePath = path.join(__dirname, '..', 'public', type, randomImage);
  let stat;
  try {
    stat = fs.statSync(filePath);
  } catch {
    res.writeHead(404, { 'Content-Type': 'text/plain' });
    res.end('Not Found');
    return;
  }
  const ext = path.extname(filePath).toLowerCase();
  res.writeHead(200, {
    'Content-Type': MIME_TYPES[ext] || 'application/octet-stream',
    'Content-Length': stat.size,
    'Cache-Control': 'no-cache, no-store, must-revalidate'
  });
  fs.createReadStream(filePath).pipe(res);
};