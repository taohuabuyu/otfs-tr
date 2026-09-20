function [txSignal, reference, params, training] = ...
        otfs_tr_build_waveform(cfg)
%otfs_tr_build_waveform Build a repeated unique-frame OTFS superframe.

rng(cfg.randomSeed, "twister");

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
params.frameCrcBits = cfg.frameCrcBits;
params.headerRepetition = cfg.headerRepetition;
params.headerInformationBits = cfg.headerInformationBits;
params.headerCodedBits = cfg.headerCodedBits;
params.headerMappedBits = cfg.headerMappedBits;
params.headerPaddingBits = cfg.headerPaddingBits;
params.headerSymbolsPerFrame = cfg.headerSymbolsPerFrame;
params.payloadBitsPerFrame = cfg.payloadBitsPerFrame;

[~, params.dataMask] = addpilot(zeros(params.N, params.M), ...
    params.xPilot, params.nPilot, params.mPilot, params.mMax, params.nMax);
dataLinearIndices = find(params.dataMask);
params.headerLinearIndices = dataLinearIndices(1:cfg.headerSymbolsPerFrame);
params.payloadLinearIndices = dataLinearIndices(cfg.headerSymbolsPerFrame+1:end);
params.headerMask = false(params.N, params.M);
params.headerMask(params.headerLinearIndices) = true;
params.payloadMask = false(params.N, params.M);
params.payloadMask(params.payloadLinearIndices) = true;

payloadBitsByFrame = randi([0, 1], cfg.payloadBitsPerFrame, ...
    cfg.superframeLength);
headerBitsByFrame = zeros(cfg.headerMappedBits, cfg.superframeLength);
payloadBlocks = complex(zeros(params.blockLen, cfg.superframeLength));

for frameIndex = 1:cfg.superframeLength
    headerBits = otfs_tr_encode_frame_header(frameIndex-1, cfg);
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
reference.headerBitsByFrame = headerBitsByFrame;
reference.bitsPerFrame = payloadBitsByFrame(:, 1);
reference.bits = payloadBitsByFrame(:);
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
reference.effectiveBitsPerFrame = cfg.payloadBitsPerFrame;
reference.payloadBitsPerFrame = cfg.payloadBitsPerFrame;
reference.totalEffectiveBits = numel(reference.bits);
reference.totalUniquePayloadBits = numel(reference.bits);
reference.headerMappedBits = cfg.headerMappedBits;
reference.headerSymbolsPerFrame = cfg.headerSymbolsPerFrame;
reference.preambleStart10 = 1;
reference.payloadStart10 = reference.preambleStart10 + cfg.preambleLen;
reference.zerosAheadLen = 0;
reference.zerosTailLen = 0;
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
