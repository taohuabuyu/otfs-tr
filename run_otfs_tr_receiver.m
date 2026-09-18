function rxRun = run_otfs_tr_receiver(equivalentDopplerHz)
%run_otfs_tr_receiver Capture a fixed raw-IQ window into X310 memory.
%
% Start run_otfs_tr_transmitter in another MATLAB session first. This
% function saves raw IQ and radio diagnostics but does not calculate BER.

cfg = otfs_tr_config();
if nargin < 1
    equivalentDopplerHz = cfg.equivalentDopplerHz;
end
cfg.equivalentDopplerHz = equivalentDopplerHz;
otfs_tr_validate_config(cfg);

pair = otfs_tr_prepare_pair(cfg);
timestamp = pair.runId;
runDirectory = pair.pairDirectory;
captureFile = pair.captureFile;

rxCenterFrequencyHz = cfg.txCenterFrequencyHz + equivalentDopplerHz;
radio = radioConfigurations(cfg.rxRadioConfiguration);
if string(radio.IPAddress) ~= cfg.rxAddress
    error("otfs_tr:RxRadioConfigurationAddressMismatch", ...
        "RX radio configuration %s uses %s, expected %s.", ...
        cfg.rxRadioConfiguration, radio.IPAddress, cfg.rxAddress);
end
rxRadio = basebandReceiver(radio, ...
    "Preload", true, ...
    "SampleRate", cfg.fsRx, ...
    "CenterFrequency", rxCenterFrequencyHz, ...
    "RadioGain", cfg.rxGainDb, ...
    "Antennas", cfg.rxAntenna, ...
    "CaptureDataType", "single", ...
    "DroppedSamplesAction", "error");
radioCleanup = onCleanup(@() localStopCapture(rxRadio));
pause(cfg.radioWarmupSeconds);

captureCalls = cfg.captureCallCount;
if captureCalls ~= 1
    error("otfs_tr:OnboardCaptureCallCount", ...
        "Onboard RX uses exactly one fixed-window capture call.");
end
fprintf("OTFS-TR onboard RX ready on %s (%s) at %.6f GHz.\n", ...
    cfg.rxRadioConfiguration, cfg.rxAddress, rxCenterFrequencyHz/1e9);
fprintf("Capturing %d samples (%.3f s) through %s into X310 memory.\n", ...
    cfg.rxSamplesPerFrame, cfg.rxCaptureDurationSeconds, cfg.rxAntenna);
captureStart = tic;
[frame, captureTimestamp, droppedSamples] = capture( ...
    rxRadio, cfg.rxSamplesPerFrame);
captureWallSeconds = toc(captureStart);
rx20 = double(frame(:));
rxLengths = numel(rx20);
rxOverruns = logical(droppedSamples > 0);

radioStatus = struct();
radioStatus.captureCalls = captureCalls;
radioStatus.executionMode = "onboard-fixed-window";
radioStatus.rxLengths = rxLengths;
radioStatus.rxOverruns = rxOverruns;
radioStatus.droppedSamples = double(droppedSamples);
radioStatus.captureTimestamp = captureTimestamp;
radioStatus.captureWallSeconds = captureWallSeconds;
radioStatus.anyRxOverrun = rxOverruns;
radioStatus.totalReceivedSamples = numel(rx20);
radioStatus.expectedReceivedSamples = captureCalls*cfg.rxSamplesPerFrame;
radioStatus.captureComplete = all(rxLengths == cfg.rxSamplesPerFrame) && ...
    radioStatus.totalReceivedSamples == radioStatus.expectedReceivedSamples;
radioStatus.captureDurationSeconds = numel(rx20)/cfg.fsRx;
radioStatus.rxRms = sqrt(mean(abs(rx20).^2));
radioStatus.rxPeak = max(abs(rx20));
save(captureFile, "cfg", "rx20", "radioStatus", ...
    "equivalentDopplerHz", "rxCenterFrequencyHz", "timestamp", "-v7.3");
pair.status = "waiting-for-reference";
pair.captureSavedAt = string(datetime("now", ...
    "Format", "yyyy-MM-dd HH:mm:ss.SSS"));
pairManifest = pair;
save(pair.manifestFile, "pairManifest");

rxRun = struct();
rxRun.captureFile = string(captureFile);
rxRun.runDirectory = string(runDirectory);
rxRun.pairDirectory = pair.pairDirectory;
rxRun.referenceDropDirectory = pair.txDirectory;
rxRun.expectedReferenceFile = pair.expectedReferenceFile;
rxRun.status = radioStatus;
fprintf("OTFS-TR RX saved raw IQ: %s\n", captureFile);
fprintf("RX samples=%d/%d, complete=%d, anyOverrun=%d.\n", ...
    radioStatus.totalReceivedSamples, radioStatus.expectedReceivedSamples, ...
    radioStatus.captureComplete, radioStatus.anyRxOverrun);
fprintf("After TX finishes, copy its final reference_package.mat to:\n%s\n", ...
    pair.txDirectory);
fprintf("Then run result = run_otfs_tr_offline_decode();\n");
clear radioCleanup;
end

function localStopCapture(rxRadio)
try
    if isCapturing(rxRadio)
        stopCapture(rxRadio);
    end
catch
    % Cleanup must not hide the original configuration or capture error.
end
end
