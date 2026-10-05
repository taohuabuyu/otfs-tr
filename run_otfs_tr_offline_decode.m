function result = run_otfs_tr_offline_decode(referenceFile, captureFile)
%run_otfs_tr_offline_decode Compare saved TX references with saved RX IQ.

defaultCfg = otfs_tr_config();
pairDirectory = "";
if nargin < 1 || strlength(string(referenceFile)) == 0
    [pairDirectory, referenceFile, captureFile] = ...
        otfs_tr_find_latest_pair(defaultCfg.resultRoot);
elseif nargin < 2 && isfolder(referenceFile)
    pairDirectory = string(referenceFile);
    referenceFile = fullfile(pairDirectory, "tx", "reference_package.mat");
    captureFile = fullfile(pairDirectory, "rx", "rx_capture.mat");
    if ~isfile(referenceFile) || ~isfile(captureFile)
        error("otfs_tr:IncompletePair", ...
            "The selected run package does not contain both saved files: %s", ...
            pairDirectory);
    end
elseif nargin < 2 || strlength(string(captureFile)) == 0
    captureFile = localLatestFile(fullfile( ...
        defaultCfg.resultRoot, "rx", "*", "rx_capture.mat"));
end

tx = load(referenceFile);
rx = load(captureFile);
localValidatePair(tx, rx);
cfg = tx.cfg;
cfg = localApplyCurrentReceiverDefaults(cfg, defaultCfg);
requestedCfoKnown = localField(rx, "requestedCfoKnown", ...
    isfinite(rx.equivalentDopplerHz));
if requestedCfoKnown && isfinite(rx.equivalentDopplerHz)
    requestedEquivalentCfoHz = double(rx.equivalentDopplerHz);
else
    requestedCfoKnown = false;
    requestedEquivalentCfoHz = NaN;
end
if requestedCfoKnown
    cfg = otfs_tr_apply_equivalent_cfo(cfg, requestedEquivalentCfoHz);
else
    % RX-local processing has no knowledge of the TX tuning. The zero value
    % is only a self-consistent nominal reference; CFO recovery is blind.
    cfg = otfs_tr_apply_equivalent_cfo(cfg, 0);
end
cfg.captureBurstCount = rx.radioStatus.captureCalls;
if localField(cfg, "enableProgressReporting", false)
    if strlength(pairDirectory) > 0
        cfg.progressFile = string(fullfile(pairDirectory, "progress.json"));
    elseif strlength(string(localField(cfg, "progressFile", ""))) == 0
        progressRoot = fullfile(cfg.resultRoot, "progress");
        progressName = "progress_" + string(datetime("now", ...
            "Format", "yyyyMMdd_HHmmss_SSS")) + ".json";
        cfg.progressFile = string(fullfile(progressRoot, progressName));
    end
end
otfs_tr_validate_config(cfg);

processed = wide_rx_process_capture(rx.rx20, tx.training, tx.params, ...
    tx.reference, cfg);
if isfield(tx.reference, "testCase") && ...
        processed.caseCodeMismatches > 0
    error("otfs_tr:AirCaseCodeMismatch", ...
        "Received air case code does not match the selected MAT case.");
end
result = otfs_tr_finalize_result(processed, requestedEquivalentCfoHz, cfg);
result.requestedCfoKnown = requestedCfoKnown;
if requestedCfoKnown
    result.cfoAssessmentSource = "configured_cfo";
    result.actualBasebandOffsetHz = -requestedEquivalentCfoHz;
else
    result.cfoAssessmentSource = "estimated_cfo";
    result.actualBasebandOffsetHz = NaN;
end
result.referenceFile = string(referenceFile);
result.captureFile = string(captureFile);
result.pairDirectory = pairDirectory;
result.localRunId = localRunId(pairDirectory);
result.referenceOrigin = string(localField(tx, ...
    "referenceOrigin", "tx-saved-reference"));
result.transmitterStatusVerified = ...
    result.referenceOrigin == "tx-saved-reference";
