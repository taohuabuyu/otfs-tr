function results = wide_rx_process_capture(rx20, training, params, refBits, p)
%wide_rx_process_capture Process one 20 MHz SDR capture through the OTFS RX chain.
%
% RX route:
%   20 MHz samples -> preamble coarse sync and large-CFO estimate
%   -> 20 MHz CFO compensation -> SFO correction -> low-pass filtering
%   -> decimate to 10 MHz
%   -> CP fine sync -> per-frame OTFS demodulation -> DD-pilot channel estimate
%   -> MP detection / equalization -> QAM demodulation -> BER.

rx20 = rx20(:);
params.channelTapThresholdRatio = localGetField( ...
    p, "channelTapThresholdRatio", 0.95);
params.maxChannelTaps = localGetField(p, "maxChannelTaps", Inf);
ratio = p.fsRx / p.fsTx;
if abs(ratio - round(ratio)) > 1e-12
    error("wide_rx_process_capture:InvalidRateRatio", ...
        "Only integer RX/TX sample-rate ratios are supported.");
end
ratio = round(ratio);

%% 20 MHz domain: preamble coarse synchronization and large-CFO estimate.
sync20 = localCoarseSyncAndCfoAt20Mhz(rx20, training.preamble10, p);

%% 20 MHz domain: compensate the estimated frequency offset.
nRx = (0:numel(rx20)-1).';
cfoEstimateHz = sync20.cfoEstimateHz;
rx20CfoCorrected = rx20 .* exp(-1j*2*pi*cfoEstimateHz/p.fsRx*nRx);

%% 20 MHz domain: estimate frame-spacing drift and correct SFO.
[rx20SfoCorrected, sfoInfo] = otfs_tr_correct_sfo( ...
    rx20CfoCorrected, training.preamble10, params, p);

%% 20 MHz domain: optional low-pass filtering before returning to 10 MHz.
% In this project the transmitted OTFS waveform already occupies the 10 MHz
% processing bandwidth. Keep this switch visible so hardware captures can be
% compared with and without FIR filtering; excessive filtering can distort the
% edge subcarriers and raise BER.
if localGetField(p, "enableRxLowpassFilter", false)
    rx20Filtered = localLowpassBeforeDecimation(rx20SfoCorrected, ratio);
else
    rx20Filtered = rx20SfoCorrected;
end

%% 10 MHz domain: decimate using the phase implied by 20 MHz coarse sync.
forcedPhase = mod(sync20.preambleStart20 - 1, ratio) + 1;
rx10 = rx20Filtered(forcedPhase:ratio:end);

%% 10 MHz domain: search the full capture for every complete frame.
[payloadStarts, frameInfo, detectedPreambleCount] = ...
    localFineSyncOtfsFramesAt10Mhz( ...
    rx10, training.preamble10, forcedPhase, params, p);
for idx = 1:numel(frameInfo)
    frameInfo(idx).cfoEstimateHz = cfoEstimateHz;
end

%% Per-frame OTFS demodulation, DD-channel estimation, detection, and BER.
maxFrames = min(localGetField(p, "maxDecodedFrames", Inf), ...
    numel(payloadStarts));
ber = nan(maxFrames, 1);
frameDiagnostics = repmat(localEmptyFrameDiagnostics(params, refBits), ...
    maxFrames, 1);
for frameIdx = 1:maxFrames
    frameStart = payloadStarts(frameIdx);
    frameEnd = frameStart + params.blockLen - 1;
    if frameStart < 1 || frameEnd > numel(rx10)
        continue;
    end

    rxBlock = rx10(frameStart:frameEnd);
    rxBlock = localApplyPreambleAndCpCorrections( ...
        rxBlock, frameInfo(frameIdx), p);
    [ber(frameIdx), frameDiagnostics(frameIdx)] = ...
        localDetectOtfsFrameAndMeasureBer(rxBlock, params, refBits, p);
end

