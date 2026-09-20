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

function serveImage(res, filePath) {
  const ext = path.extname(filePath).toLowerCase();
  res.setHeader('Content-Type', MIME_TYPES[ext] || 'application/octet-stream');
  res.setHeader('Cache-Control', 'no-cache, no-store, must-revalidate');
  res.status(200).send(fs.readFileSync(filePath));
}

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
  const filePath = path.join(__dirname, '..', 'public', type, randomImage);

  if (req.query && req.query.type === 'json') {
    res.setHeader('Cache-Control', 'no-cache, no-store, must-revalidate');
    res.status(200).json({
      url: `/${type}/${randomImage}`,
      type,
      count: images.length
    });
    return;
  }

  serveImage(res, filePath);
};