result.txAwgnEvidenceAvailable = isfield(tx, "txAwgnInfo");
if result.txAwgnEvidenceAvailable
    result.txAwgn = tx.txAwgnInfo;
end
result.testCaseId = "";
if isfield(tx.reference, "testCase")
    result.testCaseId = string(tx.reference.testCase.caseId);
    result.airCaseCode = uint32(tx.reference.testCase.caseCode);
    result.airCaseCodeConfirmed = result.validFrames >= 2 && ...
        result.caseCodeMismatches == 0;
end

radioStatus = rx.radioStatus;
radioStatus.txRepeatStarted = tx.txStatus.started;
radioStatus.anyTxUnderrun = tx.txStatus.anyTxUnderrun;
radioStatus.txCompleted = tx.txStatus.completed;
radioStatus.txExecutionMode = localField(tx.txStatus, ...
    "executionMode", "host-streaming");
radioStatus.txUnderrunMonitoringAvailable = localField(tx.txStatus, ...
    "underrunMonitoringAvailable", true);
radioStatus.txOnboardReplayStarted = localField(tx.txStatus, ...
    "onboardReplayStarted", false);
radioStatus.txOnboardReplayStopped = localField(tx.txStatus, ...
    "onboardReplayStopped", false);
radioStatus.txNoApiError = localField(tx.txStatus, "noTxApiError", false);
result.radioStatus = radioStatus;
[result.transferRateBps, result.receiveDurationSeconds] = ...
    otfs_tr_calculate_transfer_rate(result.totalBits, radioStatus, cfg.fsRx);
result.receivedBitsForRate = result.totalBits;
result.acceptance = otfs_tr_evaluate_acceptance(cfg, result, radioStatus);
result.acceptance.coreMetricsPass = result.acceptance.pass;
result.acceptance.applicationPass = result.application.pass;
result.overallPass = result.acceptance.coreMetricsPass && ...
    result.acceptance.applicationPass;
reportRoot = cfg.resultRoot;
if strlength(pairDirectory) > 0
    reportRoot = fullfile(pairDirectory, "reports");
end
result.report = otfs_tr_save_report(cfg, result, radioStatus, reportRoot);
result.report.responseFile = string(fullfile( ...
    result.report.directory, "response.json"));
result.report.metricsResponseFile = string(fullfile( ...
    result.report.directory, "metrics_response.json"));
result.report.artifactsResponseFile = string(fullfile( ...
    result.report.directory, "artifacts_response.json"));
if strlength(pairDirectory) > 0
    result.report.latestResponseFile = string(fullfile( ...
        pairDirectory, "response.json"));
else
    result.report.latestResponseFile = result.report.responseFile;
end
result.softwareResponse = otfs_tr_build_software_response( ...
    result, "metrics_completed");
localPublishResponse(result.softwareResponse, result.report, ...
    result.report.metricsResponseFile);
localUpdateManifest(pairDirectory, referenceFile, captureFile, ...
    result.report, "metrics_completed");

generateArtifacts = logical(localField(cfg, ...
    "generateDiagnosticArtifacts", false));
if ~generateArtifacts
    result.diagnosticPlotFiles = strings(0, 1);
    result.artifactsGenerated = false;
    result.softwareResponse = otfs_tr_build_software_response( ...
        result, "artifacts_skipped");
    localPublishResponse(result.softwareResponse, result.report, ...
        result.report.artifactsResponseFile);
    localUpdateManifest(pairDirectory, referenceFile, captureFile, ...
        result.report, "artifacts_skipped");
    localPrintSummary(result, cfg);
    return;
end

