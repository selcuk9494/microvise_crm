const QRCode = require('qrcode');
const { PNG } = require('pngjs');

// 5x7 glyphs, row-major, bit 4 = leftmost pixel.
const GLYPHS = {
  ' ': 0,
  0: [0x0e, 0x11, 0x13, 0x15, 0x19, 0x11, 0x0e],
  1: [0x04, 0x0c, 0x04, 0x04, 0x04, 0x04, 0x0e],
  2: [0x0e, 0x11, 0x01, 0x06, 0x08, 0x10, 0x1f],
  3: [0x0e, 0x11, 0x01, 0x06, 0x01, 0x11, 0x0e],
  4: [0x02, 0x06, 0x0a, 0x12, 0x1f, 0x02, 0x02],
  5: [0x1f, 0x10, 0x1e, 0x01, 0x01, 0x11, 0x0e],
  6: [0x06, 0x08, 0x10, 0x1e, 0x11, 0x11, 0x0e],
  7: [0x1f, 0x01, 0x02, 0x04, 0x08, 0x08, 0x08],
  8: [0x0e, 0x11, 0x11, 0x0e, 0x11, 0x11, 0x0e],
  9: [0x0e, 0x11, 0x11, 0x0f, 0x01, 0x02, 0x0c],
  A: [0x0e, 0x11, 0x11, 0x1f, 0x11, 0x11, 0x11],
  B: [0x1e, 0x11, 0x11, 0x1e, 0x11, 0x11, 0x1e],
  C: [0x0e, 0x11, 0x10, 0x10, 0x10, 0x11, 0x0e],
  D: [0x1e, 0x11, 0x11, 0x11, 0x11, 0x11, 0x1e],
  E: [0x1f, 0x10, 0x10, 0x1e, 0x10, 0x10, 0x1f],
  F: [0x1f, 0x10, 0x10, 0x1e, 0x10, 0x10, 0x10],
  G: [0x0e, 0x11, 0x10, 0x17, 0x11, 0x11, 0x0e],
  H: [0x11, 0x11, 0x11, 0x1f, 0x11, 0x11, 0x11],
  I: [0x0e, 0x04, 0x04, 0x04, 0x04, 0x04, 0x0e],
  J: [0x01, 0x01, 0x01, 0x01, 0x11, 0x11, 0x0e],
  K: [0x11, 0x12, 0x14, 0x18, 0x14, 0x12, 0x11],
  L: [0x10, 0x10, 0x10, 0x10, 0x10, 0x10, 0x1f],
  M: [0x11, 0x1b, 0x15, 0x15, 0x11, 0x11, 0x11],
  N: [0x11, 0x19, 0x15, 0x13, 0x11, 0x11, 0x11],
  O: [0x0e, 0x11, 0x11, 0x11, 0x11, 0x11, 0x0e],
  P: [0x1e, 0x11, 0x11, 0x1e, 0x10, 0x10, 0x10],
  R: [0x1e, 0x11, 0x11, 0x1e, 0x14, 0x12, 0x11],
  S: [0x0e, 0x11, 0x10, 0x0e, 0x01, 0x11, 0x0e],
  T: [0x1f, 0x04, 0x04, 0x04, 0x04, 0x04, 0x04],
  U: [0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x0e],
  V: [0x11, 0x11, 0x11, 0x11, 0x11, 0x0a, 0x04],
  Y: [0x11, 0x11, 0x0a, 0x04, 0x04, 0x04, 0x04],
  '.': [0x00, 0x00, 0x00, 0x00, 0x00, 0x0c, 0x0c],
  ',': [0x00, 0x00, 0x00, 0x00, 0x0c, 0x04, 0x08],
  '-': [0x00, 0x00, 0x00, 0x1f, 0x00, 0x00, 0x00],
  ':': [0x00, 0x0c, 0x0c, 0x00, 0x0c, 0x0c, 0x00],
  $: [0x04, 0x0f, 0x14, 0x0e, 0x05, 0x1e, 0x04],
};

function setPixel(png, x, y, rgb) {
  if (x < 0 || y < 0 || x >= png.width || y >= png.height) return;
  const i = (png.width * y + x) << 2;
  png.data[i] = rgb[0];
  png.data[i + 1] = rgb[1];
  png.data[i + 2] = rgb[2];
  png.data[i + 3] = 255;
}

function fillRect(png, x, y, w, h, rgb) {
  const x2 = Math.min(png.width, x + w);
  const y2 = Math.min(png.height, y + h);
  const x0 = Math.max(0, x);
  const y0 = Math.max(0, y);
  for (let yy = y0; yy < y2; yy += 1) {
    for (let xx = x0; xx < x2; xx += 1) setPixel(png, xx, yy, rgb);
  }
}

