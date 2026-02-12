function setActiveView(view) {
  activeView = view;
  document.querySelectorAll('.navBtn[data-view]').forEach((btn) => {
    btn.classList.toggle('active', btn.dataset.view === view);
  });
  document.querySelectorAll('.view').forEach((panel) => {
    const id = panel.id.replace('view-', '');
    panel.classList.toggle('hidden', id !== view);
  });

  if (view === 'local' && !localCasesLoaded) {
    refreshLocalCases();
  }
  if (view === 'dataset' && !datasetCasesLoaded) {
    refreshDatasetCases();
  }
  if (view === 'metrics' && !metricsHistoryLoaded) {
    refreshMetricsHistory();
  }
}

function updateLabVisibility() {
  const hasLines = Array.isArray(lastLines) && lastLines.length > 0;
  const empty = document.getElementById('labEmptyState');
  const workspace = document.getElementById('labWorkspace');
  if (empty) empty.classList.toggle('hidden', hasLines);
  if (workspace) workspace.classList.toggle('hidden', !hasLines);
}

const HOLDOUT_CASE_PREFIX = 'holdout_';
const SAVE_KIND_TRAIN = 'train';
const SAVE_KIND_HOLDOUT = 'holdout';
const SAVE_KIND_OCR_FAILURE = 'ocr_failure';
const SAVE_KIND_PARSE_FAILURE = 'parse_failure';
const SAVE_KIND_VALUES = new Set([
  SAVE_KIND_TRAIN,
  SAVE_KIND_HOLDOUT,
  SAVE_KIND_OCR_FAILURE,
  SAVE_KIND_PARSE_FAILURE,
]);

function stripHoldoutPrefix(caseId) {
  const raw = String(caseId || '').trim();
  if (!raw.startsWith(HOLDOUT_CASE_PREFIX)) return raw;
  return raw.slice(HOLDOUT_CASE_PREFIX.length).trim();
}

function selectedSaveKind() {
  const select = document.getElementById('composerSaveKind');
  const value = String((select && select.value) || SAVE_KIND_TRAIN).trim().toLowerCase();
  return SAVE_KIND_VALUES.has(value) ? value : SAVE_KIND_TRAIN;
}

function saveKindRequiresHoldout(kind = selectedSaveKind()) {
  return kind === SAVE_KIND_HOLDOUT || kind === SAVE_KIND_OCR_FAILURE || kind === SAVE_KIND_PARSE_FAILURE;
}

function sourceTypeForSaveKind(kind, fallbackSourceType) {
  if (kind === SAVE_KIND_OCR_FAILURE) return SAVE_KIND_OCR_FAILURE;
  if (kind === SAVE_KIND_PARSE_FAILURE) return SAVE_KIND_PARSE_FAILURE;
  const base = String(fallbackSourceType || 'manual_edge').trim();
  return base || 'manual_edge';
}

function inferSaveKindFromCase(caseId, sourceType) {
  const source = String(sourceType || '').trim().toLowerCase();
  if (source === SAVE_KIND_OCR_FAILURE) return SAVE_KIND_OCR_FAILURE;
  if (source === SAVE_KIND_PARSE_FAILURE) return SAVE_KIND_PARSE_FAILURE;
  if (String(caseId || '').startsWith(HOLDOUT_CASE_PREFIX)) return SAVE_KIND_HOLDOUT;
  return SAVE_KIND_TRAIN;
}

function normalizeSaveKindValue(raw) {
  const value = String(raw || '').trim().toLowerCase();
  return SAVE_KIND_VALUES.has(value) ? value : '';
}

function applySaveKindConstraints() {
  const holdoutCheck = document.getElementById('composerHoldoutCheck');
  const hint = document.getElementById('composerSaveKindHint');
  if (!holdoutCheck) return;
  const kind = selectedSaveKind();
  const forcedHoldout = saveKindRequiresHoldout(kind);
  const wasForced = holdoutCheck.disabled;
  if (forcedHoldout) holdoutCheck.checked = true;
  if (!forcedHoldout && wasForced) holdoutCheck.checked = false;
  holdoutCheck.disabled = forcedHoldout;
  if (!hint) return;
  if (kind === SAVE_KIND_OCR_FAILURE) {
    hint.textContent = 'OCR failure examples are auto-saved as holdout and excluded from training.';
    return;
  }
  if (kind === SAVE_KIND_PARSE_FAILURE) {
    hint.textContent = 'Parse failure examples are auto-saved as holdout and excluded from training.';
    return;
  }
  if (kind === SAVE_KIND_HOLDOUT) {
    hint.textContent = 'Holdout examples are excluded from training and only used for evaluation.';
    return;
  }
  hint.textContent = '';
}

function setSaveKind(kind) {
  const select = document.getElementById('composerSaveKind');
  const normalized = SAVE_KIND_VALUES.has(kind) ? kind : SAVE_KIND_TRAIN;
  if (select) select.value = normalized;
  applySaveKindConstraints();
}

function isComposerHoldoutEnabled() {
  const checkbox = document.getElementById('composerHoldoutCheck');
  return Boolean((checkbox && checkbox.checked) || saveKindRequiresHoldout());
}

function normalizeCaseIdForHoldout(caseId, holdoutEnabled) {
  const baseId = stripHoldoutPrefix(caseId) || nowId();
  return holdoutEnabled ? `${HOLDOUT_CASE_PREFIX}${baseId}` : baseId;
}

function syncCaseIdWithHoldoutMode() {
  const caseIdInput = document.getElementById('caseId');
  if (!caseIdInput) return nowId();
  const normalized = normalizeCaseIdForHoldout(caseIdInput.value, isComposerHoldoutEnabled());
  caseIdInput.value = normalized;
  return normalized;
}

function normalizeCaseLabels(lines, labels) {
  const fixedLines = Array.isArray(lines) ? lines.map((item) => String(item || '')) : [];
  const fixedLabels = Array.isArray(labels) ? labels.map((label) => {
    const value = String(label || '').trim().toLowerCase();
    return LABELS.includes(value) ? value : 'junk';
  }) : [];
  while (fixedLabels.length < fixedLines.length) fixedLabels.push('junk');
  return { lines: fixedLines, labels: fixedLabels.slice(0, fixedLines.length) };
}

const INGREDIENT_HEADER_PREFIXES = new Set([
  'ingredient',
  'ingredients',
  'for the ingredients',
  "what you'll need",
]);

