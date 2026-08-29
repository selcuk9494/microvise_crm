const { query } = require('./db');

function escapeHtml(input) {
  return String(input ?? '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#039;');
}

function isValidEmail(value) {
  const email = String(value || '').trim();
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email);
}

function pick(source, ...keys) {
  if (!source || typeof source !== 'object') return '';
  for (const key of keys) {
    const value = source[key];
    if (value != null && String(value).trim()) return String(value).trim();
  }
  return '';
}

function truthy(value) {
  const v = String(value ?? '')
    .trim()
    .toLowerCase();
  return v === 'true' || v === '1' || v === 'yes' || v === 'on';
}

function normalizeSmtpPass(value) {
  return String(value || '').replace(/\s+/g, '');
}

function smtpFromSource(source, { host, port, secure, user, pass, from }) {
  return {
    host: pick(source, host),
    port: pick(source, port) || '587',
    secure: truthy(source?.[secure]),
    user: pick(source, user),
    pass: normalizeSmtpPass(pick(source, pass)),
    from: pick(source, from),
  };
}

function smtpFromEnv() {
  return smtpFromSource(process.env, {
    host: 'SMTP_HOST',
    port: 'SMTP_PORT',
    secure: 'SMTP_SECURE',
    user: 'SMTP_USER',
    pass: 'SMTP_PASS',
    from: 'SMTP_FROM',
  });
}

function smtpFromRow(row) {
  return smtpFromSource(row || {}, {
    host: 'smtp_host',
    port: 'smtp_port',
    secure: 'smtp_secure',
    user: 'smtp_user',
    pass: 'smtp_pass',
    from: 'smtp_from',
  });
}

function isUsableSmtp(config) {
  return Boolean(config?.host && config?.user && config?.pass);
}

function formatFrom(config) {
  const from = String(config?.from || '').trim();
  if (from) return from;
  if (config?.user) return `Microvise Innovation <${config.user}>`;
  return (
    process.env.RESEND_FROM ||
    process.env.MAIL_FROM ||
    'Microvise Innovation <noreply@microvise.net>'
  );
}

function mergeSmtp(primary, fallback) {
  if (!primary && !fallback) return null;
  const merged = {
    host: primary?.host || fallback?.host || '',
    port: primary?.port || fallback?.port || '587',
    secure: Boolean(primary?.host ? primary.secure : fallback?.secure),
    user: primary?.user || fallback?.user || '',
    pass: primary?.pass || fallback?.pass || '',
    from: primary?.from || fallback?.from || '',
  };
  return isUsableSmtp(merged) ? merged : null;
}

async function loadStoredSmtp() {
  try {
    const result = await query(`
      select smtp_host, smtp_port, smtp_secure, smtp_user, smtp_pass, smtp_from
      from public.e_invoice_settings
      where is_active = true
      order by created_at asc
      limit 1
    `);
    return smtpFromRow(result.rows[0]);
  } catch (_) {
    return smtpFromRow(null);
  }
}

async function resolveMailConfig() {
  const stored = await loadStoredSmtp();
  const envSmtp = smtpFromEnv();
  const smtp = mergeSmtp(stored, envSmtp);
  const resendKey = String(process.env.RESEND_API_KEY || '').trim();
  return {
    smtp,
    resendKey,
    from: formatFrom(smtp || { from: pick(process.env, 'RESEND_FROM', 'MAIL_FROM') }),
  };
}

function getMailConfig() {
  const envSmtp = smtpFromEnv();
  const apiKey = String(process.env.RESEND_API_KEY || '').trim();
  return {
    apiKey,
    from: formatFrom(envSmtp),
    smtp: isUsableSmtp(envSmtp) ? envSmtp : null,
  };
}

