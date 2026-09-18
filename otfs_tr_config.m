function cfg = otfs_tr_config(modulationOrder)
%otfs_tr_config Central user-editable configuration for OTFS-TR.

if nargin < 1
    modulationOrder = 8;
end

cfg = struct();
cfg.projectRoot = fileparts(mfilename("fullpath"));
cfg.resultRoot = fullfile(cfg.projectRoot, "results");
cfg.resultDir = cfg.resultRoot;
cfg.scenarioName = "otfs_tr_600k_two_x310";

%% Two independent X310 devices.
cfg.platform = "X310";
cfg.txAddress = "192.168.10.2";
cfg.rxAddress = "192.168.10.3";
cfg.txRadioConfiguration = "My USRP X310";
cfg.rxRadioConfiguration = "My USRP X310";
cfg.txAntenna = "RFB:TX/RX";
cfg.rxAntenna = "RFA:RX2";
cfg.masterClockRate = 200e6;
cfg.txCenterFrequencyHz = 2.675e9;
cfg.equivalentDopplerHz = 600e3;
cfg.txGainDb = 5;
cfg.rxGainDb = 20;
cfg.txChannelMapping = 2;
cfg.rxChannelMapping = 1;
cfg.rxAntennaPort = "RX2";
% R2025a uses the UHD 4.6 vendor path. Keep its supported 16-bit X310
% transport; the sc8 RFNoC path has not provided reliable streaming on the
% current host. MATLAB signal processing remains floating point.
cfg.txTransportDataType = "int16";
cfg.rxTransportDataType = "int16";
cfg.radioWarmupSeconds = 0.25;

%% Waveform and OTFS grid.
cfg.fsTx = 10e6;
cfg.fsRx = 20e6;
cfg.signalBandwidthHz = 10e6;
cfg.N = 32;
cfg.M = 24;
cfg.MMod = modulationOrder;
cfg.MBits = log2(cfg.MMod);
cfg.cpLen = 64;
cfg.xPilot = 2 + 2i;
cfg.mPilot = 12;
cfg.nPilot = 16;
cfg.mMax = 3;
cfg.nMax = 6;
cfg.dataScale = 1;
cfg.randomSeed = 1;
cfg.preambleLen = 63;
cfg.preambleAmp = 0.5;
cfg.preambleRoot = 25;
% Hardware TX submits one prebuilt, continuous block on every System-object
% call. Every OTFS frame retains its own preamble; there are no periodic
% silent gaps inside or between submitted buffers.
cfg.zerosAheadLen = 0;
cfg.zerosTailLen = 0;
cfg.txBufferDurationSeconds = 0.10;
cfg.rxCaptureDurationSeconds = 0.05;
cfg.decodeFrameMarginRatio = 0.10;
cfg.targetTxRms = 0.20;
cfg.targetPayloadTxRms = 0.20;
cfg.hardwareTxPeak = 0.95;

%% Receiver synchronization and residual-CFO correction.
cfg.cfoSearchHz = -800e3:50e3:800e3;
cfg.cfoFineSearchSpanHz = 25e3;
cfg.cfoFineSearchStepHz = 1e3;
cfg.preamblePeakThreshold = 0.45;
cfg.framePreambleMinScore = 0.45;
cfg.preambleMinSpacingRatio = 0.80;
cfg.cfoSearchWindowSamples20 = 20000;
cfg.enableSfoCompensation = true;
cfg.sfoMinimumPreambles = 12;
cfg.sfoMinCorrectionPpm = 0.5;
cfg.sfoMaxAbsPpm = 200;
cfg.sfoPreambleMinScore = 0.35;
cfg.enableRxLowpassFilter = false;
cfg.applyPreambleResidualCfoCorrection = false;
cfg.channelTapThresholdRatio = 0.95;
cfg.maxChannelTaps = Inf;
cfg.frameResidualCfoSearchHz = 0;
cfg.cpFineSearchRadius = 32;
cfg.cpFineMinScore = 0.65;
cfg.cpFineRelativeMargin = 1.10;
cfg.applyCpCfoCorrection = true;
cfg.wideDownsampleMode = "fir";
cfg.gridPlotFrames = [1 2 3 4 5 10 15 20];
cfg.maxGridPlots = 8;

%% Capture and acceptance.
cfg.captureCallCount = 1;
cfg.captureBurstCount = cfg.captureCallCount;
cfg.maximumBer = 1e-5;
cfg.minimumDopplerHz = 500e3;
cfg.minimumSpectralEfficiency = 2;
cfg.requireNoRadioErrors = true;
cfg.offlineSnrDb = 40;

%% Derived design metrics.
cfg.designBitRateBps = cfg.fsTx * cfg.MBits;
cfg.designSpectralEfficiency = cfg.designBitRateBps / ...
    cfg.signalBandwidthHz;
cfg.txTransportPayloadRateBps = cfg.fsTx * 2 * ...
    otfs_tr_transport_bits(cfg.txTransportDataType);
cfg.rxTransportPayloadRateBps = cfg.fsRx * 2 * ...
    otfs_tr_transport_bits(cfg.rxTransportDataType);
cfg.frameLength10 = cfg.preambleLen + cfg.cpLen + cfg.N*cfg.M;
cfg.txBufferFrameCount = ceil(cfg.txBufferDurationSeconds * ...
    cfg.fsTx / cfg.frameLength10);
cfg.txBurstLength = cfg.txBufferFrameCount * cfg.frameLength10;
cfg.rxSampleRateRatio = cfg.fsRx/cfg.fsTx;
cfg.rxSamplesPerFrame = round(cfg.rxCaptureDurationSeconds * cfg.fsRx);
guardSymbols = (2*cfg.nMax+1)*(2*cfg.mMax+1);
cfg.effectiveBitsPerFrame = (cfg.N*cfg.M-guardSymbols)*cfg.MBits;
cfg.minimumTestBits = floor(3/cfg.maximumBer) + 1;
cfg.minimumValidFrames = ceil(cfg.minimumTestBits / ...
    cfg.effectiveBitsPerFrame);
cfg.availableCaptureFrames = floor( ...
    (cfg.rxSamplesPerFrame/cfg.rxSampleRateRatio) / ...
    cfg.frameLength10) - 1;
desiredDecodedFrames = ceil(cfg.minimumValidFrames * ...
    (1 + cfg.decodeFrameMarginRatio));
cfg.maxDecodedFrames = min(desiredDecodedFrames, ...
    cfg.availableCaptureFrames);
end

function bitsPerComponent = otfs_tr_transport_bits(transportDataType)
switch string(transportDataType)
    case "int8"
        bitsPerComponent = 8;
    case "int16"
        bitsPerComponent = 16;
    otherwise
        error("otfs_tr:InvalidTransportDataType", ...
            "TransportDataType must be int8 or int16.");
end
end
