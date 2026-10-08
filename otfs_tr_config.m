function cfg = otfs_tr_config(modulationOrder, captureDurationSeconds)
%otfs_tr_config Central user-editable configuration for OTFS-TR.

if nargin < 1
    modulationOrder = 8;
end
if nargin < 2
    captureDurationSeconds = 0.12;
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
% Keep RX tuned to a fixed RF center. Positive equivalentDopplerHz means
% RX center is above TX center, so the received baseband CFO is negative.
cfg.rxCenterFrequencyHz = 2.675e9;
cfg.equivalentDopplerHz = -600e3;
cfg = otfs_tr_apply_equivalent_cfo(cfg, cfg.equivalentDopplerHz);
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
cfg.waveformVersion = 3;
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
cfg.txBufferDurationSeconds = 0.09;
cfg.rxCaptureDurationSeconds = captureDurationSeconds;
cfg.decodeFrameMarginRatio = 0.10;
cfg.targetDecodedFrames = 800;
cfg.superframeLength = 1024;
cfg.frameIdBits = 10;
cfg.frameCrcBits = 8;
cfg.headerRepetition = 3;
cfg.targetTxRms = 0.20;
cfg.targetPayloadTxRms = 0.20;
cfg.hardwareTxPeak = 0.95;

%% TX-only digital AWGN injection.
% Noise is added to the complete waveform immediately before upload to the
% TX X310. These settings are never passed to the RX entry point.
cfg.enableTxAwgn = true;
cfg.txAwgnSnrDb = 20;
cfg.txAwgnSeed = 20260929;

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
cfg.enableFractionalTimingCompensation = true;
cfg.fractionalTimingSearchSamples10 = -0.30:0.01:0.30;
cfg.fractionalTimingEstimationFrames = 20;
cfg.fractionalTimingMinImprovementRatio = 1.01;
cfg.enablePerFrameDcRemoval = false;
cfg.applyPreambleResidualCfoCorrection = false;
cfg.channelTapThresholdRatio = 0.95;
cfg.maxChannelTaps = Inf;
cfg.frameResidualCfoSearchHz = 0;
cfg.enableDdPilotResidualCfoFallback = true;
cfg.ddPilotResidualCfoSearchHz = -3000:100:3000;
cfg.ddPilotResidualCfoTriggerHz = 500;
cfg.enableStructuredRowBiasCorrection = true;
cfg.rowBiasIterations = 5;
cfg.rowBiasMinMagnitude = 0.10;
cfg.rowBiasMaxMagnitude = 0.75;
cfg.rowBiasMinImprovementRatio = 1.25;
cfg.rowBiasMinCoherence = 0.65;
cfg.enableMpNoiseVarianceCalibration = true;
cfg.mpNoiseCalibrationMinRatio = 1.25;
cfg.mpMaximumIterations = 50;
cfg.enableSharedMpNoiseCalibration = true;
cfg.sharedMpNoiseCalibrationFrames = 8;
cfg.sharedMpNoiseCalibrationMinimumValidFrames = 4;
cfg.cpFineSearchRadius = 32;
cfg.cpFineMinScore = 0.65;
cfg.cpFineRelativeMargin = 1.10;
cfg.applyCpCfoCorrection = true;
cfg.wideDownsampleMode = "fir";
cfg.gridPlotFrames = [1 2 3 4 5 10 15 20];
cfg.maxGridPlots = 8;
% Routine runs return after metrics. Enable only when diagnostic plots and
% the compact result MAT archive are explicitly required.
cfg.generateDiagnosticArtifacts = false;
cfg.saveFullDiagnostics = false;
cfg.savedFullDiagnosticFrames = cfg.gridPlotFrames;

%% Host-side frame detection parallelism.
% Global synchronization remains serial. Only independent per-frame OTFS
% demodulation, channel estimation, MP detection, and bit comparison run on
% local process workers. Small jobs stay serial to avoid pool overhead.
cfg.enableFrameParallel = true;
cfg.frameParallelWorkers = 6;
cfg.frameParallelMinimumFrames = 32;
cfg.enableProgressReporting = true;
cfg.progressFile = "";
% Publish one provisional BER update per 100,000 valid, de-duplicated bits.
cfg.progressUpdateEveryBits = 100e3;

%% Capture and acceptance.
cfg.captureCallCount = 1;
cfg.captureBurstCount = cfg.captureCallCount;
% RX software may execute one capture or an automatic sequence of captures.
cfg.receiveMode = "single";
cfg.receiveRoundCount = 1;
cfg.maximumBer = 1e-5;
cfg.targetTestBits = 1e6;
cfg.minimumDopplerHz = 500e3;
cfg.minimumSpectralEfficiency = 2;
cfg.requireNoRadioErrors = true;
cfg.offlineSnrDb = 40;