const STEP_HEADER_PREFIXES = new Set([
  'instruction',
  'instructions',
  'direction',
  'directions',
  'method',
  'preparation',
  'steps',
]);

const NOTE_HEADER_PREFIXES = new Set([
  'note',
  'notes',
  'tip',
  'tips',
  'variation',
  'variations',
  "chef's note",
  'storage',
  'substitution',
  'substitutions',
]);

function headerKey(text) {
  let lowered = String(text || '').trim().toLowerCase();
  lowered = lowered.replace(/^[\W_]+|[\W_]+$/g, '');
  if (lowered.endsWith(':')) lowered = lowered.slice(0, -1).trim();
  return lowered;
}

function headerSectionType(text) {
  const key = headerKey(text);
  if (INGREDIENT_HEADER_PREFIXES.has(key)) return 'ingredients';
  if (STEP_HEADER_PREFIXES.has(key)) return 'steps';
  if (NOTE_HEADER_PREFIXES.has(key)) return 'notes';
  return null;
}

function looksLikeSubsectionHeader(text) {
  const trimmed = String(text || '').trim();
  if (!trimmed.endsWith(':')) return false;
  const words = trimmed.slice(0, -1).trim().split(/\s+/).filter(Boolean);
  if (!(words.length > 0 && words.length <= 7)) return false;
  if (trimmed.length > 90) return false;
  if (/\d/.test(trimmed)) return false;
  return true;
}

function deriveLineSections(lines) {
  const byIndex = {};
  let currentSection = 'unknown';
  let currentIngredientSection = null;
  let currentStepSection = null;

  lines.forEach((line) => {
    const label = String(line.label || '').trim().toLowerCase();
    const text = String(line.text || '').trim();
    const index = Number(line.index);
    if (!Number.isFinite(index)) return;

    let derived = '';
    if (label === 'header') {
      const sectionType = headerSectionType(text);
      if (sectionType === 'ingredients') {
        currentSection = 'ingredients';
        currentIngredientSection = null;
        derived = 'Ingredients';
      } else if (sectionType === 'steps') {
        currentSection = 'steps';
        currentStepSection = null;
        derived = 'Instructions';
      } else if (sectionType === 'notes') {
        currentSection = 'notes';
        derived = 'Notes';
      } else if (looksLikeSubsectionHeader(text)) {
        const subsection = text.replace(/:\s*$/, '').trim();
        if (currentSection === 'steps') {
          currentStepSection = subsection;
          derived = `Instructions > ${subsection}`;
        } else if (currentSection === 'notes') {
          derived = 'Notes';
        } else {
          currentSection = 'ingredients';
          currentIngredientSection = subsection;
          derived = `Ingredients > ${subsection}`;
        }
      }
    } else if (label === 'ingredient') {
      currentSection = 'ingredients';
      const sectionName = currentIngredientSection || 'Main';
      derived = sectionName === 'Main' ? 'Ingredients > Main' : `Ingredients > ${sectionName}`;
    } else if (label === 'step') {
      currentSection = 'steps';
      const sectionName = currentStepSection || 'Main';
      derived = sectionName === 'Main' ? 'Instructions > Main' : `Instructions > ${sectionName}`;
    } else if (label === 'note') {
      currentSection = 'notes';
      derived = 'Notes';
    }

    byIndex[index] = derived;
  });

  return byIndex;
}

function deriveSectionsFromAssembledRecipe(lines, recipe) {
  if (!recipe || !Array.isArray(lines)) return {};

  const mapped = {};

  const ingredientLines = lines.filter((line) => String(line.label || '').toLowerCase() === 'ingredient');
  const assembledIngredients = Array.isArray(recipe.ingredients) ? recipe.ingredients : [];
  if (ingredientLines.length && assembledIngredients.length) {
    const count = Math.min(ingredientLines.length, assembledIngredients.length);
    for (let i = 0; i < count; i += 1) {
      const lineIndex = Number(ingredientLines[i].index);
      const sectionName = assembledIngredients[i] && assembledIngredients[i].section ? String(assembledIngredients[i].section) : 'Main';
      mapped[lineIndex] = sectionName === 'Main' ? 'Ingredients > Main' : `Ingredients > ${sectionName}`;
    }
  }

  const stepLines = lines.filter((line) => String(line.label || '').toLowerCase() === 'step');
  const assembledSteps = Array.isArray(recipe.steps) ? recipe.steps : [];
  if (stepLines.length && assembledSteps.length && stepLines.length === assembledSteps.length) {
    for (let i = 0; i < stepLines.length; i += 1) {
      const lineIndex = Number(stepLines[i].index);
      const sectionName = assembledSteps[i] && assembledSteps[i].section ? String(assembledSteps[i].section) : 'Main';
      mapped[lineIndex] = sectionName === 'Main' ? 'Instructions > Main' : `Instructions > ${sectionName}`;
    }
  }

  return mapped;
}

function updateDerivedSectionsInTable(recipe = null) {
  const lines = currentLabeledLines();
  const sectionsByIndex = deriveLineSections(lines);
  const assembledSectionsByIndex = deriveSectionsFromAssembledRecipe(lines, recipe || lastAssembledRecipe);
  Object.keys(assembledSectionsByIndex).forEach((key) => {
    sectionsByIndex[key] = assembledSectionsByIndex[key];
  });
  document.querySelectorAll('#linesTable td[data-derived-section-index]').forEach((cell) => {
    const index = Number(cell.dataset.derivedSectionIndex);
    cell.textContent = sectionsByIndex[index] || '';
  });
}

