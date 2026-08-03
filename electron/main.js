const path = require('path');
const fs = require('fs');
const os = require('os');
const { fileURLToPath } = require('url');

const electron = require('electron');
const { app, BrowserWindow, dialog, shell, Menu } = electron;

if (!app || typeof app.whenReady !== 'function') {
  console.error(
    'Electron app API yok. Bu dosya yalnızca Electron ana sürecinde çalışır.',
    'typeof electron=',
    typeof electron,
    electron && Object.keys(electron).slice(0, 20),
  );
  process.exit(1);
}

// Packaged: Contents/Resources/app (asar kapalı)
function resolveAppRoot() {
  if (!app.isPackaged) return path.resolve(__dirname, '..');
  const appPath = app.getAppPath();
  if (fs.existsSync(path.join(appPath, 'scripts', 'local_server.js'))) {
    return appPath;
  }
  const sibling = path.join(path.dirname(appPath), 'app');
  if (fs.existsSync(path.join(sibling, 'scripts', 'local_server.js'))) {
    return sibling;
  }
  return appPath;
}

/** Launch cwd may already be deleted (uv_cwd ENOENT). Always chdir to a real dir. */
function ensureValidWorkingDirectory(preferred) {
  const candidates = [
    preferred,
    typeof app.getPath === 'function' ? app.getPath('userData') : null,
    typeof app.getPath === 'function' ? app.getPath('temp') : null,
    os.tmpdir(),
    path.parse(__dirname).root || '/',
  ].filter(Boolean);

  for (const dir of candidates) {
    try {
      const resolved = path.resolve(dir);
      if (!fs.existsSync(resolved)) {
        fs.mkdirSync(resolved, { recursive: true });
      }
      process.chdir(resolved);
      return resolved;
    } catch (_) {
      // try next
    }
  }
  return null;
}

function isAllowedLocalExportPath(filePath, { allowZip = false } = {}) {
  try {
    const resolved = path.resolve(String(filePath || ''));
    const lower = resolved.toLowerCase();
    const okExt =
      lower.endsWith('.pdf') || (allowZip && lower.endsWith('.zip'));
    if (!okExt) return false;
    if (!fs.existsSync(resolved) || !fs.statSync(resolved).isFile()) {
      return false;
    }
    const pdfDir = String(process.env.MICROVISE_PDF_DIR || '').trim();
    const allowedRoots = [
      pdfDir,
      path.join(os.tmpdir(), 'microvise-crm', 'pdfs'),
      typeof app.getPath === 'function'
        ? path.join(app.getPath('temp'), 'microvise-crm', 'pdfs')
        : null,
    ]
      .filter(Boolean)
      .map((dir) => path.resolve(dir));
    return allowedRoots.some(
      (root) => resolved === root || resolved.startsWith(`${root}${path.sep}`),
    );
  } catch (_) {
    return false;
  }
}

function isAllowedPdfPath(filePath) {
  return isAllowedLocalExportPath(filePath, { allowZip: false });
}

function isAllowedOpenExportPath(filePath) {
  return isAllowedLocalExportPath(filePath, { allowZip: true });
}

/**
 * ZIP veya download=1 PDF: Downloads'a kopyalar.
 * Normal PDF: doğrudan açar.
 */
