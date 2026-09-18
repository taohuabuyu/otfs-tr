function [txSignal, reference, params, training] = ...
        otfs_tr_build_waveform(cfg)
%otfs_tr_build_waveform Build one repeated-frame OTFS transmit burst.

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

numGridSymbols = params.N * params.M;
sourceBits = randi([0, 1], numGridSymbols * params.MBits, 1);
indices = bi2de(reshape(sourceBits, numGridSymbols, params.MBits));
symbols = qammod(indices, params.MMod, "gray", ...
    "UnitAveragePower", true);
dataGrid = params.dataScale * reshape(symbols, params.N, params.M);

[txGrid, params.dataMask] = addpilot(dataGrid, params.xPilot, ...
    params.nPilot, params.mPilot, params.mMax, params.nMax);
indexGrid = reshape(indices, params.N, params.M);
dataIndices = indexGrid(params.dataMask);
reference.bitsPerFrame = reshape(de2bi(dataIndices, params.MBits), [], 1);
reference.bits = repmat(reference.bitsPerFrame, cfg.maxDecodedFrames, 1);

payload = OTFS_modulation(params.N, params.M, txGrid);
payloadWithCp = [payload(end-params.LCp+1:end); payload];
payloadScale = localActiveRmsScale(payloadWithCp, ...
    cfg.targetPayloadTxRms);
payloadWithCp = payloadScale * payloadWithCp;

n = (0:cfg.preambleLen-1).';
preamble = cfg.preambleAmp * exp(-1j*pi*cfg.preambleRoot*n.* ...
    (n + 1)/cfg.preambleLen);
frame = [preamble; payloadWithCp];
txSignal = repmat(frame, cfg.txBufferFrameCount, 1);

peak = max(abs(txSignal));
peakScale = 1;
if peak > cfg.hardwareTxPeak
    peakScale = cfg.hardwareTxPeak / peak;
    txSignal = peakScale * txSignal;
    preamble = peakScale * preamble;
    payloadWithCp = peakScale * payloadWithCp;
    frame = peakScale * frame;
end

training = struct();
training.preamble10 = preamble;
training.sampleRateHz = cfg.fsTx;
training.root = cfg.preambleRoot;

reference.txFrame = frame;
reference.payloadWithCp = payloadWithCp;
reference.frameLength10 = numel(frame);
reference.txBufferFrameCount = cfg.txBufferFrameCount;
reference.maxDecodedFrames = cfg.maxDecodedFrames;
reference.payloadScale = payloadScale;
reference.peakScale = peakScale;
reference.actualTxPeak = max(abs(txSignal));
reference.effectiveBitsPerFrame = numel(reference.bitsPerFrame);
reference.totalEffectiveBits = numel(reference.bits);
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