function loadCaseIntoLab(caseData, sourcePreview = 'saved_case') {
  const normalized = normalizeCaseLabels(caseData.lines, caseData.labels);
  const rows = normalized.lines.map((line, index) => {
    const label = normalized.labels[index] || 'junk';
    return {
      index,
      text: line,
      predicted_label: label,
      label,
      confidence: 'manual',
    };
  });

  renderLines(rows);
  updateResultsSummary(`Loaded case "${caseData.id}" with ${rows.length} labeled lines.`);
  updateQuickOutput(rows, sourcePreview);
  lastSourceURL = String(caseData.source_url || (caseData.assembled_recipe && caseData.assembled_recipe.sourceURL) || '').trim();
  lastSourceType = String(caseData.source_type || 'manual_edge');

  const loadedCaseId = caseData.id || nowId();
  document.getElementById('caseId').value = loadedCaseId;
  const holdoutCheck = document.getElementById('composerHoldoutCheck');
  if (holdoutCheck) {
    holdoutCheck.checked = String(loadedCaseId).startsWith(HOLDOUT_CASE_PREFIX);
  }
  const explicitSaveKind = normalizeSaveKindValue(caseData.save_kind);
  setSaveKind(explicitSaveKind || inferSaveKindFromCase(loadedCaseId, lastSourceType));
  syncCaseIdWithHoldoutMode();
  if (caseData.dataset_dir) {
    document.getElementById('datasetDir').value = caseData.dataset_dir;
    document.getElementById('datasetBrowseDir').value = caseData.dataset_dir;
  }

  if (caseData.assembled_recipe) {
    renderAppPreview(caseData.assembled_recipe);
  } else {
    renderAppPreview(null);
    refreshAppPreview();
  }
  document.getElementById('composerInput').value = lastSourceURL;
  clearComposerImage();
  updateComposerAttachmentUI();
  updateLabVisibility();

  setActiveView('lab');
  setStatus(`Loaded case "${caseData.id}" into the lab editor.`, 'success');
  document.getElementById('resultsCard').scrollIntoView({ behavior: 'smooth', block: 'start' });
}

function renderLocalCases(cases) {
  const body = document.getElementById('localCasesBody');
  const summary = document.getElementById('localCasesSummary');
  body.innerHTML = '';
  summary.textContent = `${cases.length} local case${cases.length === 1 ? '' : 's'} found.`;

  if (!cases.length) {
    body.innerHTML = '<tr><td colspan="5"><div class="emptyState">No local cases yet. Save one from the Lab tab.</div></td></tr>';
    return;
  }

  for (const item of cases) {
    const tr = document.createElement('tr');
    tr.innerHTML = `
      <td class="mono">${escapeHtml(item.id)}</td>
      <td>${escapeHtml(item.title || '')}</td>
      <td>${escapeHtml(item.source_type || '')}</td>
      <td class="tightCell">${Number(item.line_count || 0)}</td>
      <td class="tightCell"><button class="secondary smallBtn" data-local-id="${escapeHtml(item.id)}">Load</button></td>
    `;
    body.appendChild(tr);
  }
}

function renderDatasetCases(cases, datasetDir) {
  const body = document.getElementById('datasetCasesBody');
  const summary = document.getElementById('datasetCasesSummary');
  body.innerHTML = '';
  summary.textContent = `${cases.length} dataset fixture${cases.length === 1 ? '' : 's'} in ${datasetDir}.`;

  if (!cases.length) {
    body.innerHTML = '<tr><td colspan="5"><div class="emptyState">No fixtures found for this dataset directory.</div></td></tr>';
    return;
  }

  for (const item of cases) {
    const tr = document.createElement('tr');
    tr.innerHTML = `
      <td class="mono">${escapeHtml(item.id)}</td>
      <td>${escapeHtml(item.title || '')}</td>
      <td>${escapeHtml(item.source_type || '')}</td>
      <td class="tightCell">${Number(item.line_count || 0)}</td>
      <td class="tightCell"><button class="secondary smallBtn" data-dataset-id="${escapeHtml(item.id)}">Load</button></td>
    `;
    body.appendChild(tr);
  }
}

function syncDatasetDirFromLab() {
  const value = document.getElementById('datasetDir').value.trim();
  document.getElementById('datasetBrowseDir').value = value;
  setStatus('Dataset browse dir synced from Settings.', 'info');
}

function formatMetric(value, digits = 3) {
  const num = Number(value);
  if (!Number.isFinite(num)) return '-';
  return num.toFixed(digits);
}

function formatMetricPercent(value, digits = 2) {
  const num = Number(value);
  if (!Number.isFinite(num)) return '-';
  return `${(num * 100).toFixed(digits)}%`;
}

function setMetricCard(id, valueText, pass = null, hint = '') {
  const valueEl = document.getElementById(id);
  if (!valueEl) return;
  valueEl.textContent = valueText;
  valueEl.classList.remove('good', 'bad');
  if (pass === true) valueEl.classList.add('good');
  if (pass === false) valueEl.classList.add('bad');

  const hintEl = document.getElementById(`${id}Hint`);
  if (!hintEl) return;
  hintEl.textContent = hint;
}

function renderRunDetails(payload) {
  const body = document.getElementById('metricsRunDetailsBody');
  if (!body) return;
  body.innerHTML = '';
  const summary = payload && payload.summary ? payload.summary : {};
  const fixedHoldout = summary && summary.fixed_holdout ? summary.fixed_holdout : {};
  const noteSupport = Number(summary.note_support);
  const noteSupportText = Number.isFinite(noteSupport) ? formatNumberCompact(noteSupport) : '-';
  const presentLabelCount = Number(summary.present_label_count);
  const presentLabelCountText = Number.isFinite(presentLabelCount) ? formatNumberCompact(presentLabelCount) : '-';

  const detailRows = [
    ['Action', payload && payload.action ? String(payload.action) : 'metrics'],
    ['Timestamp', payload && payload.timestamp ? formatDateCompact(payload.timestamp) : '-'],
    ['Dataset Dir', payload && payload.dataset_dir ? String(payload.dataset_dir) : '-'],
    ['Macro F1 (Support-Aware)', formatMetric(summary.macro_f1)],
    ['Macro F1 (Reported)', formatMetric(summary.macro_f1_reported)],
    ['Present Labels In Eval', presentLabelCountText],
    ['Note Support', noteSupportText],
    ['Model Artifact', payload && payload.model_path ? String(payload.model_path) : '-'],
    ['Bundled Artifact', payload && payload.bundled_model_out ? String(payload.bundled_model_out) : '-'],
    ['Validation RC', payload && payload.validate_rc != null ? String(payload.validate_rc) : 'n/a'],
    ['Train RC', payload && payload.train_rc != null ? String(payload.train_rc) : 'n/a'],
    ['Evaluate RC', payload && payload.evaluate_rc != null ? String(payload.evaluate_rc) : 'n/a'],
    ['Fixed Holdout Eval RC', payload && payload.fixed_holdout_evaluate_rc != null ? String(payload.fixed_holdout_evaluate_rc) : 'n/a'],
    ['Regression RC', payload && payload.regression_rc != null ? String(payload.regression_rc) : 'n/a'],
    ['Fixed Holdout', fixedHoldout && fixedHoldout.available ? 'Enabled (holdout_*)' : 'Not found'],
    ['Fixed Holdout Macro F1', fixedHoldout && fixedHoldout.available ? formatMetric(fixedHoldout.macro_f1) : '-'],
    ['Fixed Holdout Macro F1 (Reported)', fixedHoldout && fixedHoldout.available ? formatMetric(fixedHoldout.macro_f1_reported) : '-'],
    ['Export RC', payload && payload.export_rc != null ? String(payload.export_rc) : 'n/a'],
    ['Predictor Reloaded', payload && payload.reloaded != null ? (payload.reloaded ? 'Yes' : 'No') : 'n/a'],
    ['Rolled Back', payload && payload.rolled_back != null ? (payload.rolled_back ? 'Yes' : 'No') : 'n/a'],
    ['Rollback Error', payload && payload.rollback_error ? String(payload.rollback_error) : '-'],
  ];

  detailRows.forEach(([key, value]) => {
    const tr = document.createElement('tr');
    tr.innerHTML = `<td class="detailKey">${escapeHtml(key)}</td><td class="detailValue mono">${escapeHtml(value)}</td>`;
    body.appendChild(tr);
  });
}