%% Return both final BER and intermediate signals needed for diagnosis plots.
results = struct();
results.scenarioName = p.scenarioName;
results.ber = ber;
results.meanBer = mean(ber, "omitnan");
results.minBer = min(ber, [], "omitnan");
results.maxBer = max(ber, [], "omitnan");
results.validFrames = sum(~isnan(ber));
results.detectedPreambles = detectedPreambleCount;
results.acceptedFrameStarts = numel(payloadStarts);
results.attemptedFrames = maxFrames;
results.payloadStarts10 = payloadStarts;
results.rx20 = rx20;
results.rx20CfoCorrected = rx20CfoCorrected;
if sfoInfo.applied
    results.rx20SfoCorrected = rx20SfoCorrected;
else
    results.rx20SfoCorrected = complex(zeros(0, 1));
end
results.rx20Filtered = rx20Filtered;
results.rx10 = rx10;
results.coarseSync20 = sync20;
results.sfoInfo = sfoInfo;
results.frameInfo = frameInfo;
results.frameDiagnostics = frameDiagnostics;
if isempty(frameInfo)
    results.syncInfo = struct();
else
    results.syncInfo = frameInfo(1);
end
results.cfoEstimateHz = cfoEstimateHz;
end

function sync20 = localCoarseSyncAndCfoAt20Mhz(rx20, preamble10, p)
% Upsample the known 10 MHz preamble to the 20 MHz RX grid, then search CFO.
preamble10 = preamble10(:);
ratio = round(p.fsRx / p.fsTx);
if ratio == 1
    preamble20 = preamble10;
else
    preamble20 = resample(preamble10, ratio, 1);
end

sync20 = struct();
sync20.cfoEstimateHz = p.cfoSearchHz(1);
sync20.preambleStart20 = NaN;
sync20.preambleLength20 = numel(preamble20);
sync20.metric = zeros(0, 1);
searchLength = min(numel(rx20), ...
    localGetField(p, "cfoSearchWindowSamples20", numel(rx20)));
rx20Search = rx20(1:searchLength);
sync20.searchLength20 = searchLength;

% First pass: wide, coarse grid for large CFO capture.
[coarseHz, coarseScore, ~, coarseScores] = localSearchCfoGrid( ...
    rx20Search, preamble20, p.cfoSearchHz(:), p);

% Second pass: fine grid around the coarse maximum. This avoids leaving a
% large residual CFO when the true offset is off the 50 kHz coarse grid.
fineSpanHz = localGetField(p, "cfoFineSearchSpanHz", 50e3);
fineStepHz = localGetField(p, "cfoFineSearchStepHz", 1e3);
fineGridHz = (coarseHz - fineSpanHz:fineStepHz:coarseHz + fineSpanHz).';
[fineHz, fineScore, fineStart20, fineScores, fineMetric] = ...
    localSearchCfoGrid(rx20Search, preamble20, fineGridHz, p);

sync20.cfoEstimateHz = fineHz;
sync20.preambleStart20 = fineStart20;
sync20.metric = fineMetric;
sync20.bestScore = fineScore;
sync20.coarseCfoEstimateHz = coarseHz;
sync20.coarseBestScore = coarseScore;
sync20.cfoSearchHz = p.cfoSearchHz(:);
sync20.cfoScores = coarseScores;
sync20.cfoFineSearchHz = fineGridHz;
sync20.cfoFineScores = fineScores;
sync20.preamble20 = preamble20;
end

function [bestHz, bestScore, bestStart20, scores, bestMetric] = ...
        localSearchCfoGrid(rx20, preamble20, cfoGridHz, p)
n = (0:numel(rx20)-1).';
bestScore = -Inf;
bestHz = cfoGridHz(1);
bestStart20 = NaN;
bestMetric = zeros(0, 1);
scores = nan(numel(cfoGridHz), 1);

for idx = 1:numel(cfoGridHz)
    cfoHz = cfoGridHz(idx);
    candidate = rx20 .* exp(-1j*2*pi*cfoHz/p.fsRx*n);
    [metric, startIdx, score] = localPreambleCorrelationMetric( ...
        candidate, preamble20, p.preamblePeakThreshold);
    scores(idx) = score;
    if score > bestScore
        bestScore = score;
        bestHz = cfoHz;
        bestStart20 = startIdx;
        bestMetric = metric;
    end
end
end

function value = localGetField(s, name, defaultValue)
if isfield(s, name) && ~isempty(s.(name))
    value = s.(name);
else
    value = defaultValue;
