(() => {
  const req = typeof require === 'function' ? require : process.mainModule.require.bind(process.mainModule);
  const { app, BrowserWindow } = req('electron');
  if (globalThis.__backgroundHideHelper) return { installed: true, pid: process.pid };
  let quitting = false;
  const rulesPath = req('path').join(req('os').homedir(), 'Library/Application Support/DockHush/rules.json');
  let closeHidden = true;
  let dockHidden = true;
  const readRules = () => {
    try {
      const rules = JSON.parse(req('fs').readFileSync(rulesPath, 'utf8'));
      if (Array.isArray(rules.close)) closeHidden = rules.close.includes('com.zentraedi.zspaceMacApp');
      if (Array.isArray(rules.dock)) dockHidden = rules.dock.includes('com.zentraedi.zspaceMacApp');
    } catch {}
  };
  readRules();
  const attached = new WeakSet();
  const hideDock = () => {
    if (quitting || !app.dock) return;
    if (dockHidden && app.dock.isVisible()) app.dock.hide();
    if (!dockHidden && !app.dock.isVisible()) app.dock.show();
  };
  const attach = win => {
    if (attached.has(win) || win.isDestroyed()) return;
    // Ignore child dialogs and small tray/notification windows.
    const [width, height] = win.getSize();
    if (win.getParentWindow() || width < 500 || height < 300) return;
    attached.add(win);
    win.prependListener('close', event => {
      readRules();
      if (quitting || !closeHidden) return;
      event.preventDefault();
      win.hide();
      hideDock();
      setImmediate(hideDock);
    });
    win.on('show', () => { hideDock(); setImmediate(hideDock); });
    win.on('focus', hideDock);
  };
  app.on('before-quit', () => { quitting = true; });
  app.on('browser-window-created', (_, win) => {
    attach(win);
    win.once('ready-to-show', () => attach(win));
  });
  app.on('activate', () => { hideDock(); setImmediate(hideDock); });
  app.on('second-instance', (_, argv) => {
    hideDock();
    setImmediate(() => {
      if (argv.includes('--background-hide-helper-hide')) {
        BrowserWindow.getAllWindows().forEach(win => {
          const [w,h]=win.getSize();
          if (!win.getParentWindow() && w>=500 && h>=300) win.hide();
        });
      }
      hideDock();
    });
  });
  BrowserWindow.getAllWindows().forEach(attach);
  const timer = setInterval(() => {
    if (quitting) return;
    readRules();
    BrowserWindow.getAllWindows().forEach(attach);
    hideDock();
  }, 1000);
  timer.unref();
  globalThis.__backgroundHideHelper = { installed: true, pid: process.pid };
  hideDock();
  return { installed: true, pid: process.pid, windows: BrowserWindow.getAllWindows().length, rulesVersion: 2 };
})()