function renderPerClassMetrics(payload) {
  const body = document.getElementById('metricsPerClassBody');
  if (!body) return;
  body.innerHTML = '';

  const perClass = payload && payload.metrics && payload.metrics.per_class ? payload.metrics.per_class : null;
  if (!perClass || typeof perClass !== 'object') {
    body.innerHTML = '<tr><td colspan="5"><div class="emptyState">No per-class metrics available for this run.</div></td></tr>';
    return;
  }

  const labels = ['title', 'ingredient', 'step', 'note', 'header', 'junk'];
  labels.forEach((label) => {
    const row = perClass[label] || {};
    const tr = document.createElement('tr');
    tr.innerHTML = `
      <td>${escapeHtml(label)}</td>
      <td>${escapeHtml(formatMetric(row.precision))}</td>
      <td>${escapeHtml(formatMetric(row.recall))}</td>
      <td>${escapeHtml(formatMetric(row.f1))}</td>
      <td>${escapeHtml(formatNumberCompact(row.support == null ? '-' : row.support))}</td>
    `;
    body.appendChild(tr);
  });
}

function renderMetricsDashboard(payload, opts = {}) {
  const preserveRaw = Boolean(opts.preserveRaw);
  const summary = payload && payload.summary ? payload.summary : {};
  const thresholds = summary && summary.thresholds ? summary.thresholds : {};
  const fixedHoldout = summary && summary.fixed_holdout ? summary.fixed_holdout : {};
  const fixedHoldoutThresholds = fixedHoldout && fixedHoldout.thresholds ? fixedHoldout.thresholds : {};
  const overallPass = Boolean(thresholds.overall);
  const hasData = summary && Object.keys(summary).length > 0;
  const noteSupport = Number(summary.note_support);
  const noteSupportKnown = Number.isFinite(noteSupport);
  const noteApplicable = summary.note_recall_applicable !== false;

  const overall = document.getElementById('metricOverall');
  const overallHint = document.getElementById('metricOverallHint');
  overall.classList.remove('good', 'bad');
  if (!hasData) {
    overall.textContent = 'No run yet';
    overallHint.textContent = 'Run metrics to populate scorecards.';
  } else {
    overall.textContent = overallPass ? 'PASS' : 'Needs Work';
    overall.classList.add(overallPass ? 'good' : 'bad');
    const action = payload && payload.action ? String(payload.action) : 'metrics';
    const when = payload && payload.timestamp ? formatDateCompact(payload.timestamp) : '';
    overallHint.textContent = `${action} run ${when ? `on ${when}` : ''}`.trim();
  }

  const macroHintParts = ['Target: >= 0.88 (support-aware)'];
  if (summary.prediction_count) macroHintParts.push(`${summary.prediction_count} lines`);
  if (summary.macro_f1_reported != null) macroHintParts.push(`reported=${formatMetric(summary.macro_f1_reported)}`);
  setMetricCard(
    'metricMacroF1',
    formatMetric(summary.macro_f1),
    thresholds.macro_f1,
    macroHintParts.join(' | '),
  );
  const noteHintParts = ['Target: >= 0.85'];
  if (!noteApplicable) {
    noteHintParts.push('N/A (note support = 0)');
  } else if (noteSupportKnown) {
    noteHintParts.push(`support=${formatNumberCompact(noteSupport)}`);
  }
  setMetricCard(
    'metricNoteRecall',
    noteApplicable ? formatMetric(summary.note_recall) : 'N/A',
    noteApplicable ? thresholds.note_recall : null,
    noteHintParts.join(' | '),
  );
  setMetricCard(
    'metricConfusion',
    formatMetricPercent(summary.ingredient_step_confusion_rate),
    thresholds.ingredient_step_confusion,
    'Target: <= 8.00%',
  );
  if (fixedHoldout && fixedHoldout.available) {
    setMetricCard(
      'metricFixedHoldoutF1',
      formatMetric(fixedHoldout.macro_f1),
      fixedHoldoutThresholds.macro_f1,
      `Target: >= 0.88 (support-aware)${fixedHoldout.prediction_count ? ` | ${fixedHoldout.prediction_count} lines` : ''}`,
    );
  } else {
    setMetricCard('metricFixedHoldoutF1', '-', null, 'No holdout_* fixtures found in dataset.');
  }
  setMetricCard('metricRegressionExact', formatMetricPercent(summary.regression_exact_match_rate), null, 'Higher is better');
  setMetricCard(
    'metricRegressionLeak',
    formatMetricPercent(summary.regression_note_leakage_rate),
    thresholds.regression_note_leakage,
    'Target: <= 5.00%',
  );
  setMetricCard(
    'metricRegressionSwap',
    formatMetricPercent(summary.regression_swap_rate),
    thresholds.regression_swap,
    'Target: <= 8.00%',
  );

  renderRunDetails(payload || {});
  renderPerClassMetrics(payload || {});

  if (!preserveRaw) {
    const parts = [];
    if (payload && payload.validate) parts.push(`Validation:\n${payload.validate}`);
    if (payload && payload.train) parts.push(`Training:\n${payload.train}`);
    if (payload && payload.evaluate) parts.push(`Evaluation:\n${payload.evaluate}`);
    if (payload && payload.fixed_holdout_evaluate) parts.push(`Fixed Holdout Evaluation:\n${payload.fixed_holdout_evaluate}`);
    if (payload && payload.regression) parts.push(`Regression:\n${payload.regression}`);
    if (payload && payload.export) parts.push(`Export:\n${payload.export}`);
    const raw = parts.join('\n\n').trim();
    document.getElementById('metricsOutput').textContent = raw || 'No raw output available.';
  }
}

