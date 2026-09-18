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
cfg.equivalentDopplerHz = rx.equivalentDopplerHz;
cfg.captureBurstCount = rx.radioStatus.captureCalls;
otfs_tr_validate_config(cfg);

processed = wide_rx_process_capture(rx.rx20, tx.training, tx.params, ...
    tx.reference.bitsPerFrame, cfg);
result = otfs_tr_finalize_result(processed, rx.equivalentDopplerHz, cfg);
result.actualBasebandOffsetHz = -rx.equivalentDopplerHz;
result.referenceFile = string(referenceFile);
result.captureFile = string(captureFile);
result.pairDirectory = pairDirectory;

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
result.acceptance = otfs_tr_evaluate_acceptance(cfg, result, radioStatus);
reportRoot = cfg.resultRoot;
if strlength(pairDirectory) > 0
    reportRoot = fullfile(pairDirectory, "reports");
end
result.report = otfs_tr_save_report(cfg, result, radioStatus, reportRoot);

if strlength(pairDirectory) > 0
    manifestFile = fullfile(pairDirectory, "pair_manifest.mat");
    pairManifest = localLoadManifest(manifestFile, pairDirectory, ...
        referenceFile, captureFile);
    pairManifest.status = "processed";
    pairManifest.processedAt = string(datetime("now", ...
        "Format", "yyyy-MM-dd HH:mm:ss.SSS"));
    pairManifest.reportDirectory = result.report.directory;
    save(manifestFile, "pairManifest");
end

fprintf("Offline comparison: CFO=%+.1f Hz, frames=%d, bits=%d, errors=%d, BER=%.9g\n", ...
    result.cfoEstimateHz, result.validFrames, result.totalBits, ...
    result.totalErrors, result.ber);
fprintf("Spectral efficiency=%.3f bit/s/Hz, overall pass=%d\n", ...
    cfg.designSpectralEfficiency, result.acceptance.pass);
fprintf("Report: %s\n", result.report.textFile);
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
    tx.cfg.preambleLen == rx.cfg.preambleLen;
if ~compatible
    error("otfs_tr:IncompatibleTxRxConfiguration", ...
        "TX reference and RX capture use incompatible waveform settings.");
end
end