try
    plotDirectory = fullfile(result.report.directory, "diagnostic_plots");
    plotOptions = struct("showFigures", false, "closeFigures", true);
    result.diagnosticPlotFiles = wide_rx_plot_diagnostics( ...
        result, tx.params, plotDirectory, plotOptions);
    result.softwareResponse = otfs_tr_build_software_response( ...
        result, "artifacts_completed");
    archivedResult = otfs_tr_compact_result_for_save(result, cfg);
    archivePayload = struct("cfg", cfg, "result", archivedResult, ...
        "radioStatus", radioStatus);
    save(result.report.matFile, "-struct", "archivePayload");
    result.artifactsGenerated = true;
    localPublishResponse(result.softwareResponse, result.report, ...
        result.report.artifactsResponseFile);
    localUpdateManifest(pairDirectory, referenceFile, captureFile, ...
        result.report, "artifacts_completed");
catch exception
    failureResponse = result.softwareResponse;
    failureResponse.status = "failed";
    failureResponse.stage = "artifacts_failed";
    failureResponse.code = 1999;
    failureResponse.error_code = "ARTIFACT_GENERATION_FAILED";
    failureResponse.message = string(exception.message);
    failureResponse.updated_at = string(datetime("now", ...
        "TimeZone", "Asia/Shanghai", ...
        "Format", "yyyy-MM-dd'T'HH:mm:ssXXX"));
    localPublishResponse(failureResponse, result.report, "");
    localUpdateManifest(pairDirectory, referenceFile, captureFile, ...
        result.report, "artifacts_failed");
    rethrow(exception);
end

localPrintSummary(result, cfg);
end

function localPrintSummary(result, cfg)
fprintf("Offline comparison: CFO=%+.1f Hz, frames=%d, bits=%d, errors=%d, BER=%.9g\n", ...
    result.cfoEstimateHz, result.validFrames, result.totalBits, ...
    result.totalErrors, result.ber);
fprintf("Transfer rate=%.6f Mbit/s (%d received bits / %.6f s)\n", ...
    result.transferRateBps/1e6, result.receivedBitsForRate, ...
    result.receiveDurationSeconds);
fprintf("Spectral efficiency=%.3f bit/s/Hz, overall pass=%d\n", ...
    cfg.designSpectralEfficiency, result.overallPass);
fprintf("Report: %s\n", result.report.textFile);
end

function localPublishResponse(response, report, snapshotFile)
if strlength(string(snapshotFile)) > 0
    otfs_tr_write_json_atomic(snapshotFile, response);
end
otfs_tr_write_json_atomic(report.responseFile, response);
if report.latestResponseFile ~= report.responseFile
    otfs_tr_write_json_atomic(report.latestResponseFile, response);
end
end

function localUpdateManifest(pairDirectory, referenceFile, captureFile, ...
        report, stage)
if strlength(pairDirectory) == 0
    return;
end
manifestFile = fullfile(pairDirectory, "pair_manifest.mat");
pairManifest = localLoadManifest(manifestFile, pairDirectory, ...
    referenceFile, captureFile);
pairManifest.processingStage = stage;
pairManifest.reportDirectory = report.directory;
pairManifest.responseFile = report.latestResponseFile;
timestamp = string(datetime("now", ...
    "Format", "yyyy-MM-dd HH:mm:ss.SSS"));
switch stage
    case "metrics_completed"
        pairManifest.status = "processing";
        pairManifest.metricsCompletedAt = timestamp;
    case "artifacts_completed"
        pairManifest.status = "processed";
        pairManifest.processedAt = timestamp;
        pairManifest.artifactsCompletedAt = timestamp;
    case "artifacts_skipped"
        pairManifest.status = "processed";
        pairManifest.processedAt = timestamp;
        pairManifest.artifactsSkippedAt = timestamp;
    otherwise
        pairManifest.status = "failed";
        pairManifest.artifactsFailedAt = timestamp;
end
save(manifestFile, "pairManifest");
end

function runId = localRunId(pairDirectory)
if strlength(pairDirectory) > 0
    [~, runId] = fileparts(pairDirectory);
    runId = string(runId);
else
    runId = "";
end
end