function renderMetricsTrend(runs) {
  const svg = document.getElementById('metricsTrendChart');
  const empty = document.getElementById('metricsTrendEmpty');
  const summary = document.getElementById('metricsTrendSummary');
  if (!svg || !empty || !summary) return;

  svg.innerHTML = '';
  if (!Array.isArray(runs) || runs.length < 2) {
    empty.classList.remove('hidden');
    summary.textContent = 'Need at least 2 runs to generate trends.';
    return;
  }

  const ordered = [...runs].reverse();
  const series = {
    macro: ordered.map((run) => Number(run && run.summary ? run.summary.macro_f1 : NaN)),
    holdout: ordered.map((run) => {
      const fixed = run && run.summary && run.summary.fixed_holdout ? run.summary.fixed_holdout : null;
      return Number(fixed && fixed.available ? fixed.macro_f1 : NaN);
    }),
    confusion: ordered.map((run) => Number(run && run.summary ? run.summary.ingredient_step_confusion_rate : NaN)),
  };

  const hasEnoughPoints = Object.values(series).some((values) => values.filter((v) => Number.isFinite(v)).length >= 2);
  if (!hasEnoughPoints) {
    empty.classList.remove('hidden');
    summary.textContent = 'Need at least 2 valid points in a metric series to draw trend lines.';
    return;
  }

  empty.classList.add('hidden');
  const firstTime = ordered[0] && ordered[0].timestamp ? formatDateCompact(ordered[0].timestamp) : '';
  const lastTime = ordered[ordered.length - 1] && ordered[ordered.length - 1].timestamp ? formatDateCompact(ordered[ordered.length - 1].timestamp) : '';
  summary.textContent = `Oldest to newest: ${firstTime || '-'} -> ${lastTime || '-'}`;

  const NS = 'http://www.w3.org/2000/svg';
  const width = 760;
  const height = 220;
  const margin = { left: 44, right: 14, top: 12, bottom: 28 };
  const chartWidth = width - margin.left - margin.right;
  const chartHeight = height - margin.top - margin.bottom;
  const maxIndex = Math.max(1, ordered.length - 1);
  const xAt = (idx) => margin.left + (idx / maxIndex) * chartWidth;
  const clamp01 = (value) => Math.max(0, Math.min(1, value));
  const yAt = (value) => margin.top + (1 - clamp01(value)) * chartHeight;

  const makeLine = (x1, y1, x2, y2, stroke, widthPx = 1) => {
    const line = document.createElementNS(NS, 'line');
    line.setAttribute('x1', String(x1));
    line.setAttribute('y1', String(y1));
    line.setAttribute('x2', String(x2));
    line.setAttribute('y2', String(y2));
    line.setAttribute('stroke', stroke);
    line.setAttribute('stroke-width', String(widthPx));
    return line;
  };

  const makeText = (x, y, text, fill = '#6b7280', anchor = 'middle') => {
    const el = document.createElementNS(NS, 'text');
    el.setAttribute('x', String(x));
    el.setAttribute('y', String(y));
    el.setAttribute('fill', fill);
    el.setAttribute('font-size', '10');
    el.setAttribute('text-anchor', anchor);
    el.textContent = text;
    return el;
  };

  const yTicks = [0, 0.2, 0.4, 0.6, 0.8, 1];
  yTicks.forEach((tick) => {
    const y = yAt(tick);
    svg.appendChild(makeLine(margin.left, y, width - margin.right, y, '#eef0f3', 1));
    svg.appendChild(makeText(margin.left - 6, y + 3, String(tick.toFixed(1)), '#9ca3af', 'end'));
  });

  svg.appendChild(makeLine(margin.left, margin.top, margin.left, height - margin.bottom, '#d1d5db', 1));
  svg.appendChild(makeLine(margin.left, height - margin.bottom, width - margin.right, height - margin.bottom, '#d1d5db', 1));

  const drawSeries = (values, color) => {
    const points = [];
    values.forEach((value, idx) => {
      if (!Number.isFinite(value)) return;
      points.push({ x: xAt(idx), y: yAt(value) });
    });
    if (points.length < 2) return;

    const path = document.createElementNS(NS, 'path');
    const d = points.map((p, idx) => `${idx === 0 ? 'M' : 'L'} ${p.x.toFixed(2)} ${p.y.toFixed(2)}`).join(' ');
    path.setAttribute('d', d);
    path.setAttribute('fill', 'none');
    path.setAttribute('stroke', color);
    path.setAttribute('stroke-width', '2');
    svg.appendChild(path);

    points.forEach((p) => {
      const dot = document.createElementNS(NS, 'circle');
      dot.setAttribute('cx', p.x.toFixed(2));
      dot.setAttribute('cy', p.y.toFixed(2));
      dot.setAttribute('r', '2.5');
      dot.setAttribute('fill', color);
      svg.appendChild(dot);
    });
  };

  drawSeries(series.macro, '#2563eb');
  drawSeries(series.holdout, '#059669');
  drawSeries(series.confusion, '#d97706');

  svg.appendChild(makeText(margin.left, height - 8, 'Oldest', '#9ca3af', 'start'));
  svg.appendChild(makeText(width - margin.right, height - 8, 'Newest', '#9ca3af', 'end'));
}

function renderMetricsHistory(runs, maxRuns = null) {
  metricsHistoryRuns = Array.isArray(runs) ? runs : [];
  metricsHistoryMaxRuns = Number.isFinite(maxRuns) ? maxRuns : null;
  metricsHistoryPage = 1;
  renderMetricsHistoryPage();
  renderMetricsTrend(metricsHistoryRuns);
}

function clampMetricsHistoryPage() {
  const totalPages = Math.max(1, Math.ceil(metricsHistoryRuns.length / METRICS_HISTORY_PAGE_SIZE));
  metricsHistoryPage = Math.min(Math.max(1, metricsHistoryPage), totalPages);
  return totalPages;
}

function pagedMetricsHistoryRuns() {
  clampMetricsHistoryPage();
  if (!metricsHistoryRuns.length) return [];
  const start = (metricsHistoryPage - 1) * METRICS_HISTORY_PAGE_SIZE;
  const end = start + METRICS_HISTORY_PAGE_SIZE;
  return metricsHistoryRuns.slice(start, end);
}

