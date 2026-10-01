function txRun = run_otfs_tr_transmitter(requestOrDuration)
%run_otfs_tr_transmitter Transmit from the TX X310 and save references.
%
% Run this function in the TX MATLAB session. The waveform is uploaded once
% to the X310 onboard buffer and replayed continuously by the radio.
% A software-supplied key=value TXT path may also be passed directly.

cfg = otfs_tr_config();
sourceConfigFile = "";
if nargin < 1 || isempty(requestOrDuration)
    requestOrDuration = cfg.defaultTransmitDurationSeconds;
end
if isstruct(requestOrDuration)
    request = otfs_tr_validate_request(requestOrDuration, cfg);
elseif ischar(requestOrDuration) || ...
        (isstring(requestOrDuration) && isscalar(requestOrDuration))
    request = otfs_tr_load_software_config(requestOrDuration, cfg);
    sourceConfigFile = string(requestOrDuration);
else
    request = localLegacyRequest(cfg, requestOrDuration);
end
durationSeconds = request.options.duration_seconds;
testCase = [];
if isfield(request, "test_case_file")
    cfg = otfs_tr_apply_test_case_mode(cfg);
    testCase = otfs_tr_load_test_case(request.test_case_file, cfg);
end
cfg = otfs_tr_apply_equivalent_cfo(cfg, request.equivalent_cfo_hz);
cfg = otfs_tr_apply_software_targets(cfg, request);
otfs_tr_validate_config(cfg);
[txSignal, reference, params, training] = ...
    otfs_tr_build_waveform(cfg, request, testCase);
[txSignalForRadio, txAwgnInfo] = otfs_tr_add_tx_awgn(txSignal, cfg);
timestamp = string(datetime("now", "Format", "yyyyMMdd_HHmmss"));
pair = otfs_tr_prepare_pair(cfg);
runDirectory = pair.txDirectory;
referenceFile = pair.expectedReferenceFile;
requestFile = fullfile(pair.pairDirectory, "request.json");
writelines(jsonencode(request, PrettyPrint=true), requestFile);
if strlength(sourceConfigFile) > 0
    copyfile(sourceConfigFile, fullfile( ...
        pair.pairDirectory, "software_config.txt"));
end
archivedTestCaseFile = "";
if ~isempty(testCase)
    test_case = struct("version", testCase.version, ...
        "case_id", testCase.caseId, ...
        "payload_bits", uint8(testCase.payloadBitsByFrame));
    archivedTestCaseFile = string(fullfile( ...
        pair.pairDirectory, "test_case.mat"));
    save(archivedTestCaseFile, "test_case", "-v7.3");
end

txStatus = struct("started", false, "initialized", false, ...
    "completed", false, ...
    "durationSeconds", durationSeconds, "transmitCalls", 0, ...
    "bufferSamples", numel(txSignal), ...
    "bufferDurationSeconds", numel(txSignal)/cfg.fsTx, ...
    "executionMode", "onboard-continuous", ...
    "underrunMonitoringAvailable", false, ...
    "underruns", false(0, 1), "anyTxUnderrun", false);
txStatus.txAwgn = txAwgnInfo;
save(referenceFile, "cfg", "params", "training", "reference", ...
    "txSignal", "txSignalForRadio", "txAwgnInfo", ...
    "txStatus", "timestamp", "request", "-v7.3");

txRadio = basebandTransmitter(cfg.txRadioConfiguration, ...
    "Preload", true, ...
    "SampleRate", cfg.fsTx, ...
    "CenterFrequency", cfg.txCenterFrequencyHz, ...
    "RadioGain", cfg.txGainDb, ...
    "Antennas", cfg.txAntenna, ...
    "TransmitDataType", "single");
radioCleanup = onCleanup(@() localStopTransmission(txRadio));

fprintf("OTFS-TR TX preparing on %s (%s) at %.6f GHz for %.1f s.\n", ...
    cfg.txRadioConfiguration, cfg.txAddress, ...
    cfg.txCenterFrequencyHz/1e9, durationSeconds);