function mapAttachments(attachments) {
  if (!Array.isArray(attachments) || !attachments.length) return [];
  return attachments
    .map((item) => {
      if (!item || typeof item !== 'object') return null;
      const filename = String(item.filename || 'ek').trim() || 'ek';
      const content = item.content;
      if (content == null || content === '') return null;
      return {
        filename,
        content,
        encoding: typeof content === 'string' ? 'base64' : undefined,
        contentType: item.contentType || item.content_type || undefined,
      };
    })
    .filter(Boolean);
}

async function sendViaSmtp(config, { to, subject, html, text, attachments }) {
  let nodemailer;
  try {
    nodemailer = require('nodemailer');
  } catch (_) {
    const error = new Error(
      'SMTP gönderimi için nodemailer kurulu değil. `npm install nodemailer` çalıştırın.',
    );
    error.statusCode = 500;
    throw error;
  }
  const port = Number.parseInt(String(config.port || '587'), 10) || 587;
  const transporter = nodemailer.createTransport({
    host: config.host,
    port,
    secure: config.secure || port === 465,
    auth: {
      user: config.user,
      pass: config.pass,
    },
  });
  return transporter.sendMail({
    from: formatFrom(config),
    to: Array.isArray(to) ? to.join(', ') : to,
    subject,
    html: html || undefined,
    text: text || undefined,
    attachments: mapAttachments(attachments),
  });
}

async function sendViaResend({ apiKey, from }, { to, subject, html, text, attachments }) {
  const payload = {
    from,
    to: Array.isArray(to) ? to : [to],
    subject,
    html: String(html || ''),
  };
  if (text) payload.text = String(text);
  if (Array.isArray(attachments) && attachments.length) {
    payload.attachments = attachments;
  }
  const response = await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${apiKey}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(payload),
  });
  const data = await response.json().catch(() => ({}));
  if (!response.ok) {
    const detail =
      data?.message ||
      data?.error?.message ||
      (typeof data?.error === 'string' ? data.error : '') ||
      `HTTP ${response.status}`;
    const error = new Error(`E-posta gönderilemedi: ${detail}`);
    error.statusCode = 502;
    throw error;
  }
  return data;
}

async function sendEmail({ to, subject, html, text, attachments, smtpOverride }) {
  const recipients = (Array.isArray(to) ? to : [to])
    .map((item) => String(item || '').trim())
    .filter(isValidEmail);
  if (!recipients.length) {
    const error = new Error('Geçerli bir e-posta adresi gerekli.');
    error.statusCode = 400;
    throw error;
  }

  const config = await resolveMailConfig();
  if (smtpOverride && typeof smtpOverride === 'object') {
    const overlay = smtpFromRow(smtpOverride);
    config.smtp = mergeSmtp(overlay, config.smtp);
    if (config.smtp) config.from = formatFrom(config.smtp);
  }
  const mail = {
    to: recipients,
    subject: String(subject || 'Microvise').trim() || 'Microvise',
    html,
    text,
    attachments,
  };

  if (config.smtp) {
    try {
      return await sendViaSmtp(config.smtp, mail);
    } catch (error) {
      if (config.resendKey) {
        return sendViaResend(
          { apiKey: config.resendKey, from: config.from },
          mail,
        );
      }
      const detail = error?.message || 'SMTP gönderimi başarısız.';
      const wrapped = new Error(`E-posta gönderilemedi: ${detail}`);
      wrapped.statusCode = error?.statusCode || 502;
      throw wrapped;
    }
  }

  if (config.resendKey) {
    return sendViaResend(
      { apiKey: config.resendKey, from: config.from },
      mail,
    );
  }

  const error = new Error(
    'E-posta gönderimi yapılandırılmamış. E-Fatura > Ayarlar bölümüne SMTP bilgilerini kaydedin.',
  );
  error.statusCode = 400;
  throw error;
}

module.exports = {
  escapeHtml,
  getMailConfig,
  isValidEmail,
  sendEmail,
  resolveMailConfig,
  smtpFromEnv,
  smtpFromRow,
  isUsableSmtp,
  formatFrom,
  mergeSmtp,
};