function deliverLocalExport(filePath, { forceDownload = false, downloadName = null } = {}) {
  const resolved = path.resolve(String(filePath || ''));
  if (!isAllowedOpenExportPath(resolved)) return false;
  const lower = resolved.toLowerCase();
  const isZip = lower.endsWith('.zip');
  const isPdf = lower.endsWith('.pdf');
  if (isZip || (forceDownload && isPdf)) {
    try {
      const downloadsDir = app.getPath('downloads');
      fs.mkdirSync(downloadsDir, { recursive: true });
      let base = String(downloadName || path.basename(resolved)).trim();
      base = base.replace(/[^a-zA-Z0-9._-]+/g, '_') || path.basename(resolved);
      if (isPdf && !base.toLowerCase().endsWith('.pdf')) {
        base = `${base}.pdf`;
      }
      if (isZip && !base.toLowerCase().endsWith('.zip')) {
        base = `${base}.zip`;
      }
      let dest = path.join(downloadsDir, base);
      if (fs.existsSync(dest)) {
        const ext = path.extname(base);
        const stem = path.basename(base, ext);
        let i = 2;
        while (fs.existsSync(dest)) {
          dest = path.join(downloadsDir, `${stem}_${i}${ext}`);
          i += 1;
        }
      }
      fs.copyFileSync(resolved, dest);
      // ZIP tek dosya: Finder'da göster. Toplu PDF'de sessiz kopya (çok pencere yok).
      if (isZip) shell.showItemInFolder(dest);
      return true;
    } catch (_) {
      shell.openPath(resolved);
      return true;
    }
  }
  shell.openPath(resolved);
  return true;
}

function envHasDb(filePath) {
  if (!fs.existsSync(filePath)) return false;
  try {
    const text = fs.readFileSync(filePath, 'utf8');
    return /^(DATABASE_URL|POSTGRES_URL|NEON_DATABASE_URL)\s*=\s*\S+/m.test(
      text,
    );
  } catch (_) {
    return false;
  }
}

function loadEnvIntoProcess(filePath, { override = false } = {}) {
  if (!fs.existsSync(filePath)) return;
  const content = fs.readFileSync(filePath, 'utf8');
  for (const rawLine of content.split('\n')) {
    const line = rawLine.trim();
    if (!line || line.startsWith('#')) continue;
    const eq = line.indexOf('=');
    if (eq <= 0) continue;
    const key = line.slice(0, eq).trim();
    let value = line.slice(eq + 1).trim();
    if (!key) continue;
    if (
      (value.startsWith('"') && value.endsWith('"')) ||
      (value.startsWith("'") && value.endsWith("'"))
    ) {
      value = value.slice(1, -1);
    }
    const current = process.env[key];
    if (override || current == null || current === '') {
      process.env[key] = value;
    }
  }
}

/** Paketli .app içinde .env.local yok; userData + geliştirme kökünden senkronize et. */
function ensureEnvLocal(root, userData) {
  const userEnv = path.join(userData, '.env.local');
  const candidates = [
    path.join(root, '.env.local'),
    // unpackaged / monorepo
    path.resolve(__dirname, '..', '.env.local'),
    // .app yanındaki klasör (manuel kopya)
    path.join(path.dirname(process.execPath), '..', '..', '..', '.env.local'),
  ];

  let source = null;
  for (const candidate of candidates) {
    if (envHasDb(candidate)) {
      source = candidate;
      break;
    }
  }

  const shouldCopy =
    !!source &&
    (!envHasDb(userEnv) ||
      (fs.existsSync(userEnv) &&
        fs.statSync(source).mtimeMs > fs.statSync(userEnv).mtimeMs + 1000));
  if (shouldCopy && source) {
    try {
      fs.mkdirSync(userData, { recursive: true });
      fs.copyFileSync(source, userEnv);
    } catch (_) {
      // yoksay
    }
  }

  // require(local_server) öncesi process.env'e bas — JWT / MASTER / DB kesin gelsin.
  if (envHasDb(userEnv)) {
    loadEnvIntoProcess(userEnv, { override: true });
  } else if (source) {
    loadEnvIntoProcess(source, { override: true });
  }

  return { userEnv, source, hasDb: !!(process.env.DATABASE_URL || process.env.POSTGRES_URL || process.env.NEON_DATABASE_URL) };
}

let mainWindow = null;
let localServer = null;