function updateMetricsHistoryPagerUI() {
  const pager = document.getElementById('metricsHistoryPager');
  const prevBtn = document.getElementById('metricsHistoryPrevBtn');
  const nextBtn = document.getElementById('metricsHistoryNextBtn');
  const summary = document.getElementById('metricsHistoryPageSummary');
  if (!pager || !prevBtn || !nextBtn || !summary) return;

  const total = metricsHistoryRuns.length;
  const totalPages = clampMetricsHistoryPage();
  if (total <= METRICS_HISTORY_PAGE_SIZE) {
    pager.classList.add('hidden');
    summary.textContent = `Rows ${total ? 1 : 0}-${total} of ${total}`;
    return;
  }

  pager.classList.remove('hidden');
  const start = (metricsHistoryPage - 1) * METRICS_HISTORY_PAGE_SIZE + 1;
  const end = Math.min(metricsHistoryPage * METRICS_HISTORY_PAGE_SIZE, total);
  summary.textContent = `Rows ${start}-${end} of ${total} (Page ${metricsHistoryPage}/${totalPages})`;
  prevBtn.disabled = metricsHistoryPage <= 1;
  nextBtn.disabled = metricsHistoryPage >= totalPages;
}

function renderMetricsHistoryPage() {
  const body = document.getElementById('metricsHistoryBody');
  const summary = document.getElementById('metricsHistorySummary');
  body.innerHTML = '';

  if (!Array.isArray(metricsHistoryRuns) || !metricsHistoryRuns.length) {
    body.innerHTML = '<tr><td colspan="8"><div class="emptyState">No history yet. Run metrics or retrain to create a baseline.</div></td></tr>';
    if (summary) {
      summary.textContent = metricsHistoryMaxRuns != null
        ? `No history yet. Retention cap is ${metricsHistoryMaxRuns} runs.`
        : 'No history yet.';
    }
    updateMetricsHistoryPagerUI();
    return;
  }

  if (summary) {
    const start = (metricsHistoryPage - 1) * METRICS_HISTORY_PAGE_SIZE + 1;
    const end = Math.min(metricsHistoryPage * METRICS_HISTORY_PAGE_SIZE, metricsHistoryRuns.length);
    summary.textContent = metricsHistoryMaxRuns != null
      ? `Showing ${start}-${end} of ${metricsHistoryRuns.length} most recent run(s). History retention cap: ${metricsHistoryMaxRuns}.`
      : `Showing ${start}-${end} of ${metricsHistoryRuns.length} most recent run(s).`;
  }

  const runs = pagedMetricsHistoryRuns();
  runs.forEach((run) => {
    const runSummary = run && run.summary ? run.summary : {};
    const fixedHoldout = runSummary && runSummary.fixed_holdout ? runSummary.fixed_holdout : {};
    const tr = document.createElement('tr');
    const statusClass = run && run.success ? 'good' : 'bad';
    const statusText = run && run.success ? 'PASS' : 'FAIL';
    tr.innerHTML = `
      <td>${escapeHtml(formatDateCompact(run.timestamp || ''))}</td>
      <td>${escapeHtml(String(run.action || 'metrics'))}</td>
      <td><span class="statusPill ${statusClass}">${statusText}</span></td>
      <td>${escapeHtml(formatMetric(runSummary.macro_f1))}</td>
      <td>${escapeHtml(fixedHoldout && fixedHoldout.available ? formatMetric(fixedHoldout.macro_f1) : '-')}</td>
      <td>${escapeHtml(formatMetric(runSummary.note_recall))}</td>
      <td>${escapeHtml(formatMetricPercent(runSummary.ingredient_step_confusion_rate))}</td>
      <td>${escapeHtml(formatMetricPercent(runSummary.regression_exact_match_rate))}</td>
    `;
    body.appendChild(tr);
  });

  updateMetricsHistoryPagerUI();
}

function goToPrevMetricsHistoryPage() {
  metricsHistoryPage -= 1;
  renderMetricsHistoryPage();
}

function goToNextMetricsHistoryPage() {
  metricsHistoryPage += 1;
  renderMetricsHistoryPage();
}

async function copyTextToClipboard(text) {
  const fallbackCopy = () => {
    const area = document.createElement('textarea');
    area.value = text;
    area.setAttribute('readonly', 'readonly');
    area.style.position = 'fixed';
    area.style.left = '-9999px';
    document.body.appendChild(area);
    area.select();
    const ok = document.execCommand('copy');
    document.body.removeChild(area);
    return ok;
  };

  try {
    if (navigator.clipboard && navigator.clipboard.writeText) {
      await navigator.clipboard.writeText(text);
      return true;
    }
    return fallbackCopy();
  } catch (_) {
    return fallbackCopy();
  }
}

async function copyMetricsRawOutput() {
  const output = document.getElementById('metricsOutput');
  const text = output ? String(output.textContent || '') : '';
  if (!text.trim()) {
    setMetricsStatus('No raw output to copy yet.', 'info');
    return;
  }

  const ok = await copyTextToClipboard(text);
  setMetricsStatus(ok ? 'Raw output copied to clipboard.' : 'Copy failed.', ok ? 'success' : 'error');
}

async function copyAppRecipeJsonOutput() {
  if (!lastAssembledRecipe) {
    setStatus('No app preview JSON to copy yet.', 'info');
    return;
  }
  const text = JSON.stringify(lastAssembledRecipe, null, 2);
  const ok = await copyTextToClipboard(text);
  setStatus(ok ? 'App preview JSON copied to clipboard.' : 'Copy failed.', ok ? 'success' : 'error');
}

function isLikelyURLInput(value) {
  const text = String(value || '').trim();
  if (!text || /\s/.test(text)) return false;
  const normalized = text.startsWith('http://') || text.startsWith('https://') ? text : `https://${text}`;
  try {
    const parsed = new URL(normalized);
    return parsed.protocol === 'http:' || parsed.protocol === 'https:';
  } catch (_) {
    return false;
  }
}

function normalizedComposerURL(value) {
  const text = String(value || '').trim();
  if (!text) return '';
  return text.startsWith('http://') || text.startsWith('https://') ? text : `https://${text}`;
}

function clearComposerImage() {
  const imageInput = document.getElementById('composerImageInput');
  if (imageInput) imageInput.value = '';
  updateComposerAttachmentUI();
}

