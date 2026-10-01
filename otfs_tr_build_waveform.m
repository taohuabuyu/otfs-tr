function [txSignal, reference, params, training] = ...
        otfs_tr_build_waveform(cfg, applicationRequest, suppliedTestCase)
%otfs_tr_build_waveform Build a repeated unique-frame OTFS superframe.

rng(cfg.randomSeed, "twister");
requestProvided = nargin >= 2 && ~isempty(applicationRequest);
testCaseMode = isfield(cfg, "payloadMode") && ...
    string(cfg.payloadMode) == "test-case-bits";
testCase = struct();
caseCode = uint32(0);
if ~requestProvided
    applicationRequest = localDefaultApplicationRequest(cfg);
end
if testCaseMode
    if ~requestProvided || ~isfield(applicationRequest, "test_case_file")
        error("otfs_tr:MissingTestCaseFile", ...
            "Test-case waveform requires a request with test_case_file.");
    end
    applicationRequest = otfs_tr_validate_request( ...
        applicationRequest, cfg);
    if nargin >= 3 && ~isempty(suppliedTestCase)
        testCase = suppliedTestCase;
    else
        testCase = otfs_tr_load_test_case( ...
            applicationRequest.test_case_file, cfg);
    end
    caseCode = otfs_tr_case_code(testCase.caseId);
    applicationBits = zeros(0, 1);
    application = struct("enabled", false);
elseif cfg.applicationEnabled
    if isfield(applicationRequest, "test_case_file")
        error("otfs_tr:TestCaseModeRequired", ...
            "Apply test-case mode before building a MAT-bit waveform.");
    end
    applicationRequest = otfs_tr_validate_request(applicationRequest, cfg);
    [applicationBits, application] = ...
        otfs_tr_encode_application(applicationRequest, cfg);
else
    if requestProvided
        error("otfs_tr:ApplicationRequires8Qam", ...
            "Application payload transport is enabled only for 8-QAM.");
    end
    applicationBits = zeros(0, 1);
    application = struct("enabled", false);
end

params = struct();
params.N = cfg.N;
params.M = cfg.M;
params.MMod = cfg.MMod;
params.MBits = cfg.MBits;
params.Nfft = cfg.N * cfg.M;
params.LCp = cfg.cpLen;
params.blockLen = params.Nfft + params.LCp;
params.xPilot = cfg.xPilot;
params.mPilot = cfg.mPilot;
params.nPilot = cfg.nPilot;
params.mMax = cfg.mMax;
params.nMax = cfg.nMax;
params.dataScale = cfg.dataScale;
params.fsTx = cfg.fsTx;
params.pilotPattern = "single";
params.waveformVersion = cfg.waveformVersion;
params.referenceMode = "unique-superframe";
params.superframeLength = cfg.superframeLength;
params.frameIdBits = cfg.frameIdBits;
params.frameCaseIdBits = localFrameCaseIdBits(cfg);
params.frameCrcBits = cfg.frameCrcBits;
params.headerRepetition = cfg.headerRepetition;
params.headerInformationBits = cfg.headerInformationBits;
params.headerCodedBits = cfg.headerCodedBits;
params.headerMappedBits = cfg.headerMappedBits;
params.headerPaddingBits = cfg.headerPaddingBits;
params.headerSymbolsPerFrame = cfg.headerSymbolsPerFrame;
params.payloadBitsPerFrame = cfg.payloadBitsPerFrame;
params.payloadMode = string(localPayloadMode(cfg));
params.applicationMappedBitsPerFrame = cfg.applicationMappedBitsPerFrame;
params.berTestBitsPerFrame = cfg.berTestBitsPerFrame;

[~, params.dataMask] = addpilot(zeros(params.N, params.M), ...
    params.xPilot, params.nPilot, params.mPilot, params.mMax, params.nMax);
dataLinearIndices = find(params.dataMask);
params.headerLinearIndices = dataLinearIndices(1:cfg.headerSymbolsPerFrame);
params.payloadLinearIndices = dataLinearIndices(cfg.headerSymbolsPerFrame+1:end);
params.headerMask = false(params.N, params.M);
params.headerMask(params.headerLinearIndices) = true;
params.payloadMask = false(params.N, params.M);
params.payloadMask(params.payloadLinearIndices) = true;

if testCaseMode
    berTestBitsByFrame = testCase.payloadBitsByFrame;
else
    berTestBitsByFrame = randi([0, 1], cfg.berTestBitsPerFrame, ...
        cfg.superframeLength);
end
payloadBitsByFrame = [repmat(applicationBits, 1, cfg.superframeLength); ...
    berTestBitsByFrame];
headerBitsByFrame = zeros(cfg.headerMappedBits, cfg.superframeLength);
payloadBlocks = complex(zeros(params.blockLen, cfg.superframeLength));