async function startBridge() {
  const root = resolveAppRoot();
  // Önce geçerli bir cwd garantile (silinmiş launch dir → uv_cwd), sonra app root.
  ensureValidWorkingDirectory(root);
  if (fs.existsSync(root)) {
    try {
      process.chdir(root);
    } catch (_) {
      ensureValidWorkingDirectory(app.getPath('userData'));
    }
  }

  const userData = app.getPath('userData');
  const pdfDir = path.join(app.getPath('temp'), 'microvise-crm', 'pdfs');
  fs.mkdirSync(pdfDir, { recursive: true });

  process.env.MICROVISE_APP_ROOT = root;
  process.env.MICROVISE_ENV_DIR = userData;
  process.env.MICROVISE_PDF_DIR = pdfDir;

  const envState = ensureEnvLocal(root, userData);
  if (!envState.hasDb) {
    throw new Error(
      `DATABASE_URL bulunamadı.\n` +
        `.env.local şuraya koyun:\n${path.join(userData, '.env.local')}\n` +
        `(proje kökündeki .env.local kopyalanabilir)`,
    );
  }

  // 4010: geliştirme local_server (:4000) ile çakışmasın; pencere kendi köprüsüne bağlanır.
  const preferred = Number(
    process.env.MICROVISE_ELECTRON_PORT || process.env.PORT || 4010,
  );
  const { startLocalServer } = require(path.join(
    root,
    'scripts',
    'local_server.js',
  ));

  const tryPorts = [preferred, 4011, 4012, 0];
  let lastErr;
  for (const port of tryPorts) {
    try {
      process.env.PORT = String(port);
      const started = await startLocalServer({
        port,
        host: '127.0.0.1',
        exitOnBusy: false,
      });
      process.env.MICROVISE_LOCAL_ORIGIN =
        started?.url || `http://127.0.0.1:${started?.port || port}`;
      return started;
    } catch (err) {
      lastErr = err;
      if (!String(err.message || err).includes('kullanımda')) throw err;
    }
  }
  throw lastErr || new Error('Yerel API portu açılamadı.');
}

function createWindow(url) {
  mainWindow = new BrowserWindow({
    width: 1440,
    height: 900,
    minWidth: 1024,
    minHeight: 700,
    title: 'Microvise CRM',
    backgroundColor: '#4A617C',
    webPreferences: {
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: true,
    },
    show: false,
  });

  mainWindow.once('ready-to-show', () => {
    mainWindow.show();
    // Flutter web (CanvasKit) sometimes sizes its rendering surface off the
    // window's pre-show bounds; the result is a tiny/scaled paint in the
    // corner of an otherwise-blank window. Nudging the size by 1px right
    // after show forces a real resize event so Flutter recomputes the
    // surface against the actual on-screen bounds.
    const bounds = mainWindow.getBounds();
    mainWindow.setBounds({ ...bounds, width: bounds.width + 1 });
    setTimeout(() => {
      if (mainWindow && !mainWindow.isDestroyed()) {
        mainWindow.setBounds(bounds);
      }
    }, 60);
  });

  mainWindow.webContents.setWindowOpenHandler(({ url: target }) => {
    try {
      const parsed = new URL(target);
      if (parsed.protocol === 'file:') {
        const filePath = fileURLToPath(parsed);
        if (isAllowedLocalExportPath(filePath, { allowZip: true })) {
          shell.openPath(filePath);
          return { action: 'deny' };
        }
      }
      if (parsed.pathname === '/api/_local/open-pdf') {
        const filePath = parsed.searchParams.get('path');
        if (filePath && isAllowedOpenExportPath(filePath)) {
          const dl = String(parsed.searchParams.get('download') || '')
            .trim()
            .toLowerCase();
          const forceDownload = dl === '1' || dl === 'true';
          const downloadName = parsed.searchParams.get('name');
          deliverLocalExport(filePath, {
            forceDownload,
            downloadName,
          });
          return { action: 'deny' };
        }
      }
      if (parsed.pathname === '/api/_local/reveal-file') {
        const filePath = parsed.searchParams.get('path');
        if (
          filePath &&
          isAllowedLocalExportPath(filePath, { allowZip: true })
        ) {
          shell.showItemInFolder(path.resolve(filePath));
          return { action: 'deny' };
        }
      }
    } catch (_) {
      // fall through to openExternal
    }
    shell.openExternal(target);
    return { action: 'deny' };
  });

  mainWindow.on('closed', () => {
    mainWindow = null;
  });

  return mainWindow.loadURL(url);
}

