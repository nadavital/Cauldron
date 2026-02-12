const LABELS = ["title","ingredient","step","note","header","junk"];
const DEFAULT_DATASET_DIR = (window.APP_CONFIG && window.APP_CONFIG.defaultDatasetDir) ? String(window.APP_CONFIG.defaultDatasetDir) : '';
let lastLines = [];
let lastAssembledRecipe = null;
let lastSourcePreview = '';
let lastExtractMethod = '';
let lastSourceURL = '';
let lastSourceType = 'manual_edge';
let assembleDebounceId = null;
let activeView = 'lab';
let localCasesLoaded = false;
let datasetCasesLoaded = false;
let metricsHistoryLoaded = false;
let lastMetricsPayload = null;
const METRICS_HISTORY_PAGE_SIZE = 20;
let metricsHistoryPage = 1;
let metricsHistoryRuns = [];
let metricsHistoryMaxRuns = null;
const LINES_PAGE_SIZE = 50;
let linesPage = 1;
let lineEditsByIndex = {};

function nowId() {
  const d = new Date();
  const pad = (n) => String(n).padStart(2, '0');
  return `qa_${d.getFullYear()}_${pad(d.getMonth()+1)}_${pad(d.getDate())}_${pad(d.getHours())}${pad(d.getMinutes())}${pad(d.getSeconds())}`;
}

function log(msg) {
  // Keep logs in dev console only. UI log panel was removed.
  console.info('[ModelLab]', String(msg));
}

function setStatus(msg, tone='info') {
  const bar = document.getElementById('statusBar');
  if (!bar) return;
  bar.className = '';
  bar.style.display = '';
  if (!msg) {
    bar.style.display = 'none';
    bar.textContent = '';
    return;
  }
  bar.textContent = String(msg);
  bar.classList.add(tone);
}

function setMetricsStatus(msg, tone='info') {
  const bar = document.getElementById('metricsStatus');
  if (!bar) return;
  bar.className = '';
  bar.style.display = '';
  if (!msg) {
    bar.style.display = 'none';
    bar.textContent = '';
    return;
  }
  bar.textContent = String(msg);
  bar.classList.add(tone);
}

function updateResultsSummary(msg) {
  document.getElementById('resultsSummary').textContent = msg;
}

function updateQuickOutput(lines, sourcePreview) {
  const box = document.getElementById('quickOutput');
  if (!lines || !lines.length) {
    box.textContent = 'No output yet. Use the composer at the bottom to run a prediction.';
    return;
  }
  const preview = lines.slice(0, 6).map((row) => {
    const text = String(row.text || '').replace(/\s+/g, ' ').slice(0, 140);
    return `[${row.predicted_label}] ${text}`;
  });
  const hidden = lines.length > preview.length ? `\n... ${lines.length - preview.length} more lines in full table below.` : '';
  box.textContent = `Source: ${sourcePreview || 'input'}\n${preview.join('\n')}${hidden}`;
}

function escapeHtml(value) {
  return String(value || '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/\"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

function formatDateCompact(value) {
  if (!value) return '';
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return String(value);
  return date.toLocaleString();
}