for frameIndex = 1:cfg.superframeLength
    if testCaseMode
        headerBits = otfs_tr_encode_frame_header( ...
            frameIndex-1, cfg, caseCode);
    else
        headerBits = otfs_tr_encode_frame_header(frameIndex-1, cfg);
    end
    headerBitsByFrame(:, frameIndex) = headerBits;
    headerRows = reshape(headerBits, cfg.headerSymbolsPerFrame, ...
        params.MBits);
    payloadRows = reshape(payloadBitsByFrame(:, frameIndex), ...
        cfg.payloadSymbolsPerFrame, params.MBits);
    dataIndices = bi2de([headerRows; payloadRows]);
    symbols = qammod(dataIndices, params.MMod, "gray", ...
        "UnitAveragePower", true);
    dataGrid = complex(zeros(params.N, params.M));
    dataGrid(params.dataMask) = params.dataScale*symbols;
    [txGrid, ~] = addpilot(dataGrid, params.xPilot, ...
        params.nPilot, params.mPilot, params.mMax, params.nMax);
    payload = OTFS_modulation(params.N, params.M, txGrid);
    payloadBlocks(:, frameIndex) = ...
        [payload(end-params.LCp+1:end); payload];
end

payloadScale = localActiveRmsScale(payloadBlocks(:), ...
    cfg.targetPayloadTxRms);
payloadBlocks = payloadScale*payloadBlocks;

n = (0:cfg.preambleLen-1).';
preamble = cfg.preambleAmp * exp(-1j*pi*cfg.preambleRoot*n.* ...
    (n + 1)/cfg.preambleLen);
frames = [repmat(preamble, 1, cfg.superframeLength); payloadBlocks];
txSuperframe = frames(:);
if mod(cfg.txBufferFrameCount, cfg.superframeLength) ~= 0
    error("otfs_tr:IncompleteTransmitSuperframe", ...
        "txBufferFrameCount must be a multiple of superframeLength.");
end
txSignal = repmat(txSuperframe, ...
    cfg.txBufferFrameCount/cfg.superframeLength, 1);

peak = max(abs(txSignal));
peakScale = 1;
if peak > cfg.hardwareTxPeak
    peakScale = cfg.hardwareTxPeak / peak;
    txSignal = peakScale*txSignal;
    preamble = peakScale*preamble;
    payloadBlocks = peakScale*payloadBlocks;
    frames = peakScale*frames;
    txSuperframe = peakScale*txSuperframe;
end

training = struct();
training.preamble10 = preamble;
training.sampleRateHz = cfg.fsTx;
training.root = cfg.preambleRoot;

reference = struct();
reference.waveformVersion = cfg.waveformVersion;
reference.referenceMode = "unique-superframe";
reference.superframeLength = cfg.superframeLength;
reference.frameIds = (0:cfg.superframeLength-1).';
reference.payloadBitsByFrame = payloadBitsByFrame;
reference.berTestBitsByFrame = berTestBitsByFrame;
reference.application = application;
if testCaseMode
    reference.testCase = struct("version", testCase.version, ...
        "caseId", testCase.caseId, ...
        "caseCode", caseCode, ...
        "sourceFile", testCase.sourceFile);
end
reference.headerBitsByFrame = headerBitsByFrame;
reference.bitsPerFrame = berTestBitsByFrame(:, 1);
reference.bits = berTestBitsByFrame(:);
reference.txFrame = frames(:, 1);
reference.txFrames = frames;
reference.txSuperframe = txSuperframe;
reference.payloadWithCp = payloadBlocks(:, 1);
reference.payloadBlocksWithCp = payloadBlocks;
reference.frameLength10 = size(frames, 1);
reference.txBufferFrameCount = cfg.txBufferFrameCount;
reference.maxDecodedFrames = cfg.maxDecodedFrames;
reference.payloadScale = payloadScale;
reference.peakScale = peakScale;
reference.actualTxPeak = max(abs(txSignal));
reference.effectiveBitsPerFrame = cfg.berTestBitsPerFrame;
reference.payloadBitsPerFrame = cfg.payloadBitsPerFrame;
reference.applicationMappedBitsPerFrame = ...
    cfg.applicationMappedBitsPerFrame;
reference.berTestBitsPerFrame = cfg.berTestBitsPerFrame;
reference.totalEffectiveBits = numel(reference.bits);
reference.totalUniquePayloadBits = numel(reference.bits);
reference.headerMappedBits = cfg.headerMappedBits;
reference.headerSymbolsPerFrame = cfg.headerSymbolsPerFrame;
reference.preambleStart10 = 1;
reference.payloadStart10 = reference.preambleStart10 + cfg.preambleLen;
reference.zerosAheadLen = 0;
reference.zerosTailLen = 0;
end

function mode = localPayloadMode(cfg)
if isfield(cfg, "payloadMode")
    mode = cfg.payloadMode;
else
    mode = "application";
end
end

function count = localFrameCaseIdBits(cfg)
count = 0;
if isfield(cfg, "frameCaseIdBits")
    count = cfg.frameCaseIdBits;
end
end

function request = localDefaultApplicationRequest(cfg)
request = struct("protocol_version", cfg.controlProtocolVersion, ...
    "command", "start_test", ...
    "payload_text", "TEST", ...
    "equivalent_cfo_hz", cfg.equivalentDopplerHz, ...
    "options", struct("duration_seconds", ...
    cfg.defaultTransmitDurationSeconds));
end

function scale = localActiveRmsScale(x, targetRms)
active = abs(x) > 0;
if any(active)
    activeRms = sqrt(mean(abs(x(active)).^2));
else
    activeRms = 0;
end
if targetRms > 0 && activeRms > 0
    scale = targetRms / activeRms;
else
    scale = 1;
end
end