%% Short application payload carried by the 8-QAM waveform.
cfg.applicationProtocolVersion = 1;
cfg.applicationMagic = uint8([hex2dec("4F") hex2dec("54")]);
cfg.applicationPayloadType = 1;
cfg.applicationMaxPayloadBytes = 32;
cfg.applicationMinimumConsistentFrames = 3;
cfg.controlProtocolVersion = "1.0";
cfg.defaultTransmitDurationSeconds = 30;
cfg.minimumTransmitDurationSeconds = 5;
cfg.maximumTransmitDurationSeconds = 300;

%% Derived design metrics.
cfg.designBitRateBps = cfg.fsTx * cfg.MBits;
cfg.designSpectralEfficiency = cfg.designBitRateBps / ...
    cfg.signalBandwidthHz;
cfg.txTransportPayloadRateBps = cfg.fsTx * 2 * ...
    otfs_tr_transport_bits(cfg.txTransportDataType);
cfg.rxTransportPayloadRateBps = cfg.fsRx * 2 * ...
    otfs_tr_transport_bits(cfg.rxTransportDataType);
cfg.frameLength10 = cfg.preambleLen + cfg.cpLen + cfg.N*cfg.M;
desiredTxBufferFrames = ceil(cfg.txBufferDurationSeconds * ...
    cfg.fsTx / cfg.frameLength10);
cfg.txBufferFrameCount = ceil(desiredTxBufferFrames / ...
    cfg.superframeLength) * cfg.superframeLength;
cfg.txBurstLength = cfg.txBufferFrameCount * cfg.frameLength10;
cfg.rxSampleRateRatio = cfg.fsRx/cfg.fsTx;
cfg.rxSamplesPerFrame = round(cfg.rxCaptureDurationSeconds * cfg.fsRx);
guardSymbols = (2*cfg.nMax+1)*(2*cfg.mMax+1);
cfg.dataSymbolsPerFrame = cfg.N*cfg.M-guardSymbols;
cfg.headerInformationBits = cfg.frameIdBits + cfg.frameCrcBits;
cfg.headerCodedBits = cfg.headerInformationBits*cfg.headerRepetition;
cfg.headerSymbolsPerFrame = ceil(cfg.headerCodedBits/cfg.MBits);
cfg.headerMappedBits = cfg.headerSymbolsPerFrame*cfg.MBits;
cfg.headerPaddingBits = cfg.headerMappedBits-cfg.headerCodedBits;
cfg.payloadSymbolsPerFrame = cfg.dataSymbolsPerFrame - ...
    cfg.headerSymbolsPerFrame;
cfg.payloadBitsPerFrame = cfg.payloadSymbolsPerFrame*cfg.MBits;
cfg.applicationEnabled = cfg.MMod == 8;
if cfg.applicationEnabled
    cfg.applicationPacketBytes = 2 + 1 + 1 + 4 + 2 + ...
        cfg.applicationMaxPayloadBytes + 4;
    cfg.applicationPacketBits = 8*cfg.applicationPacketBytes;
    cfg.applicationMappedBitsPerFrame = ceil( ...
        cfg.applicationPacketBits/cfg.MBits)*cfg.MBits;
else
    cfg.applicationPacketBytes = 0;
    cfg.applicationPacketBits = 0;
    cfg.applicationMappedBitsPerFrame = 0;
end
cfg.berTestBitsPerFrame = cfg.payloadBitsPerFrame - ...
    cfg.applicationMappedBitsPerFrame;
cfg.effectiveBitsPerFrame = cfg.berTestBitsPerFrame;
cfg.totalUniquePayloadBits = cfg.superframeLength* ...
    cfg.berTestBitsPerFrame;
statisticalMinimumTestBits = floor(3/cfg.maximumBer) + 1;
cfg.minimumTestBits = max(statisticalMinimumTestBits, ...
    cfg.targetTestBits);
cfg.minimumValidFrames = ceil(cfg.minimumTestBits / ...
    cfg.effectiveBitsPerFrame);
cfg.availableCaptureFrames = floor( ...
    (cfg.rxSamplesPerFrame/cfg.rxSampleRateRatio) / ...
    cfg.frameLength10) - 1;
desiredDecodedFrames = ceil(cfg.minimumValidFrames * ...
    (1 + cfg.decodeFrameMarginRatio));
desiredDecodedFrames = max(desiredDecodedFrames, cfg.targetDecodedFrames);
cfg.maxDecodedFrames = min([desiredDecodedFrames, ...
    cfg.availableCaptureFrames, cfg.superframeLength]);
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