/**
 * Önceden hiç menü/reload kısayolu yoktu: pencere açık kalırken yeni bir
 * `flutter build web` yapılsa bile kullanıcı sayfayı yenileyemiyordu (yalnızca
 * uygulamayı tamamen kapatıp yeniden açmak "çalışıyordu", o da Chromium'un
 * disk cache'i main.dart.js'i eskiden tutarsa yine işe yaramıyordu). Cmd/Ctrl+R
 * artık cache'i atlayarak (`reloadIgnoringCache`) yeniden yüklüyor.
 */
function applyMenu() {
  const template = [
    {
      label: 'Microvise CRM',
      submenu: [
        { role: 'about' },
        { type: 'separator' },
        { role: 'quit' },
      ],
    },
    {
      label: 'Düzen',
      submenu: [
        { role: 'undo' },
        { role: 'redo' },
        { type: 'separator' },
        { role: 'cut' },
        { role: 'copy' },
        { role: 'paste' },
        { role: 'selectAll' },
      ],
    },
    {
      label: 'Görünüm',
      submenu: [
        {
          label: 'Yeniden Yükle',
          accelerator: 'CmdOrCtrl+R',
          click: () => {
            if (mainWindow && !mainWindow.isDestroyed()) {
              mainWindow.webContents.reloadIgnoringCache();
            }
          },
        },
        {
          label: 'Geliştirici Araçları',
          accelerator: 'CmdOrCtrl+Alt+I',
          click: () => {
            if (mainWindow && !mainWindow.isDestroyed()) {
              mainWindow.webContents.toggleDevTools();
            }
          },
        },
        { type: 'separator' },
        { role: 'resetZoom' },
        { role: 'zoomIn' },
        { role: 'zoomOut' },
        { type: 'separator' },
        { role: 'togglefullscreen' },
      ],
    },
    {
      label: 'Pencere',
      submenu: [{ role: 'minimize' }, { role: 'close' }],
    },
  ];
  Menu.setApplicationMenu(Menu.buildFromTemplate(template));
}

async function bootstrap() {
  try {
    // app ready sonrası userData/temp erişilebilir; cwd'yi hemen düzelt.
    ensureValidWorkingDirectory(resolveAppRoot());
    applyMenu();
    localServer = await startBridge();
    await createWindow(localServer.url);
  } catch (err) {
    const message =
      err instanceof Error ? err.message : String(err || 'Bilinmeyen hata');
    dialog.showErrorBox(
      'Microvise CRM başlatılamadı',
      `${message}\n\nbuild/web var mı? npm run electron:build-web çalıştırın.\n.env.local: ${app.getPath('userData')}`,
    );
    app.quit();
  }
}

const gotLock = app.requestSingleInstanceLock();
if (!gotLock) {
  app.quit();
} else {
  app.on('second-instance', () => {
    if (mainWindow) {
      if (mainWindow.isMinimized()) mainWindow.restore();
      mainWindow.focus();
    }
  });

  app.whenReady().then(bootstrap);

  app.on('activate', () => {
    if (BrowserWindow.getAllWindows().length === 0 && localServer) {
      createWindow(localServer.url);
    }
  });

  app.on('window-all-closed', () => {
    if (process.platform !== 'darwin') app.quit();
  });

  app.on('before-quit', () => {
    try {
      localServer?.server?.close();
    } catch (_) {
      // yoksay
    }
  });
}