function updateComposerAttachmentUI() {
  const imageInput = document.getElementById('composerImageInput');
  const attachmentRow = document.getElementById('composerAttachmentRow');
  const attachmentName = document.getElementById('composerAttachmentName');
  const hasImage = Boolean(imageInput.files && imageInput.files[0]);

  if (hasImage) {
    attachmentName.textContent = imageInput.files[0].name;
    attachmentRow.classList.remove('hidden');
    return;
  }
  attachmentName.textContent = '';
  attachmentRow.classList.add('hidden');
}

function openComposerFilePicker() {
  document.getElementById('composerImageInput').click();
}

function clearLabWorkspace() {
  renderLines([]);
  renderAppPreview(null);
  updateResultsSummary('No predictions yet.');
  updateQuickOutput([], '');
  document.getElementById('composerInput').value = '';
  clearComposerImage();
  document.getElementById('caseId').value = '';
  const holdoutCheck = document.getElementById('composerHoldoutCheck');
  if (holdoutCheck) holdoutCheck.checked = false;
  setSaveKind(SAVE_KIND_TRAIN);
  syncCaseIdWithHoldoutMode();
  lastSourcePreview = '';
  lastExtractMethod = '';
  lastSourceURL = '';
  lastSourceType = 'manual_edge';
  updateComposerAttachmentUI();
  updateLabVisibility();
}

function resolvePredictionInput() {
  const composerInput = document.getElementById('composerInput');
  const imageInput = document.getElementById('composerImageInput');
  const text = String(composerInput.value || '').trim();
  const hasImage = Boolean(imageInput.files && imageInput.files[0]);

  if (!text && !hasImage) {
    throw new Error('Paste recipe URL/text or attach an image first');
  }

  if (text && isLikelyURLInput(text)) {
    return {
      mode: 'url',
      url: normalizedComposerURL(text),
      imageIgnored: hasImage,
    };
  }

  if (text) {
    return {
      mode: 'text',
      text,
      imageIgnored: hasImage,
    };
  }

  return {
    mode: 'image',
    file: imageInput.files[0],
    imageIgnored: false,
  };
}

function currentLabeledLines() {
  return lastLines.map(row => ({
    index: row.index,
    text: (() => {
      const edit = lineEditsByIndex[row.index];
      const candidate = String(edit && edit.text != null ? edit.text : row.text || '').trim();
      return candidate || row.text;
    })(),
    label: String((lineEditsByIndex[row.index] && lineEditsByIndex[row.index].label) || row.label || 'junk'),
  }));
}

function collectAssemblePayload() {
  const lines = currentLabeledLines();
  return {
    lines,
    source_url: lastSourceURL,
  };
}

function renderSectionList(container, sections) {
  container.innerHTML = '';
  if (!sections || !sections.length) {
    container.textContent = 'None';
    return;
  }

  const fragment = document.createDocumentFragment();
  sections.forEach((section, index) => {
    const block = document.createElement('div');
    block.className = 'previewSection';

    const title = document.createElement('div');
    title.className = 'previewSectionTitle';
    const name = section.name || 'Main';
    const items = Array.isArray(section.items) ? section.items : [];
    title.textContent = `${index + 1}. ${name} (${items.length})`;
    block.appendChild(title);

    const list = document.createElement('div');
    list.className = 'previewList';
    items.forEach((item) => {
      const row = document.createElement('div');
      row.className = 'previewListItem';
      row.textContent = String(item || '');
      list.appendChild(row);
    });

    block.appendChild(list);
    fragment.appendChild(block);
  });
  container.appendChild(fragment);
}

function formatNumberCompact(value) {
  const num = Number(value);
  if (!Number.isFinite(num)) return String(value ?? '');
  return Number.isInteger(num) ? String(num) : String(num.toFixed(3)).replace(/0+$/, '').replace(/\.$/, '');
}

function formatQuantityPreview(quantity) {
  if (!quantity) return '';
  const value = quantity.value;
  const upper = quantity.upperValue;
  const unit = (quantity.unit || '').trim();
  if (value == null) return '';
  if (upper != null) {
    return `${formatNumberCompact(value)} - ${formatNumberCompact(upper)} ${unit}`.trim();
  }
  return `${formatNumberCompact(value)} ${unit}`.trim();
}

function formatIngredientQuantities(item) {
  const parts = [];
  const primary = formatQuantityPreview(item && item.quantity ? item.quantity : null);
  if (primary) parts.push(primary);
  const additional = Array.isArray(item && item.additionalQuantities) ? item.additionalQuantities : [];
  additional.forEach((entry) => {
    const text = formatQuantityPreview(entry);
    if (text) parts.push(text);
  });
  return parts.join(' + ');
}

function ingredientSectionsForPreview(recipe) {
  const ingredients = Array.isArray(recipe.ingredients) ? recipe.ingredients : [];
  if (!ingredients.length) return [];

  const grouped = new Map();
  const addSection = (sectionName) => {
    const key = sectionName || 'Main';
    if (!grouped.has(key)) grouped.set(key, []);
    return key;
  };

  ingredients.forEach((item) => {
    const key = addSection(item.section || 'Main');
    grouped.get(key).push(item);
  });

  const orderedKeys = [];
  (recipe.ingredientSections || []).forEach((section) => {
    const key = section && section.name ? section.name : 'Main';
    if (grouped.has(key) && !orderedKeys.includes(key)) orderedKeys.push(key);
  });
  grouped.forEach((_, key) => {
    if (!orderedKeys.includes(key)) orderedKeys.push(key);
  });

  const out = [];
  orderedKeys.forEach((key, index) => {
    const items = grouped.get(key) || [];
    const sectionItems = [];
    items.forEach((item) => {
      const qty = formatIngredientQuantities(item);
      const note = String(item && item.note ? item.note : '').trim();
      const base = qty ? `${qty} | ${item.name}` : `${item.name}`;
      sectionItems.push(note ? `${base} (${note})` : base);
    });
    out.push({
      name: key,
      items: sectionItems,
    });
  });
  return out;
}

