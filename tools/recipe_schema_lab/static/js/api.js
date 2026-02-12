async function refreshLocalCases() {
  try {
    const res = await fetch('/api/local_cases');
    const data = await res.json();
    if (!res.ok) throw new Error(data.error || 'failed to load local cases');
    renderLocalCases(Array.isArray(data.cases) ? data.cases : []);
    localCasesLoaded = true;
  } catch (err) {
    document.getElementById('localCasesSummary').textContent = 'Failed to load local cases.';
    document.getElementById('localCasesBody').innerHTML = '<tr><td colspan="5"><div class="emptyState">Error loading local cases.</div></td></tr>';
    setStatus('Local cases error: ' + err.message, 'error');
  }
}

async function refreshDatasetCases() {
  try {
    const datasetDir = document.getElementById('datasetBrowseDir').value.trim();
    const query = new URLSearchParams();
    if (datasetDir) query.set('dataset_dir', datasetDir);
    const res = await fetch('/api/dataset_cases?' + query.toString());
    const data = await res.json();
    if (!res.ok) throw new Error(data.error || 'failed to load dataset fixtures');
    if (data.dataset_dir) {
      document.getElementById('datasetBrowseDir').value = data.dataset_dir;
    }
    renderDatasetCases(Array.isArray(data.cases) ? data.cases : [], data.dataset_dir || datasetDir);
    datasetCasesLoaded = true;
  } catch (err) {
    document.getElementById('datasetCasesSummary').textContent = 'Failed to load dataset fixtures.';
    document.getElementById('datasetCasesBody').innerHTML = '<tr><td colspan="5"><div class="emptyState">Error loading dataset fixtures.</div></td></tr>';
    setStatus('Dataset fixtures error: ' + err.message, 'error');
  }
}

async function openLocalCase(caseId) {
  try {
    const query = new URLSearchParams({ id: caseId });
    const res = await fetch('/api/local_case?' + query.toString());
    const data = await res.json();
    if (!res.ok) throw new Error(data.error || 'failed to load local case');
    document.getElementById('localCaseDetail').textContent = JSON.stringify(
      {
        id: data.id,
        title: data.title,
        source_type: data.source_type,
        line_count: Array.isArray(data.lines) ? data.lines.length : 0,
        saved_at: formatDateCompact(data.saved_at),
        path: data.path,
      },
      null,
      2,
    );
    loadCaseIntoLab(data, `local:${data.id}`);
  } catch (err) {
    setStatus('Load local case error: ' + err.message, 'error');
  }
}

async function openDatasetCase(caseId) {
  try {
    const datasetDir = document.getElementById('datasetBrowseDir').value.trim();
    const query = new URLSearchParams({ id: caseId });
    if (datasetDir) query.set('dataset_dir', datasetDir);
    const res = await fetch('/api/dataset_case?' + query.toString());
    const data = await res.json();
    if (!res.ok) throw new Error(data.error || 'failed to load dataset case');
    document.getElementById('datasetCaseDetail').textContent = JSON.stringify(
      {
        id: data.id,
        title: data.title,
        source_type: data.source_type,
        line_count: Array.isArray(data.lines) ? data.lines.length : 0,
        dataset_dir: data.dataset_dir,
        document_path: data.document_path,
        lines_path: data.lines_path,
        target_recipe: data.target_recipe || null,
      },
      null,
      2,
    );
    loadCaseIntoLab(data, `dataset:${data.id}`);
  } catch (err) {
    setStatus('Load dataset case error: ' + err.message, 'error');
  }
}


async function refreshAppPreview() {
  try {
    if (!lastLines.length) {
      renderAppPreview(null);
      return;
    }
    const payload = collectAssemblePayload();
    const res = await fetch('/assemble_recipe', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(payload),
    });
    const data = await res.json();
    if (!res.ok) throw new Error(data.error || 'assemble failed');
    renderAppPreview(data.recipe || null);
  } catch (err) {
    log('Assemble preview error: ' + err.message);
  }
}

async function fileToDataURL(file) {
  return new Promise((resolve, reject) => {
    const r = new FileReader();
    r.onload = () => resolve(r.result);
    r.onerror = reject;
    r.readAsDataURL(file);
  });
}

async function predict() {
  const predictBtn = document.getElementById('predictBtn');
  try {
    const resolved = resolvePredictionInput();
    const mode = resolved.mode;
    const payload = { mode };
    if (mode === 'text') payload.text = resolved.text;
    if (mode === 'url') payload.url = resolved.url;
    if (mode === 'image') {
      payload.image_name = resolved.file.name;
      payload.image_data_url = await fileToDataURL(resolved.file);
    }

    predictBtn.disabled = true;
    setStatus('Running prediction...', 'info');
    log('Running prediction...');
    const res = await fetch('/predict', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(payload),
    });
    const data = await res.json();
    if (!res.ok) throw new Error(data.error || 'predict failed');

    renderLines(data.lines);
    lastSourcePreview = data.source_preview || mode;
    lastExtractMethod = data.extract_method || mode;
    lastSourceURL = mode === 'url' ? (resolved.url || '') : '';
    lastSourceType = mode === 'image' ? 'ocr' : (mode === 'url' ? 'url' : 'manual_edge');
    updateResultsSummary(`Source: ${data.source_preview || mode} | Extract: ${data.extract_method || mode} | Lines: ${data.lines.length}${data.truncated ? ' (truncated)' : ''}`);
    updateQuickOutput(data.lines, `${data.source_preview || mode} (${data.extract_method || mode})`);
    renderAppPreview(data.assembled_recipe || null);
    if (!document.getElementById('caseId').value.trim()) {
      syncCaseIdWithHoldoutMode();
    }
    if (resolved.imageIgnored) {
      setStatus('Prediction complete using text input. Attached image was ignored for this run.', 'success');
    } else {
      setStatus(`Prediction complete: ${data.lines.length} lines loaded.`, 'success');
    }
    updateComposerAttachmentUI();

    log(`Predicted ${data.lines.length} lines.${data.truncated ? ' (truncated to max lines)' : ''}`);
    document.getElementById('resultsCard').scrollIntoView({ behavior: 'smooth', block: 'start' });
  } catch (err) {
    setStatus('Predict error: ' + err.message, 'error');
    log('Predict error: ' + err.message);
  } finally {
    predictBtn.disabled = false;
  }
}

