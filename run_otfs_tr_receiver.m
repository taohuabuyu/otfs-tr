function rxRun = run_otfs_tr_receiver(receiverInput)
%run_otfs_tr_receiver Capture a fixed raw-IQ window into X310 memory.
%
% Preferred software entry: run_otfs_tr_receiver(rxConfigTxtPath).
% Direct entry: run_otfs_tr_receiver(testCaseMatPath).
% The RX TXT is intentionally parsed only after raw IQ has been saved.
% It contains only testPayload=<RX-local MAT path>; TX CFO is unknown here.
% The input may be one MAT file or a directory of MAT cases.
% A directory enables automatic selection from the received air case code.

cfg = otfs_tr_config();
if nargin < 1
    inputOptions = otfs_tr_resolve_receiver_input();
else
    inputOptions = otfs_tr_resolve_receiver_input(receiverInput);
end
softwareTxtMode = inputOptions.softwareTxtMode;
sourceConfigFile = inputOptions.sourceConfigFile;
localTestCaseMode = inputOptions.localTestCaseMode;
autoCaseMode = inputOptions.autoCaseMode;
equivalentDopplerHz = inputOptions.equivalentDopplerHz;
requestedCfoKnown = inputOptions.requestedCfoKnown;
% Zero is a neutral local snapshot only. Actual CFO is estimated from IQ.
cfg = otfs_tr_apply_equivalent_cfo(cfg, 0);
if localTestCaseMode
    cfg = otfs_tr_apply_test_case_mode(cfg);
end
otfs_tr_validate_config(cfg);

pair = otfs_tr_prepare_pair(cfg);
timestamp = pair.runId;
runDirectory = pair.pairDirectory;
captureFile = pair.captureFile;

rxCenterFrequencyHz = cfg.rxCenterFrequencyHz;
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
fprintf("[RX] 接收开始\n");
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
    "equivalentDopplerHz", "requestedCfoKnown", ...
    "rxCenterFrequencyHz", "sourceConfigFile", "timestamp", "-v7.3");
pair.status = "waiting-for-reference";
pair.captureSavedAt = string(datetime("now", ...
    "Format", "yyyy-MM-dd HH:mm:ss.SSS"));
pairManifest = pair;
save(pair.manifestFile, "pairManifest");
fprintf("[RX] 接收完成\n");

rxRun = struct();
rxRun.captureFile = string(captureFile);
rxRun.runDirectory = string(runDirectory);
rxRun.pairDirectory = pair.pairDirectory;
rxRun.referenceDropDirectory = pair.txDirectory;
rxRun.expectedReferenceFile = pair.expectedReferenceFile;
rxRun.status = radioStatus;
rxRun.localRunId = pair.runId;
rxRun.sourceConfigFile = sourceConfigFile;
fprintf("OTFS-TR RX saved raw IQ: %s\n", captureFile);
fprintf("RX samples=%d/%d, complete=%d, anyOverrun=%d.\n", ...
    radioStatus.totalReceivedSamples, radioStatus.expectedReceivedSamples, ...
    radioStatus.captureComplete, radioStatus.anyRxOverrun);
clear radioCleanup;
if localTestCaseMode
    if ~radioStatus.captureComplete || radioStatus.anyRxOverrun
        error("otfs_tr:InvalidCapture", ...
            "Capture is incomplete or contains dropped samples: %s", ...
            captureFile);
    end
    fprintf("[RX] 开始处理\n");
    if softwareTxtMode
        rxConfig = otfs_tr_load_receiver_config(sourceConfigFile);
        referenceCaseFile = rxConfig.test_case_file;
        copyfile(sourceConfigFile, fullfile( ...
            pair.pairDirectory, "receiver_config.txt"));
    elseif autoCaseMode
        selectedCase = otfs_tr_identify_test_case( ...
            rx20, cfg, inputOptions.testCaseInput);
        rxRun.selectedTestCase = selectedCase;
        fprintf("Air case code %08X selected %s (%s).\n", ...
            selectedCase.caseCode, selectedCase.caseId, ...
            selectedCase.filePath);
        referenceCaseFile = selectedCase.filePath;
    else
        referenceCaseFile = inputOptions.testCaseInput;
    end
    otfs_tr_prepare_local_reference( ...
        cfg, equivalentDopplerHz, referenceCaseFile, pair);
    rxRun.result = run_otfs_tr_offline_decode(pair.pairDirectory);
    rxRun.responseFile = rxRun.result.report.responseFile;
    fprintf("Software result: %s\n", rxRun.responseFile);
    fprintf("[RX] 处理完成\n");
else
    fprintf("Use this capture with the matching TX reference file in the explicit two-file offline decoder.\n");
end
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