end
end

function [metric, startIdx, score] = localPreambleCorrelationMetric( ...
        rx, preamble, relativeThreshold)
% Normalized sliding correlation. The first strong peak is the burst start.
rx = rx(:);
preamble = preamble(:);
refLen = numel(preamble);
if numel(rx) < refLen
    metric = zeros(0, 1);
    startIdx = NaN;
    score = -Inf;
    return;
end

corrVals = conv(rx, conj(flipud(preamble)), "valid");
refEnergy = sum(abs(preamble).^2);
energyPrefix = cumsum([0; abs(rx).^2]);
rxEnergy = energyPrefix(refLen+1:end) - energyPrefix(1:end-refLen);
metric = abs(corrVals).^2 ./ (rxEnergy * refEnergy + eps);
[score, maxIdx] = max(metric);
threshold = max(relativeThreshold * score, ...
    median(metric) + 8 * median(abs(metric - median(metric))));
candidateIdx = find(metric >= threshold);
candidateIdx = candidateIdx(candidateIdx > 1 & candidateIdx < numel(metric));
isPeak = metric(candidateIdx) >= metric(candidateIdx - 1) & ...
    metric(candidateIdx) >= metric(candidateIdx + 1);
peaks = candidateIdx(isPeak);
if isempty(peaks)
    startIdx = maxIdx;
else
    startIdx = peaks(1);
end
end

function rx20Filtered = localLowpassBeforeDecimation(rx20, ratio)
% FIR low-pass filtering suppresses out-of-band content before decimation.
if ratio <= 1
    rx20Filtered = rx20(:);
    return;
end

filterOrder = 96;
cutoffNormalized = min(0.99 / ratio, 0.99);
b = fir1(filterOrder, cutoffNormalized);
rx20Filtered = filter(b, 1, rx20(:));

% Compensate the linear-phase FIR delay so timing indices remain readable.
delay = filterOrder / 2;
if delay > 0 && numel(rx20Filtered) > delay
    rx20Filtered = [rx20Filtered(delay+1:end); complex(zeros(delay, 1))];
end
end

function [payloadStarts, frameInfo, detectedPreambleCount] = ...
        localFineSyncOtfsFramesAt10Mhz( ...
        rx10, preamble10, samplePhase, params, p)
% Detect every preamble in an arbitrary continuous-capture window.
frameLen = numel(preamble10) + params.blockLen;
[metric, ~, bestScore] = localPreambleCorrelationMetric( ...
    rx10, preamble10, p.preamblePeakThreshold);
absoluteThreshold = localGetField(p, "framePreambleMinScore", 0);
robustThreshold = median(metric) + ...
    8*median(abs(metric-median(metric)));
threshold = max([absoluteThreshold, ...
    p.preamblePeakThreshold*bestScore, robustThreshold]);
candidateIdx = find(metric >= threshold);
candidateIdx = candidateIdx(candidateIdx > 1 & ...
    candidateIdx < numel(metric));
isPeak = metric(candidateIdx) >= metric(candidateIdx-1) & ...
    metric(candidateIdx) >= metric(candidateIdx+1);
preambleStarts = localEnforcePeakSpacing(candidateIdx(isPeak), metric, ...
    max(1, floor(localGetField(p, "preambleMinSpacingRatio", 0.8) * ...
    frameLen)));
complete = preambleStarts + frameLen - 1 <= numel(rx10);
preambleStarts = preambleStarts(complete);
detectedPreambleCount = numel(preambleStarts);