function fillRoundRect(png, x, y, w, h, r, rgb) {
  const radius = Math.max(0, Math.min(r, Math.floor(Math.min(w, h) / 2)));
  fillRect(png, x + radius, y, w - radius * 2, h, rgb);
  fillRect(png, x, y + radius, w, h - radius * 2, rgb);
  for (let oy = 0; oy < radius; oy += 1) {
    for (let ox = 0; ox < radius; ox += 1) {
      if (ox * ox + oy * oy <= radius * radius) {
        setPixel(png, x + radius - 1 - ox, y + radius - 1 - oy, rgb);
        setPixel(png, x + w - radius + ox, y + radius - 1 - oy, rgb);
        setPixel(png, x + radius - 1 - ox, y + h - radius + oy, rgb);
        setPixel(png, x + w - radius + ox, y + h - radius + oy, rgb);
      }
    }
  }
}

function drawChar(png, ch, x, y, scale, rgb) {
  const glyph = GLYPHS[ch] || GLYPHS[ch.toUpperCase()];
  if (!glyph || glyph === 0) {
    return 4 * scale;
  }
  for (let row = 0; row < 7; row += 1) {
    const bits = glyph[row];
    for (let col = 0; col < 5; col += 1) {
      if (bits & (1 << (4 - col))) {
        fillRect(png, x + col * scale, y + row * scale, scale, scale, rgb);
      }
    }
  }
  return 6 * scale;
}

function drawText(png, text, x, y, scale, rgb) {
  let cx = x;
  for (const raw of String(text || '')) {
    const ch = raw === 'İ' ? 'I' : raw === 'ı' ? 'I' : raw;
    cx += drawChar(png, ch, cx, y, scale, rgb);
  }
  return cx - x;
}

function textWidth(text, scale) {
  return String(text || '').length * 6 * scale;
}

function asciiAmount(label) {
  return String(label || '')
    .replace(/₺/g, 'TL')
    .replace(/€/g, 'EUR')
    .replace(/£/g, 'GBP')
    .replace(/[^\w.,:\- $]/g, ' ')
    .replace(/\s+/g, ' ')
    .trim()
    .toUpperCase();
}

function blit(dest, src, dx, dy) {
  for (let y = 0; y < src.height; y += 1) {
    for (let x = 0; x < src.width; x += 1) {
      const si = (src.width * y + x) << 2;
      if (src.data[si + 3] < 80) continue;
      setPixel(dest, dx + x, dy + y, [
        src.data[si],
        src.data[si + 1],
        src.data[si + 2],
      ]);
    }
  }
}

async function buildPaymentOgImage({
  amountLabel,
  pageUrl,
  invoiceLabel = '',
}) {
  const width = 1200;
  const height = 630;
  const png = new PNG({ width, height });
  const navy = [30, 58, 95];
  const blue = [29, 78, 216];
  const white = [255, 255, 255];
  const ink = [15, 23, 42];
  const muted = [100, 116, 139];
  const page = [241, 245, 249];

  fillRect(png, 0, 0, width, height, page);
  fillRoundRect(png, 36, 36, width - 72, height - 72, 28, white);
  fillRoundRect(png, 36, 36, width - 72, 132, 28, navy);
  fillRect(png, 36, 120, width - 72, 48, navy);

  drawText(png, 'MICROVISE', 72, 72, 6, white);
  drawText(png, 'GUVENLI FATURA ODEMESI', 72, 122, 3, [191, 219, 254]);

  const amount = asciiAmount(amountLabel) || '0,00 TL';
  const amountScale = amount.length > 16 ? 7 : 9;
  drawText(png, amount, 72, 210, amountScale, ink);

  const invoice = String(invoiceLabel || '')
    .replace(/[^\w.,\- ]/g, ' ')
    .trim()
    .toUpperCase()
    .slice(0, 42);
  if (invoice) {
    drawText(png, invoice, 72, 210 + 7 * amountScale + 18, 3, muted);
  }

  const btnLabel = 'GUVENLI ODEME YAP';
  const btnScale = 5;
  const btnW = textWidth(btnLabel, btnScale) + 64;
  const btnH = 7 * btnScale + 40;
  const btnX = 72;
  const btnY = 430;
  fillRoundRect(png, btnX, btnY, btnW, btnH, 16, blue);
  drawText(
    png,
    btnLabel,
    btnX + 32,
    btnY + 20,
    btnScale,
    white,
  );

  if (pageUrl) {
    try {
      const qrBuf = await QRCode.toBuffer(pageUrl, {
        type: 'png',
        width: 220,
        margin: 1,
        color: { dark: '#0f172a', light: '#ffffff' },
      });
      const qr = PNG.sync.read(qrBuf);
      blit(png, qr, 900, 250);
    } catch (_) {
      // QR is optional; the CTA still reads as a payment button.
    }
  }

  return PNG.sync.write(png);
}

module.exports = {
  buildPaymentOgImage,
  asciiAmount,
};
