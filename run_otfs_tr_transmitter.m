function txRun = run_otfs_tr_transmitter(durationSeconds)
%run_otfs_tr_transmitter Transmit from the TX X310 and save references.
%
% Run this function in the TX MATLAB session. The waveform is uploaded once
% to the X310 onboard buffer and replayed continuously by the radio.

cfg = otfs_tr_config();
if nargin < 1
    durationSeconds = 30;
end
validateattributes(durationSeconds, {'numeric'}, ...
    {'scalar', 'real', 'finite', 'positive'});
otfs_tr_validate_config(cfg);

[txSignal, reference, params, training] = otfs_tr_build_waveform(cfg);
timestamp = string(datetime("now", "Format", "yyyyMMdd_HHmmss"));
runDirectory = fullfile(cfg.resultRoot, "tx", timestamp);
if ~exist(runDirectory, "dir")
    mkdir(runDirectory);
end
referenceFile = fullfile(runDirectory, "reference_package.mat");

txStatus = struct("started", false, "initialized", false, ...
    "completed", false, ...
    "durationSeconds", durationSeconds, "transmitCalls", 0, ...
    "bufferSamples", numel(txSignal), ...
    "bufferDurationSeconds", numel(txSignal)/cfg.fsTx, ...
    "executionMode", "onboard-continuous", ...
    "underrunMonitoringAvailable", false, ...
    "underruns", false(0, 1), "anyTxUnderrun", false);
save(referenceFile, "cfg", "params", "training", "reference", ...
    "txSignal", "txStatus", "timestamp");

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
fprintf("Reference file: %s\n", referenceFile);

overallStart = tic;
fprintf("Uploading waveform to X310 onboard memory. RF transmission has not started.\n");
initializationStart = tic;
txHardwareSignal = single(txSignal);
transmit(txRadio, txHardwareSignal, "continuous");
txStatus.initializationSeconds = toc(initializationStart);
txStatus.initialized = true;
txStatus.started = true;
txStatus.transmitCalls = 1;
txStatus.onboardReplayStarted = true;
txStatus.noTxApiError = true;
save(referenceFile, "cfg", "params", "training", "reference", ...
    "txSignal", "txStatus", "timestamp");
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
    "txSignal", "txStatus", "timestamp");

txRun = struct();
txRun.referenceFile = string(referenceFile);
txRun.runDirectory = string(runDirectory);
txRun.status = txStatus;
fprintf("OTFS-TR onboard TX finished: started=%d, completed=%d.\n", ...
    txStatus.started, txStatus.completed);
clear radioCleanup;
end

function localStopTransmission(txRadio)
try
    stopTransmission(txRadio);
catch
    % Cleanup must not hide the original initialization or transmit error.
end
end