function renderAppPreview(recipe) {
  const summary = document.getElementById('appPreviewSummary');
  const ingredientPreview = document.getElementById('ingredientSectionsPreview');
  const stepPreview = document.getElementById('stepSectionsPreview');
  const jsonPreview = document.getElementById('appRecipeJson');

  if (!recipe) {
    lastAssembledRecipe = null;
    summary.textContent = 'No app save preview yet.';
    ingredientPreview.innerHTML = '';
    ingredientPreview.textContent = 'No sections yet.';
    stepPreview.innerHTML = '';
    stepPreview.textContent = 'No sections yet.';
    jsonPreview.textContent = 'No preview yet.';
    return;
  }

  lastAssembledRecipe = recipe;
  const stats = recipe.stats || {};
  const ingredientCount = stats.ingredient_count ?? (recipe.ingredients || []).length;
  const parsedQtyCount = stats.ingredient_parsed_quantity_count ?? 0;
  const stepCount = stats.step_count ?? (recipe.steps || []).length;
  const noteCount = stats.note_count ?? 0;
  const ingredientSectionCount = stats.ingredient_section_count ?? (recipe.ingredientSections || []).length;
  const stepSectionCount = stats.step_section_count ?? (recipe.stepSections || []).length;
  summary.textContent = `Will save: ${ingredientCount} ingredients (${parsedQtyCount} with parsed quantity/unit) across ${ingredientSectionCount} ingredient sections, ${stepCount} steps across ${stepSectionCount} step sections, ${noteCount} note lines.`;

  renderSectionList(ingredientPreview, ingredientSectionsForPreview(recipe));
  const stepSections = (recipe.stepSections || []).map((section) => ({
    name: section && section.name ? section.name : 'Main',
    items: Array.isArray(section && section.items) ? section.items.map((item) => String(item || '')) : [],
  }));
  renderSectionList(stepPreview, stepSections);
  jsonPreview.textContent = JSON.stringify(recipe, null, 2);
  updateDerivedSectionsInTable(recipe);
}

function scheduleAppPreview() {
  if (assembleDebounceId) clearTimeout(assembleDebounceId);
  assembleDebounceId = setTimeout(() => {
    refreshAppPreview();
  }, 120);
}

function clampLinesPage() {
  const totalPages = Math.max(1, Math.ceil(lastLines.length / LINES_PAGE_SIZE));
  linesPage = Math.min(Math.max(1, linesPage), totalPages);
  return totalPages;
}

function pagedRowsForCurrentPage() {
  clampLinesPage();
  if (!lastLines.length) return [];
  const start = (linesPage - 1) * LINES_PAGE_SIZE;
  const end = start + LINES_PAGE_SIZE;
  return lastLines.slice(start, end);
}

function updateLinesPagerUI() {
  const pager = document.getElementById('linesPager');
  const prevBtn = document.getElementById('linesPrevBtn');
  const nextBtn = document.getElementById('linesNextBtn');
  const summary = document.getElementById('linesPageSummary');
  if (!pager || !prevBtn || !nextBtn || !summary) return;

  const total = lastLines.length;
  const totalPages = clampLinesPage();
  if (total <= LINES_PAGE_SIZE) {
    pager.classList.add('hidden');
    summary.textContent = `Rows ${total ? 1 : 0}-${total} of ${total}`;
    return;
  }

  pager.classList.remove('hidden');
  const start = (linesPage - 1) * LINES_PAGE_SIZE + 1;
  const end = Math.min(linesPage * LINES_PAGE_SIZE, total);
  summary.textContent = `Rows ${start}-${end} of ${total} (Page ${linesPage}/${totalPages})`;
  prevBtn.disabled = linesPage <= 1;
  nextBtn.disabled = linesPage >= totalPages;
}

function renderLinesPage() {
  const tbody = document.querySelector('#linesTable tbody');
  tbody.innerHTML = '';

  const rows = pagedRowsForCurrentPage();
  for (const row of rows) {
    const editState = lineEditsByIndex[row.index] || {
      text: row.text,
      label: row.label,
    };
    lineEditsByIndex[row.index] = editState;

    const tr = document.createElement('tr');

    const tdIndex = document.createElement('td');
    tdIndex.textContent = row.index;

    const tdText = document.createElement('td');
    const textInput = document.createElement('textarea');
    textInput.className = 'lineTextInput';
    textInput.value = String(editState.text || '');
    textInput.dataset.index = row.index;
    textInput.addEventListener('input', () => {
      lineEditsByIndex[row.index] = {
        text: String(textInput.value || ''),
        label: String((lineEditsByIndex[row.index] && lineEditsByIndex[row.index].label) || row.label || 'junk'),
      };
      scheduleAppPreview();
      updateDerivedSectionsInTable();
    });
    tdText.appendChild(textInput);

    const tdPred = document.createElement('td');
    tdPred.textContent = row.predicted_label;

    const tdConf = document.createElement('td');
    tdConf.textContent = row.confidence;

    const tdLabel = document.createElement('td');
    const select = document.createElement('select');
    select.dataset.index = row.index;
    for (const label of LABELS) {
      const opt = document.createElement('option');
      opt.value = label;
      opt.textContent = label;
      if (label === editState.label) opt.selected = true;
      select.appendChild(opt);
    }
    select.addEventListener('change', () => {
      lineEditsByIndex[row.index] = {
        text: String((lineEditsByIndex[row.index] && lineEditsByIndex[row.index].text) || row.text || ''),
        label: select.value,
      };
      updateDerivedSectionsInTable();
      scheduleAppPreview();
    });
    tdLabel.appendChild(select);

    const tdSection = document.createElement('td');
    tdSection.dataset.derivedSectionIndex = String(row.index);

    tr.append(tdIndex, tdText, tdPred, tdConf, tdLabel, tdSection);
    tbody.appendChild(tr);
  }

  updateDerivedSectionsInTable();
  updateLinesPagerUI();
  updateLabVisibility();
}

function renderLines(lines) {
  lastLines = lines;
  lineEditsByIndex = {};
  lines.forEach((row) => {
    lineEditsByIndex[row.index] = {
      text: String(row.text || ''),
      label: String(row.label || 'junk'),
    };
  });
  linesPage = 1;
  renderLinesPage();
}

function goToPrevLinesPage() {
  linesPage -= 1;
  renderLinesPage();
}

function goToNextLinesPage() {
  linesPage += 1;
  renderLinesPage();
}

function collectPayload() {
  const caseId = syncCaseIdWithHoldoutMode();

  const lines = currentLabeledLines();
  const saveKind = selectedSaveKind();

  const payload = {
    id: caseId,
    source_type: sourceTypeForSaveKind(saveKind, lastSourceType),
    save_kind: saveKind,
    title: lines.length ? lines[0].text : 'Untitled',
    lines,
  };
  if (lastAssembledRecipe) {
    payload.assembled_recipe = lastAssembledRecipe;
  }
  return payload;
}
