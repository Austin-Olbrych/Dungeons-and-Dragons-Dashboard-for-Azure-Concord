// Azure Concord · loader for Scriptable
// Paste this into a new Scriptable script (name it "Azure Concord"). It downloads the latest widget from GitHub
// each time it runs, keeps a copy for when you're offline, and runs it. Updates on GitHub reach your phone by themselves.
const URL = 'https://raw.githubusercontent.com/Austin-Olbrych/dungeons-and-dragons-dashboard-for-azure-concord/main/tools/scriptable/azure-concord-widget.js';
const fm = FileManager.local();
const path = fm.joinPath(fm.documentsDirectory(), 'azure-concord-widget.cache.js');
try {
  const r = new Request(URL); r.timeoutInterval = 10;
  const code = await r.loadString();
  if (code && code.includes('Azure Concord')) fm.writeString(path, code);
} catch (e) { /* offline: use the copy from last time */ }
if (!fm.fileExists(path)) throw new Error('Couldn’t download the widget yet. Check your connection and run it again.');
const AsyncFunction = Object.getPrototypeOf(async function () {}).constructor;
await new AsyncFunction(fm.readString(path))();