async function saveLocal() {
  const saveBtn = document.getElementById('saveBtn');
  try {
    saveBtn.disabled = true;
    setStatus('Saving local JSON...', 'info');
    const payload = collectPayload();
    const res = await fetch('/save_local', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(payload),
    });
    const data = await res.json();
    if (!res.ok) throw new Error(data.error || 'save failed');
    setStatus(`Saved local case JSON successfully (${data.id || payload.id}).`, 'success');
    log(`Saved local case file:\n${data.path}`);
    localCasesLoaded = false;
    refreshLocalCases();
    clearLabWorkspace();
  } catch (err) {
    setStatus('Save error: ' + err.message, 'error');
    log('Save error: ' + err.message);
  } finally {
    saveBtn.disabled = false;
  }
}

async function appendDataset() {
  const appendBtn = document.getElementById('appendBtn');
  try {
    appendBtn.disabled = true;
    setStatus('Appending to dataset...', 'info');
    const payload = collectPayload();
    payload.dataset_dir = document.getElementById('datasetDir').value.trim();

    const res = await fetch('/append_dataset', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(payload),
    });
    const data = await res.json();
    if (!res.ok) throw new Error(data.error || 'append failed');

    setStatus(`Appended to dataset successfully (${data.id || payload.id}).`, 'success');
    log(`Appended to dataset.\n${data.stdout || ''}${data.stderr ? '\n' + data.stderr : ''}`);
    document.getElementById('datasetBrowseDir').value = payload.dataset_dir;
    datasetCasesLoaded = false;
    refreshDatasetCases();
    clearLabWorkspace();
  } catch (err) {
    setStatus('Append error: ' + err.message, 'error');
    log('Append error: ' + err.message);
  } finally {
    appendBtn.disabled = false;
  }
}

async function runMetrics() {
  const metricsBtn = document.getElementById('metricsBtn');
  try {
    metricsBtn.disabled = true;
    setMetricsStatus('Running evaluation + regression metrics...', 'info');
    document.getElementById('metricsOutput').textContent = 'Running...';
    const res = await fetch('/run_metrics', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ dataset_dir: document.getElementById('datasetDir').value.trim() }),
    });
    const data = await res.json();
    lastMetricsPayload = data;
    renderMetricsDashboard(data);
    await refreshMetricsHistory();
    if (res.ok && data.ok) {
      setMetricsStatus('Metrics completed successfully.', 'success');
    } else {
      setMetricsStatus('Metrics completed with failures. Check scorecards and raw output.', 'error');
    }
  } catch (err) {
    setMetricsStatus('Metrics error: ' + err.message, 'error');
    document.getElementById('metricsOutput').textContent = 'Metrics error: ' + err.message;
  } finally {
    metricsBtn.disabled = false;
  }
}

async function retrainModel() {
  const retrainBtn = document.getElementById('retrainBtn');
  try {
    retrainBtn.disabled = true;
    setMetricsStatus('Retraining model + running evaluation/regression...', 'info');
    document.getElementById('metricsOutput').textContent = 'Running retrain pipeline...';
    const res = await fetch('/retrain_model', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ dataset_dir: document.getElementById('datasetDir').value.trim() }),
    });
    const data = await res.json();
    data.action = 'retrain';
    lastMetricsPayload = data;
    renderMetricsDashboard(data);
    await refreshMetricsHistory();
    if (res.ok && data.ok) {
      setMetricsStatus('Retrain completed and model reloaded in the lab.', 'success');
    } else {
      setMetricsStatus('Retrain completed with failures. Review details below.', 'error');
    }
  } catch (err) {
    setMetricsStatus('Retrain error: ' + err.message, 'error');
    document.getElementById('metricsOutput').textContent = 'Retrain error: ' + err.message;
  } finally {
    retrainBtn.disabled = false;
  }
}

async function refreshMetricsHistory() {
  try {
    const res = await fetch('/api/metrics_history');
    const data = await res.json();
    if (!res.ok) throw new Error(data.error || 'failed to load metrics history');
    const runs = Array.isArray(data.runs) ? data.runs : [];
    const maxRuns = Number(data.max_runs);
    renderMetricsHistory(runs, Number.isFinite(maxRuns) ? maxRuns : null);
    metricsHistoryLoaded = true;
    if (!lastMetricsPayload && runs.length > 0) {
      const latest = runs[0];
      renderMetricsDashboard(
        {
          action: latest.action,
          timestamp: latest.timestamp,
          summary: latest.summary || {},
        },
        { preserveRaw: true },
      );
    }
  } catch (err) {
    metricsHistoryLoaded = false;
    metricsHistoryRuns = [];
    metricsHistoryPage = 1;
    const pager = document.getElementById('metricsHistoryPager');
    if (pager) pager.classList.add('hidden');
    const summary = document.getElementById('metricsHistorySummary');
    if (summary) summary.textContent = 'Failed to load metrics history.';
    document.getElementById('metricsHistoryBody').innerHTML =
      '<tr><td colspan="8"><div class="emptyState">Failed to load metrics history.</div></td></tr>';
    renderMetricsTrend([]);
    setMetricsStatus('Metrics history error: ' + err.message, 'error');
  }
}
