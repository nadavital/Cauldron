(function init() {
  document.getElementById('caseId').value = '';
  setSaveKind(selectedSaveKind());
  syncCaseIdWithHoldoutMode();
  document.getElementById('datasetDir').value = DEFAULT_DATASET_DIR;
  document.getElementById('datasetBrowseDir').value = DEFAULT_DATASET_DIR;

  document.getElementById('predictBtn').addEventListener('click', predict);
  document.getElementById('saveBtn').addEventListener('click', saveLocal);
  document.getElementById('appendBtn').addEventListener('click', appendDataset);
  document.getElementById('metricsBtn').addEventListener('click', runMetrics);
  document.getElementById('retrainBtn').addEventListener('click', retrainModel);
  document.getElementById('copyMetricsRawBtn').addEventListener('click', copyMetricsRawOutput);
  document.getElementById('copyAppRecipeJsonBtn').addEventListener('click', copyAppRecipeJsonOutput);
  document.getElementById('refreshPreviewBtn').addEventListener('click', refreshAppPreview);
  document.getElementById('linesPrevBtn').addEventListener('click', goToPrevLinesPage);
  document.getElementById('linesNextBtn').addEventListener('click', goToNextLinesPage);
  document.getElementById('metricsHistoryPrevBtn').addEventListener('click', goToPrevMetricsHistoryPage);
  document.getElementById('metricsHistoryNextBtn').addEventListener('click', goToNextMetricsHistoryPage);
  document.getElementById('localRefreshBtn').addEventListener('click', refreshLocalCases);
  document.getElementById('datasetRefreshBtn').addEventListener('click', refreshDatasetCases);
  document.getElementById('datasetSyncBtn').addEventListener('click', syncDatasetDirFromLab);
  document.getElementById('resetCaseIdBtn').addEventListener('click', () => {
    document.getElementById('caseId').value = nowId();
    const effectiveCaseId = syncCaseIdWithHoldoutMode();
    setStatus(`Generated a new case ID in Settings: ${effectiveCaseId}`, 'info');
  });
  document.getElementById('composerHoldoutCheck').addEventListener('change', () => {
    const effectiveCaseId = syncCaseIdWithHoldoutMode();
    const enabled = document.getElementById('composerHoldoutCheck').checked;
    if (enabled) {
      setStatus(`Holdout mode on. Case ID will save as ${effectiveCaseId}.`, 'info');
      return;
    }
    setStatus(`Holdout mode off. Case ID will save as ${effectiveCaseId}.`, 'info');
  });
  document.getElementById('composerSaveKind').addEventListener('change', () => {
    applySaveKindConstraints();
    const effectiveCaseId = syncCaseIdWithHoldoutMode();
    const kind = selectedSaveKind();
    if (kind === SAVE_KIND_OCR_FAILURE) {
      setStatus(`Save mode: OCR failure. Saved as holdout (${effectiveCaseId}).`, 'info');
      return;
    }
    if (kind === SAVE_KIND_PARSE_FAILURE) {
      setStatus(`Save mode: parse failure. Saved as holdout (${effectiveCaseId}).`, 'info');
      return;
    }
    if (kind === SAVE_KIND_HOLDOUT) {
      setStatus(`Save mode: holdout. Case ID will save as ${effectiveCaseId}.`, 'info');
      return;
    }
    setStatus(`Save mode: training example. Case ID is ${effectiveCaseId}.`, 'info');
  });
  document.getElementById('composerAttachBtn').addEventListener('click', openComposerFilePicker);
  document.getElementById('composerAttachmentRemoveBtn').addEventListener('click', () => {
    clearComposerImage();
  });
  document.getElementById('composerImageInput').addEventListener('change', updateComposerAttachmentUI);
  document.getElementById('composerInput').addEventListener('keydown', (event) => {
    if (event.key === 'Enter' && !event.shiftKey) {
      event.preventDefault();
      predict();
    }
  });
  document.querySelectorAll('.navBtn[data-view]').forEach((btn) => {
    btn.addEventListener('click', () => setActiveView(btn.dataset.view));
  });
  document.getElementById('localCasesBody').addEventListener('click', (event) => {
    const target = event.target.closest('button[data-local-id]');
    if (!target) return;
    openLocalCase(target.dataset.localId);
  });
  document.getElementById('datasetCasesBody').addEventListener('click', (event) => {
    const target = event.target.closest('button[data-dataset-id]');
    if (!target) return;
    openDatasetCase(target.dataset.datasetId);
  });
  document.getElementById('datasetDir').addEventListener('change', () => {
    document.getElementById('datasetBrowseDir').value = document.getElementById('datasetDir').value.trim();
  });
  document.getElementById('datasetBrowseDir').addEventListener('change', () => {
    datasetCasesLoaded = false;
    refreshDatasetCases();
  });
  applySaveKindConstraints();
  updateComposerAttachmentUI();
  setActiveView('lab');
  updateResultsSummary('No predictions yet.');
  updateQuickOutput([], '');
  renderAppPreview(null);
  updateLabVisibility();
  log('Ready.');
  refreshLocalCases();
  refreshDatasetCases();
})();