function cfg = localApplyCurrentReceiverDefaults(cfg, currentCfg)
% Older reference packages predate receiver-only algorithms. Import only
% missing RX controls so stored waveform and modulation parameters remain
% authoritative while old captures can use the current decoder.
receiverFields = [ ...
    "enableFractionalTimingCompensation", ...
    "fractionalTimingSearchSamples10", ...
    "fractionalTimingEstimationFrames", ...
    "fractionalTimingMinImprovementRatio", ...
    "enablePerFrameDcRemoval", ...
    "enableDdPilotResidualCfoFallback", ...
    "ddPilotResidualCfoSearchHz", ...
    "ddPilotResidualCfoTriggerHz", ...
    "enableStructuredRowBiasCorrection", ...
    "rowBiasIterations", "rowBiasMinMagnitude", ...
    "rowBiasMaxMagnitude", "rowBiasMinImprovementRatio", ...
    "rowBiasMinCoherence", ...
    "enableMpNoiseVarianceCalibration", ...
    "mpNoiseCalibrationMinRatio", "mpMaximumIterations", ...
    "enableSharedMpNoiseCalibration", ...
    "sharedMpNoiseCalibrationFrames", ...
    "sharedMpNoiseCalibrationMinimumValidFrames", ...
    "enableFrameParallel", "frameParallelWorkers", ...
    "frameParallelMinimumFrames", ...
    "enableProgressReporting", "progressFile", ...
    "progressUpdateEveryBits", ...
    "generateDiagnosticArtifacts", ...
    "saveFullDiagnostics", "savedFullDiagnosticFrames"];
for fieldIndex = 1:numel(receiverFields)
    fieldName = receiverFields(fieldIndex);
    if ~isfield(cfg, fieldName) && isfield(currentCfg, fieldName)
        cfg.(fieldName) = currentCfg.(fieldName);
    end
end
end

function pairManifest = localLoadManifest(manifestFile, pairDirectory, ...
        referenceFile, captureFile)
if isfile(manifestFile)
    savedManifest = load(manifestFile, "pairManifest");
    pairManifest = savedManifest.pairManifest;
else
    pairManifest = struct("version", 1, ...
        "pairDirectory", string(pairDirectory), ...
        "expectedReferenceFile", string(referenceFile), ...
        "captureFile", string(captureFile));
end
end

function value = localField(s, name, defaultValue)
if isfield(s, name)
    value = s.(name);
else
    value = defaultValue;
end
end

function filePath = localLatestFile(pattern)
files = dir(pattern);
if isempty(files)
    error("otfs_tr:MissingSavedRun", ...
        "No saved file matches: %s", pattern);
end
[~, latestIndex] = max([files.datenum]);
filePath = fullfile(files(latestIndex).folder, files(latestIndex).name);
end

function localValidatePair(tx, rx)
requiredTx = ["cfg", "params", "training", "reference", "txStatus"];
requiredRx = ["cfg", "rx20", "radioStatus", "equivalentDopplerHz"];
for index = 1:numel(requiredTx)
    if ~isfield(tx, requiredTx(index))
        error("otfs_tr:InvalidReferenceFile", ...
            "TX reference file is missing %s.", requiredTx(index));
    end
end
for index = 1:numel(requiredRx)
    if ~isfield(rx, requiredRx(index))
        error("otfs_tr:InvalidCaptureFile", ...
            "RX capture file is missing %s.", requiredRx(index));
    end
end
compatible = tx.cfg.fsTx == rx.cfg.fsTx && ...
    tx.cfg.fsRx == rx.cfg.fsRx && tx.cfg.N == rx.cfg.N && ...
    tx.cfg.M == rx.cfg.M && tx.cfg.MMod == rx.cfg.MMod && ...
    tx.cfg.cpLen == rx.cfg.cpLen && ...
    tx.cfg.preambleLen == rx.cfg.preambleLen && ...
    localField(tx.cfg, "waveformVersion", 1) == ...
    localField(rx.cfg, "waveformVersion", 1);
if ~compatible
    error("otfs_tr:IncompatibleTxRxConfiguration", ...
        "TX reference and RX capture use incompatible waveform settings.");
end
end