payloadStarts = zeros(0, 1);
frameInfo = repmat(localEmptyFrameInfo(), 0, 1);
refEnergy = sum(abs(preamble10).^2);
for idx = 1:numel(preambleStarts)
    preStart = preambleStarts(idx);
    preEnd = preStart + numel(preamble10) - 1;
    rxPre = rx10(preStart:preEnd);
    timingScore = abs(sum(conj(preamble10) .* rxPre))^2 / ...
        (sum(abs(rxPre).^2) * refEnergy + eps);
    residualCfoHz = localEstimateResidualCfoFromPreamble( ...
        rxPre, preamble10, p.fsTx);

    % Preamble channel estimate removes common amplitude/phase per frame.
    channelEstimate = (preamble10' * rxPre) / refEnergy;
    if abs(channelEstimate) < eps
        channelEstimate = 1;
    end

    coarsePayloadStart = preEnd + 1;
    [payloadStart, cpScore, cpCfoHz] = localFineSyncWithOtfsCp( ...
        rx10, coarsePayloadStart, params, p);

    info = localEmptyFrameInfo();
    info.preambleStart10 = preStart;
    info.trainStart10 = preStart;
    info.payloadStart10 = payloadStart;
    info.samplePhase = samplePhase;
    info.timingScore = timingScore;
    info.channelEstimate = channelEstimate;
    info.phaseEstimateRad = angle(channelEstimate);
    info.cpTimingScore = cpScore;
    info.preambleResidualCfoHz = residualCfoHz;
    info.cpCfoEstimateHz = cpCfoHz;
    if p.applyCpCfoCorrection
        info.cpCfoHz = cpCfoHz;
    else
        info.cpCfoHz = 0;
    end
    info.cpFineOffset = payloadStart - coarsePayloadStart;
    info.cpAccepted = cpScore >= p.cpFineMinScore;

    if timingScore >= absoluteThreshold && info.cpAccepted
        payloadStarts(end+1, 1) = payloadStart; %#ok<AGROW>
        frameInfo(end+1, 1) = info; %#ok<AGROW>
    end
end
end

function peaks = localEnforcePeakSpacing(candidateIdx, metric, minSpacing)
peaks = zeros(0, 1);
for index = 1:numel(candidateIdx)
    candidate = candidateIdx(index);
    if isempty(peaks) || candidate-peaks(end) >= minSpacing
        peaks(end+1, 1) = candidate; %#ok<AGROW>
    elseif metric(candidate) > metric(peaks(end))
        peaks(end) = candidate;
    end
end
end

function [payloadStart, bestScore, cfoHz] = localFineSyncWithOtfsCp( ...
        rx10, coarseStart, params, p)
% The CP repeats the end of the OTFS block, so CP/tail correlation refines timing.
searchStart = max(1, coarseStart - p.cpFineSearchRadius);
searchEnd = min(numel(rx10) - params.blockLen + 1, ...
    coarseStart + p.cpFineSearchRadius);
payloadStart = coarseStart;
bestScore = NaN;
cfoHz = 0;
if searchEnd < searchStart
    return;
end

bestScore = -Inf;
bestCorr = 0;
coarseScore = NaN;
for candidateStart = searchStart:searchEnd
    cp = rx10(candidateStart:candidateStart+params.LCp-1);
    tail = rx10(candidateStart+params.Nfft: ...
        candidateStart+params.Nfft+params.LCp-1);
    corrVal = sum(conj(cp) .* tail);
    metric = abs(corrVal)^2 / (sum(abs(cp).^2) * ...
        sum(abs(tail).^2) + eps);
    if candidateStart == coarseStart
        coarseScore = metric;
    end
    if metric > bestScore
        bestScore = metric;
        bestCorr = corrVal;
        payloadStart = candidateStart;
    end
end

acceptFineStart = bestScore >= p.cpFineMinScore && ...
    (~isfinite(coarseScore) || payloadStart == coarseStart || ...
    bestScore >= p.cpFineRelativeMargin * coarseScore);
if ~acceptFineStart
    payloadStart = coarseStart;
    cfoHz = 0;
else
    cfoHz = angle(bestCorr) * p.fsTx / (2*pi*params.Nfft);
end
end

function rxBlock = localApplyPreambleAndCpCorrections(rxBlock, frameInfo, p)
% Apply residual CP CFO if enabled, then remove preamble-estimated gain/phase.
rxBlock = rxBlock(:);
n = (0:numel(rxBlock)-1).';
if localGetField(p, "applyPreambleResidualCfoCorrection", false) && ...
        isfield(frameInfo, "preambleResidualCfoHz") && ...
        isfinite(frameInfo.preambleResidualCfoHz)
    rxBlock = rxBlock .* exp(-1j*2*pi* ...
        frameInfo.preambleResidualCfoHz/p.fsTx*n);
end
if isfield(frameInfo, "cpCfoHz") && isfinite(frameInfo.cpCfoHz)
    rxBlock = rxBlock .* exp(-1j*2*pi*frameInfo.cpCfoHz/p.fsTx*n);
end
if isfield(frameInfo, "channelEstimate") && ...
        abs(frameInfo.channelEstimate) > eps
    rxBlock = rxBlock / frameInfo.channelEstimate;
end
end

function [ber, diag] = localDetectOtfsFrameAndMeasureBer( ...
        rxBlock, params, refBits, p)
% OTFS demodulation -> DD-pilot channel estimate -> MP detection -> BER.
diag = localEmptyFrameDiagnostics(params, refBits);
[rxBlock, frameResidualCfoHz, frameResidualCfoScore] = ...
    localRefineResidualCfoWithDdPilot(rxBlock, params, p);
diag.frameResidualCfoHz = frameResidualCfoHz;
diag.frameResidualCfoScore = frameResidualCfoScore;
rxData = rxBlock(params.LCp+1:end);
rxGrid = OTFS_demodulation(params.N, params.M, rxData);
diag.rxGrid = rxGrid;

% The single DD pilot gives a common phase reference before channel estimation.
pilotRx = rxGrid(params.nPilot, params.mPilot);
diag.pilotRx = pilotRx;
if abs(pilotRx) < eps
    ber = NaN;
    return;
end
theta = angle(pilotRx * conj(params.xPilot));
diag.phaseCorrectionRad = theta;
rxGrid = rxGrid * exp(-1j * theta);

% Estimate sparse delay-Doppler channel taps from the pilot guard area.
[delayTaps, dopplerTaps, chanCoef, taps, ~, ~, sigmaEst] = ...
    channel_estimation_for_ZF(rxGrid, params.mPilot, params.nPilot, ...
    params.mMax, params.nMax, params.xPilot, params.channelTapThresholdRatio);
diag.delayTaps = delayTaps;
diag.dopplerTaps = dopplerTaps;
diag.chanCoef = chanCoef;
diag.taps = taps;
diag.sigmaEst = sigmaEst;
if taps <= 0 || isempty(chanCoef) || ~isfinite(sigmaEst)
    ber = NaN;
    return;
end
[delayTaps, dopplerTaps, chanCoef, taps] = localKeepStrongestTaps( ...
    delayTaps, dopplerTaps, chanCoef, params.maxChannelTaps);
diag.delayTapsUsed = delayTaps;
diag.dopplerTapsUsed = dopplerTaps;
diag.chanCoefUsed = chanCoef;
diag.tapsUsed = taps;

% MP detection uses the estimated DD-domain sparse channel to recover symbols.
sigmaEst = max(sigmaEst, 1e-8);
xEst = OTFS_MP_Detection(params.N, params.M, params.MMod, taps, ...
    delayTaps, dopplerTaps, chanCoef, sigmaEst, rxGrid);
xEst = reshape(xEst, params.N, params.M);
dataSymbols = xEst(params.dataMask == 1);
diag.detectedGrid = xEst;
diag.dataSymbols = dataSymbols;

if isfield(params, "dataScale") && params.dataScale ~= 0 && ...
        params.dataScale ~= 1
    dataSymbols = dataSymbols / params.dataScale;
end
demapped = qamdemod(dataSymbols, params.MMod, "gray", ...
    "UnitAveragePower", true);
estimatedBits = reshape(de2bi(demapped, params.MBits), [], 1);
compareLen = min(numel(estimatedBits), numel(refBits));
bitErrors = xor(estimatedBits(1:compareLen), refBits(1:compareLen));
ber = sum(bitErrors) / compareLen;

diag.estimatedBits = estimatedBits(1:compareLen);
diag.refBits = refBits(1:compareLen);
diag.bitErrors = bitErrors;
diag.errorBitPositions = find(bitErrors);
end

function [rxBlockBest, bestCfoHz, bestScore] = ...
        localRefineResidualCfoWithDdPilot(rxBlock, params, p)
% Small residual CFO creates a phase slope over one OTFS block and spreads the
% pilot in Doppler. Pick the CFO that makes the pilot guard region most
% concentrated before running channel estimation and MP detection.
cfoGridHz = localGetField(p, "frameResidualCfoSearchHz", 0);
cfoGridHz = cfoGridHz(:).';
rxBlock = rxBlock(:);
n = (0:numel(rxBlock)-1).';
bestScore = -Inf;
bestCfoHz = 0;
rxBlockBest = rxBlock;

for cfoHz = cfoGridHz
    candidateBlock = rxBlock .* exp(-1j*2*pi*cfoHz/p.fsTx*n);
    rxData = candidateBlock(params.LCp+1:end);
    rxGrid = OTFS_demodulation(params.N, params.M, rxData);
    score = localPilotConcentrationScore(rxGrid, params);
    if score > bestScore
        bestScore = score;
        bestCfoHz = cfoHz;
        rxBlockBest = candidateBlock;
    end
end
end

function score = localPilotConcentrationScore(rxGrid, params)
[N, M] = size(rxGrid);

rowStart = max(1, params.nPilot - params.nMax);
rowEnd   = min(N, params.nPilot + params.nMax);

colStart = max(1, params.mPilot - params.mMax);
colEnd   = min(M, params.mPilot + params.mMax);

guard = rxGrid(rowStart:rowEnd, colStart:colEnd);
% colStart = max(1, params.mPilot);
% colEnd = min(params.M, params.mPilot + params.mMax);
% guard = rxGrid(:, colStart:colEnd);
pilotPeak = abs(rxGrid(params.nPilot, params.mPilot))^2;
guardEnergy = sum(abs(guard(:)).^2);
score = pilotPeak / (guardEnergy + eps);
end

function diag = localEmptyFrameDiagnostics(params, refBits)
diag = struct();
diag.rxGrid = complex(nan(params.N, params.M));
diag.detectedGrid = complex(nan(params.N, params.M));
diag.pilotRx = NaN;
diag.phaseCorrectionRad = NaN;
diag.delayTaps = [];
diag.dopplerTaps = [];
diag.chanCoef = [];
diag.taps = 0;
diag.tapsUsed = 0;
diag.sigmaEst = NaN;
diag.delayTapsUsed = [];
diag.dopplerTapsUsed = [];
diag.chanCoefUsed = [];
diag.dataSymbols = complex(zeros(0, 1));
diag.estimatedBits = zeros(0, 1);
diag.refBits = refBits(:);
diag.bitErrors = false(numel(refBits), 1);
diag.errorBitPositions = zeros(0, 1);
diag.frameResidualCfoHz = 0;
diag.frameResidualCfoScore = NaN;
end

function [delayTaps, dopplerTaps, chanCoef, taps] = localKeepStrongestTaps( ...
        delayTaps, dopplerTaps, chanCoef, maxChannelTaps)
if ~isfinite(maxChannelTaps) || numel(chanCoef) <= maxChannelTaps
    taps = numel(chanCoef);
    return;
end
[~, order] = sort(abs(chanCoef), "descend");
order = order(1:maxChannelTaps);
delayTaps = delayTaps(order);
dopplerTaps = dopplerTaps(order);
chanCoef = chanCoef(order);
taps = numel(order);
end

function info = localEmptyFrameInfo()
info = struct("preambleStart10", NaN, "trainStart10", NaN, ...
    "payloadStart10", NaN, "samplePhase", NaN, "timingScore", NaN, ...
    "channelEstimate", 1, "phaseEstimateRad", NaN, ...
    "cpTimingScore", NaN, "preambleResidualCfoHz", 0, ...
    "cpCfoEstimateHz", 0, "cpCfoHz", 0, ...
    "cpFineOffset", NaN, "cfoEstimateHz", NaN, ...
    "residualCfoHz", 0, "cpAccepted", false);
end

function residualCfoHz = localEstimateResidualCfoFromPreamble( ...
        rxPre, preamble10, fsTx)
% Residual CFO appears as a linear phase slope across the known preamble.
phaseError = unwrap(angle(rxPre(:) .* conj(preamble10(:))));
n = (0:numel(phaseError)-1).';
valid = isfinite(phaseError);
if nnz(valid) < 8
    residualCfoHz = 0;
    return;
end
coef = polyfit(n(valid), phaseError(valid), 1);
residualCfoHz = coef(1) * fsTx / (2*pi);
end
