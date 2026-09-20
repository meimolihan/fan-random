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
  const images = manifest.pc;

  if (!images || images.length === 0) {
    res.status(500).json({ error: 'No pc(desktop) images found' });
    return;
  }

  const randomImage = images[Math.floor(Math.random() * images.length)];
  const filePath = path.join(__dirname, '..', 'public', 'pc', randomImage);

  if (req.query && req.query.type === 'json') {
    res.setHeader('Cache-Control', 'no-cache, no-store, must-revalidate');
    res.status(200).json({
      url: `/pc/${randomImage}`,
      type: 'pc',
      count: images.length
    });
    return;
  }

  serveImage(res, filePath);
};