fprintf("Onboard replay buffer: %d frames, %d samples, %.3f s/period.\n", ...
    cfg.txBufferFrameCount, numel(txSignal), numel(txSignal)/cfg.fsTx);
if txAwgnInfo.enabled
    fprintf([ ...
        "TX whole-waveform AWGN enabled: configured=%.2f dB, " ...
        "actual=%.2f dB, seed=%u, peak=%.4f.\n"], ...
        txAwgnInfo.configuredSnrDb, txAwgnInfo.actualInjectedSnrDb, ...
        uint32(txAwgnInfo.seed), txAwgnInfo.outputPeak);
else
    fprintf("TX whole-waveform AWGN disabled.\n");
end
fprintf("Reference file: %s\n", referenceFile);

overallStart = tic;
fprintf("Uploading waveform to X310 onboard memory. RF transmission has not started.\n");
initializationStart = tic;
txHardwareSignal = single(txSignalForRadio);
transmit(txRadio, txHardwareSignal, "continuous");
txStatus.initializationSeconds = toc(initializationStart);
txStatus.initialized = true;
txStatus.started = true;
txStatus.transmitCalls = 1;
txStatus.onboardReplayStarted = true;
txStatus.noTxApiError = true;
save(referenceFile, "cfg", "params", "training", "reference", ...
    "txSignal", "txSignalForRadio", "txAwgnInfo", ...
    "txStatus", "timestamp", "request", "-v7.3");
fprintf("Onboard continuous transmission started in %.3f s.\n", ...
    txStatus.initializationSeconds);
fprintf("Start run_otfs_tr_receiver in the RX MATLAB session now.\n");

startTime = tic;
pause(durationSeconds);
activeElapsedSeconds = toc(startTime);
stopTransmission(txRadio);

txStatus.completed = true;
txStatus.elapsedSeconds = activeElapsedSeconds;
txStatus.activeElapsedSeconds = activeElapsedSeconds;
txStatus.wallElapsedSeconds = toc(overallStart);
txStatus.onboardReplayStopped = true;
save(referenceFile, "cfg", "params", "training", "reference", ...
    "txSignal", "txSignalForRadio", "txAwgnInfo", ...
    "txStatus", "timestamp", "request", "-v7.3");

pair.status = "waiting-for-capture";
pair.txCompletedAt = string(datetime("now", ...
    "Format", "yyyy-MM-dd HH:mm:ss.SSS"));
pairManifest = pair;
save(pair.manifestFile, "pairManifest");

txRun = struct();
txRun.referenceFile = string(referenceFile);
txRun.runDirectory = string(runDirectory);
txRun.pairDirectory = pair.pairDirectory;
txRun.localRunId = pair.runId;
txRun.request = request;
txRun.requestFile = string(requestFile);
txRun.sourceConfigFile = sourceConfigFile;
txRun.testCaseFile = archivedTestCaseFile;
txRun.txAwgn = txAwgnInfo;
txRun.rxCommand = ...
    'run_otfs_tr_receiver("<RX_LOCAL_TEST_CASE_MAT>")';
txRun.status = txStatus;
fprintf("OTFS-TR onboard TX finished: started=%d, completed=%d.\n", ...
    txStatus.started, txStatus.completed);
clear radioCleanup;
end

function request = localLegacyRequest(cfg, durationSeconds)
request = struct("protocol_version", cfg.controlProtocolVersion, ...
    "command", "start_test", ...
    "payload_text", "TEST", ...
    "equivalent_cfo_hz", cfg.equivalentDopplerHz, ...
    "options", struct("duration_seconds", durationSeconds));
request = otfs_tr_validate_request(request, cfg);
end

function localStopTransmission(txRadio)
try
    stopTransmission(txRadio);
catch
    % Cleanup must not hide the original initialization or transmit error.
end
end
