function results = wide_rx_process_capture(rx20, training, params, referenceInput, p)
%wide_rx_process_capture Process one 20 MHz SDR capture through the OTFS RX chain.
%
% RX route:
%   20 MHz samples -> preamble coarse sync and large-CFO estimate
%   -> 20 MHz CFO compensation -> SFO correction -> low-pass filtering
%   -> provisional 10 MHz decimation -> DD-pilot fractional timing estimate
%   -> correct the 20 MHz IQ -> final 10 MHz decimation
%   -> CP fine sync -> per-frame OTFS demodulation -> DD-pilot channel estimate
%   -> MP detection / equalization -> QAM demodulation -> BER.

rx20 = rx20(:);
params.channelTapThresholdRatio = localGetField( ...
    p, "channelTapThresholdRatio", 0.95);
params.maxChannelTaps = localGetField(p, "maxChannelTaps", Inf);
reference = localNormalizeReference(referenceInput);
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

%% Estimate residual fractional timing from known DD pilots only.
[provisionalPayloadStarts, provisionalFrameInfo, ~] = ...
    localFineSyncOtfsFramesAt10Mhz( ...
    rx10, training.preamble10, forcedPhase, params, p);
fractionalTimingInfo = localEstimateFractionalTiming( ...
    rx10, provisionalPayloadStarts, provisionalFrameInfo, ...
    training.preamble10, params, p);
if fractionalTimingInfo.applied
    rx20FractionalTimingCorrected = localFractionalShift( ...
        rx20Filtered, ratio*fractionalTimingInfo.selectedOffsetSamples10);
    rx10 = rx20FractionalTimingCorrected(forcedPhase:ratio:end);
else
    rx20FractionalTimingCorrected = complex(zeros(0, 1));
end

%% 10 MHz domain: search the corrected capture for every complete frame.
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
frameDiagnostics = repmat(localEmptyFrameDiagnostics(params), ...
    maxFrames, 1);
seenFrameIds = false(max(1, reference.superframeLength), 1);
previousFrameId = NaN;
headerCrcFailures = 0;
duplicateFrameIds = 0;
sequenceDiscontinuities = 0;
for frameIdx = 1:maxFrames
    frameStart = payloadStarts(frameIdx);
    frameEnd = frameStart + params.blockLen - 1;
    if frameStart < 1 || frameEnd > numel(rx10)
        continue;
    end

    rxBlock = rx10(frameStart:frameEnd);
    rxBlock = localApplyPreambleAndCpCorrections( ...
        rxBlock, frameInfo(frameIdx), p);
    frameSettings = p;
    fallbackApplied = localShouldUseDdPilotCfoFallback( ...
        frameInfo(frameIdx), p);
    if fallbackApplied
        frameSettings.frameResidualCfoSearchHz = localGetField( ...
            p, "ddPilotResidualCfoSearchHz", -3000:100:3000);
    end
    frameSettings.ddPilotResidualCfoFallbackApplied = fallbackApplied;
    [ber(frameIdx), frameDiagnostics(frameIdx)] = ...
        localDetectOtfsFrameAndMeasureBer( ...
        rxBlock, params, reference, frameSettings);
    if reference.mode == "unique-superframe"
        if ~frameDiagnostics(frameIdx).headerValid
            headerCrcFailures = headerCrcFailures + 1;
            continue;
        end
        frameId = frameDiagnostics(frameIdx).frameId;
        if seenFrameIds(frameId+1)
            frameDiagnostics(frameIdx).duplicateFrameId = true;
            duplicateFrameIds = duplicateFrameIds + 1;
            ber(frameIdx) = NaN;
            continue;
        end
        seenFrameIds(frameId+1) = true;
        if isfinite(previousFrameId) && ...
                frameId ~= mod(previousFrameId+1, reference.superframeLength)
            frameDiagnostics(frameIdx).sequenceDiscontinuity = true;
            sequenceDiscontinuities = sequenceDiscontinuities + 1;
        end
        previousFrameId = frameId;
    end
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
results.rx20FractionalTimingCorrected = rx20FractionalTimingCorrected;
results.rx10 = rx10;
results.coarseSync20 = sync20;
results.sfoInfo = sfoInfo;
results.fractionalTimingInfo = fractionalTimingInfo;
results.frameInfo = frameInfo;
results.frameDiagnostics = frameDiagnostics;
results.referenceMode = reference.mode;
results.frameIds = [frameDiagnostics.frameId].';
results.headerCrcFailures = headerCrcFailures;
results.duplicateFrameIds = duplicateFrameIds;
results.sequenceDiscontinuities = sequenceDiscontinuities;
results.referenceAlignmentPass = reference.mode == "legacy-repeated" || ...
    (headerCrcFailures == 0 && duplicateFrameIds == 0 && ...
    sequenceDiscontinuities == 0 && any(isfinite(ber)));
if isempty(frameInfo)
    results.syncInfo = struct();
else
    results.syncInfo = frameInfo(1);
end
results.cfoEstimateHz = cfoEstimateHz;
end

function useFallback = localShouldUseDdPilotCfoFallback(frameInfo, p)
useFallback = false;
if ~localGetField(p, "enableDdPilotResidualCfoFallback", false)
    return;
end
triggerHz = localGetField(p, "ddPilotResidualCfoTriggerHz", 500);
cpRejected = isfield(frameInfo, "cpCorrectionAccepted") && ...
    ~frameInfo.cpCorrectionAccepted;
cpNearZeroButPreambleIsNot = abs(frameInfo.cpCfoEstimateHz) < triggerHz && ...
    abs(frameInfo.preambleResidualCfoHz) >= triggerHz;
useFallback = cpRejected || cpNearZeroButPreambleIsNot;
end

function info = localEstimateFractionalTiming( ...
        rx10, payloadStarts, frameInfo, preamble10, params, p)
% Select a sub-sample phase from the known DD pilot, then refine it locally
% with the known preamble. Neither score uses payload reference bits.
searchGrid = localGetField(p, "fractionalTimingSearchSamples10", 0);
searchGrid = searchGrid(:);
info = struct("enabled", localGetField( ...
    p, "enableFractionalTimingCompensation", false), ...
    "applied", false, "status", "disabled", ...
    "searchGridSamples10", searchGrid, ...
    "concentrationScores", nan(size(searchGrid)), ...
    "preambleScores", nan(size(searchGrid)), ...
    "pilotSelectedOffsetSamples10", 0, ...
    "selectedOffsetSamples10", 0, "baselineScore", NaN, ...
    "bestScore", NaN, "improvementRatio", NaN, ...
    "estimationFrames", 0);
if ~info.enabled
    return;
end
if isempty(payloadStarts)
    info.status = "no-complete-frames";
    return;
end

frameLimit = min(numel(payloadStarts), localGetField( ...
    p, "fractionalTimingEstimationFrames", 20));
scoreMatrix = nan(frameLimit, numel(searchGrid));
preambleScoreMatrix = nan(frameLimit, numel(searchGrid));
preamble10 = preamble10(:);
preambleEnergy = sum(abs(preamble10).^2);
for gridIndex = 1:numel(searchGrid)
    candidateRx10 = localFractionalShift(rx10, searchGrid(gridIndex));
    for frameIndex = 1:frameLimit
        firstSample = payloadStarts(frameIndex);
        lastSample = firstSample + params.blockLen - 1;
        if firstSample < 1 || lastSample > numel(candidateRx10)
            continue;
        end
        candidateBlock = candidateRx10(firstSample:lastSample);
        rxData = candidateBlock(params.LCp+1:end);
        rxGrid = OTFS_demodulation(params.N, params.M, rxData);
        scoreMatrix(frameIndex, gridIndex) = ...
            localPilotConcentrationScore(rxGrid, params);
        preambleStart = frameInfo(frameIndex).preambleStart10;
        preambleEnd = preambleStart + numel(preamble10) - 1;
        if preambleStart >= 1 && preambleEnd <= numel(candidateRx10)
            candidatePreamble = candidateRx10(preambleStart:preambleEnd);
            preambleScoreMatrix(frameIndex, gridIndex) = ...
                abs(preamble10' * candidatePreamble)^2 / ...
                (preambleEnergy*sum(abs(candidatePreamble).^2) + eps);
        end
    end
end
info.concentrationScores = median(scoreMatrix, 1, "omitnan").';
info.preambleScores = median(preambleScoreMatrix, 1, "omitnan").';
info.estimationFrames = sum(any(isfinite(scoreMatrix), 2));
zeroIndex = find(abs(searchGrid) < 10*eps, 1, "first");
info.baselineScore = info.concentrationScores(zeroIndex);
[info.bestScore, bestIndex] = max(info.concentrationScores);
if ~isfinite(info.bestScore) || ~isfinite(info.baselineScore)
    info.status = "insufficient-pilot-observations";
    return;
end
info.pilotSelectedOffsetSamples10 = searchGrid(bestIndex);
info.improvementRatio = info.bestScore / max(info.baselineScore, eps);
refineRadius = 0.03;
refineMask = abs(searchGrid-info.pilotSelectedOffsetSamples10) <= ...
    refineRadius + 10*eps & isfinite(info.preambleScores);
refineIndices = find(refineMask);
if isempty(refineIndices)
    selectedIndex = bestIndex;
else
    [~, localIndex] = max(info.preambleScores(refineIndices));
    selectedIndex = refineIndices(localIndex);
end
info.selectedOffsetSamples10 = searchGrid(selectedIndex);
minimumRatio = localGetField(p, ...
    "fractionalTimingMinImprovementRatio", 1.01);
if abs(info.selectedOffsetSamples10) < 10*eps
    info.status = "zero-offset-selected";
elseif info.improvementRatio < minimumRatio
    info.status = "improvement-below-threshold";
    info.selectedOffsetSamples10 = 0;
else
    info.applied = true;
    info.status = "applied";
end
end

function shifted = localFractionalShift(signal, offsetSamples)
% PCHIP avoids the strong passband distortion seen with the optional LPF.
signal = signal(:);
sampleIndex = (1:numel(signal)).';
shifted = interp1(sampleIndex, signal, sampleIndex + offsetSamples, ...
    "pchip", 0);
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
    [payloadStart, cpScore, cpCfoHz, cpCorrectionAccepted] = ...
        localFineSyncWithOtfsCp( ...
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
    info.cpCorrectionAccepted = cpCorrectionAccepted;
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

function [payloadStart, bestScore, cfoHz, correctionAccepted] = ...
        localFineSyncWithOtfsCp( ...
        rx10, coarseStart, params, p)
% The CP repeats the end of the OTFS block, so CP/tail correlation refines timing.
searchStart = max(1, coarseStart - p.cpFineSearchRadius);
searchEnd = min(numel(rx10) - params.blockLen + 1, ...
    coarseStart + p.cpFineSearchRadius);
payloadStart = coarseStart;
bestScore = NaN;
cfoHz = 0;
correctionAccepted = false;
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
    correctionAccepted = true;
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
        rxBlock, params, reference, p)
% OTFS demodulation -> DD-pilot channel estimate -> MP detection -> BER.
diag = localEmptyFrameDiagnostics(params);
[rxBlock, frameResidualCfoHz, frameResidualCfoScore] = ...
    localRefineResidualCfoWithDdPilot(rxBlock, params, p);
diag.frameResidualCfoHz = frameResidualCfoHz;
diag.frameResidualCfoScore = frameResidualCfoScore;
diag.ddPilotResidualCfoFallbackApplied = localGetField( ...
    p, "ddPilotResidualCfoFallbackApplied", false);
rxData = rxBlock(params.LCp+1:end);
diag.frameDcEstimate = mean(rxData);
if localGetField(p, "enablePerFrameDcRemoval", false)
    rxData = rxData-diag.frameDcEstimate;
    diag.frameDcRemovalApplied = true;
end
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
[xEst, xPosteriorMean, decisionConfidence, xObservation] = ...
    OTFS_MP_Detection( ...
    params.N, params.M, params.MMod, taps, ...
    delayTaps, dopplerTaps, chanCoef, sigmaEst, rxGrid);
xEst = reshape(xEst, params.N, params.M);
xPosteriorMean = reshape(xPosteriorMean, params.N, params.M);
xObservation = reshape(xObservation, params.N, params.M);
decisionConfidence = reshape(decisionConfidence, params.N, params.M);
[xObservationCorrected, xEstCorrected, rowBiasInfo] = ...
    localCorrectStructuredRowBias(xObservation, xEst, params, p);
[sigmaEffective, noiseInfo] = localCalibrateMpNoiseVariance( ...
    xObservationCorrected, xEstCorrected, chanCoef, sigmaEst, params, p);
if noiseInfo.applied
    [xEst, xPosteriorMean, decisionConfidence, xObservation] = ...
        OTFS_MP_Detection( ...
        params.N, params.M, params.MMod, taps, ...
        delayTaps, dopplerTaps, chanCoef, sigmaEffective, rxGrid);
    xEst = reshape(xEst, params.N, params.M);
    xPosteriorMean = reshape(xPosteriorMean, params.N, params.M);
    xObservation = reshape(xObservation, params.N, params.M);
    decisionConfidence = reshape(decisionConfidence, params.N, params.M);
    [xObservationCorrected, xEstCorrected, rowBiasInfo] = ...
        localCorrectStructuredRowBias(xObservation, xEst, params, p);
end
xObservationRaw = xObservation;
xObservation = xObservationCorrected;
xEst = xEstCorrected;
dataSymbols = xEst(params.dataMask == 1);
posteriorMeanDataSymbols = xPosteriorMean(params.dataMask == 1);
softDataSymbols = xObservation(params.dataMask == 1);
dataDecisionConfidence = decisionConfidence(params.dataMask == 1);
diag.detectedGrid = xEst;
diag.posteriorMeanGrid = xPosteriorMean;
diag.softDetectedGrid = xObservation;
diag.rawSoftDetectedGrid = xObservationRaw;
diag.rowBiasCorrectionApplied = rowBiasInfo.applied;
diag.rowBiasAppliedRows = rowBiasInfo.appliedRows;
diag.rowBiasByRow = rowBiasInfo.biasByRow;
diag.rowBiasImprovementRatioByRow = rowBiasInfo.improvementRatioByRow;
diag.rowBiasCoherenceByRow = rowBiasInfo.coherenceByRow;
diag.sigmaEffective = sigmaEffective;
diag.mpNoiseCalibrationApplied = noiseInfo.applied;
diag.mpNoiseCalibrationRatio = noiseInfo.ratio;
diag.decisionDirectedSigmaEqualized = noiseInfo.equalizedVariance;
diag.dataSymbols = dataSymbols;
diag.softDataSymbols = softDataSymbols;
diag.posteriorMeanDataSymbols = posteriorMeanDataSymbols;
diag.dataDecisionConfidence = dataDecisionConfidence;
diag.meanDecisionConfidence = mean(dataDecisionConfidence, "omitnan");
diag.minimumDecisionConfidence = min(dataDecisionConfidence, [], "omitnan");

if isfield(params, "dataScale") && params.dataScale ~= 0 && ...
        params.dataScale ~= 1
    dataSymbols = dataSymbols / params.dataScale;
    softDataSymbols = softDataSymbols / params.dataScale;
end

demapped = qamdemod(dataSymbols, params.MMod, "gray", ...
    "UnitAveragePower", true);
demappedRows = de2bi(demapped, params.MBits);
if reference.mode == "unique-superframe"
    if ~isfield(params, "headerSymbolsPerFrame") || ...
            size(demappedRows, 1) <= params.headerSymbolsPerFrame
        ber = NaN;
        return;
    end
    headerBits = reshape(demappedRows( ...
        1:params.headerSymbolsPerFrame, :), [], 1);
    [frameId, headerValid, headerInformationBits] = ...
        otfs_tr_decode_frame_header(headerBits, params);
    diag.frameId = frameId;
    diag.headerValid = headerValid;
    diag.headerEstimatedBits = headerBits;
    diag.headerInformationBits = headerInformationBits;
    if ~headerValid
        ber = NaN;
        return;
    end
    estimatedBits = reshape(demappedRows( ...
        params.headerSymbolsPerFrame+1:end, :), [], 1);
    refBits = reference.payloadBitsByFrame(:, frameId+1);
    expectedHeaderBits = otfs_tr_encode_frame_header(frameId, params);
    expectedHeaderRows = reshape(expectedHeaderBits, ...
        params.headerSymbolsPerFrame, params.MBits);
    expectedPayloadRows = reshape(refBits, [], params.MBits);
    expectedRows = [expectedHeaderRows; expectedPayloadRows];
    expectedSymbols = qammod(bi2de(expectedRows), params.MMod, ...
        "gray", "UnitAveragePower", true);
    diag = localAddSoftSymbolDiagnostics(diag, softDataSymbols, ...
        expectedSymbols);
else
    estimatedBits = reshape(demappedRows, [], 1);
    refBits = reference.bitsPerFrame;
    diag.headerValid = true;
end
compareLen = min(numel(estimatedBits), numel(refBits));
if compareLen < 1
    ber = NaN;
    return;
end
bitErrors = xor(logical(estimatedBits(1:compareLen)), ...
    logical(refBits(1:compareLen)));
ber = sum(bitErrors) / compareLen;

diag.estimatedBits = estimatedBits(1:compareLen);
diag.refBits = refBits(1:compareLen);
diag.bitErrors = bitErrors;
diag.errorBitPositions = find(bitErrors);
bitErrorRows = reshape(bitErrors, [], params.MBits);
diag.bitErrorsByPlane = sum(bitErrorRows, 1);
end

function [observationCorrected, hardCorrected, info] = ...
        localCorrectStructuredRowBias(observation, hardDecision, params, p)
observationCorrected = observation;
hardCorrected = hardDecision;
info = struct("applied", false, "appliedRows", zeros(0, 1), ...
    "biasByRow", complex(zeros(params.N, 1)), ...
    "improvementRatioByRow", ones(params.N, 1), ...
    "coherenceByRow", zeros(params.N, 1));
if ~localGetField(p, "enableStructuredRowBiasCorrection", false)
    return;
end

alphabet = qammod((0:params.MMod-1).', params.MMod, "gray", ...
    "UnitAveragePower", true);
dataScale = localGetField(params, "dataScale", 1);
alphabet = dataScale*alphabet;
iterations = localGetField(p, "rowBiasIterations", 5);
minimumMagnitude = localGetField(p, "rowBiasMinMagnitude", 0.10);
maximumMagnitude = localGetField(p, "rowBiasMaxMagnitude", 0.75);
minimumImprovement = localGetField(p, ...
    "rowBiasMinImprovementRatio", 1.25);
minimumCoherence = localGetField(p, "rowBiasMinCoherence", 0.65);

for row = 1:params.N
    dataColumns = find(params.dataMask(row, :) == 1);
    if numel(dataColumns) < 4
        continue;
    end
    values = observation(row, dataColumns).';
    bias = 0;
    for iteration = 1:iterations
        decisions = localNearestAlphabet(values-bias, alphabet);
        bias = mean(values-decisions);
    end
    decisionsBefore = localNearestAlphabet(values, alphabet);
    decisionsAfter = localNearestAlphabet(values-bias, alphabet);
    distanceBefore = sum(abs(values-decisionsBefore).^2);
    distanceAfter = sum(abs(values-bias-decisionsAfter).^2);
    residuals = values-decisionsAfter;
    improvement = distanceBefore/max(distanceAfter, eps);
    coherence = abs(mean(residuals))/(mean(abs(residuals))+eps);
    info.biasByRow(row) = bias;
    info.improvementRatioByRow(row) = improvement;
    info.coherenceByRow(row) = coherence;
    shouldApply = abs(bias) >= minimumMagnitude && ...
        abs(bias) <= maximumMagnitude && ...
        improvement >= minimumImprovement && ...
        coherence >= minimumCoherence;
    if shouldApply
        observationCorrected(row, :) = observation(row, :)-bias;
        hardCorrected(row, dataColumns) = decisionsAfter.';
        info.appliedRows(end+1, 1) = row;
    end
end
info.applied = ~isempty(info.appliedRows);
end

function decisions = localNearestAlphabet(values, alphabet)
[~, indices] = min(abs(values-alphabet.').^2, [], 2);
decisions = alphabet(indices);
end

function [sigmaEffective, info] = localCalibrateMpNoiseVariance( ...
        observation, hardDecision, chanCoef, sigmaOriginal, params, p)
info = struct("applied", false, "ratio", 1, ...
    "equalizedVariance", NaN, "candidateVariance", sigmaOriginal);
sigmaEffective = sigmaOriginal;
if ~localGetField(p, "enableMpNoiseVarianceCalibration", false)
    return;
end
mask = params.dataMask == 1;
residual = observation(mask)-hardDecision(mask);
if isempty(residual) || ~any(isfinite(residual))
    return;
end
% For circular complex Gaussian noise, |w|^2 is exponential and its mean
% equals median(|w|^2)/log(2). This also captures unmodelled residual energy.
equalizedVariance = median(abs(residual).^2, "omitnan")/log(2);
channelPower = sum(abs(chanCoef).^2);
candidateVariance = max(equalizedVariance*channelPower, 1e-8);
ratio = candidateVariance/max(sigmaOriginal, 1e-8);
info.equalizedVariance = equalizedVariance;
info.candidateVariance = candidateVariance;
info.ratio = ratio;
minimumRatio = localGetField(p, "mpNoiseCalibrationMinRatio", 1.25);
if isfinite(candidateVariance) && ratio >= minimumRatio
    sigmaEffective = candidateVariance;
    info.applied = true;
end
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

function diag = localEmptyFrameDiagnostics(params)
diag = struct();
diag.rxGrid = complex(nan(params.N, params.M));
diag.detectedGrid = complex(nan(params.N, params.M));
diag.softDetectedGrid = complex(nan(params.N, params.M));
diag.rawSoftDetectedGrid = complex(nan(params.N, params.M));
diag.posteriorMeanGrid = complex(nan(params.N, params.M));
diag.pilotRx = NaN;
diag.phaseCorrectionRad = NaN;
diag.delayTaps = [];
diag.dopplerTaps = [];
diag.chanCoef = [];
diag.taps = 0;
diag.tapsUsed = 0;
diag.sigmaEst = NaN;
diag.sigmaEffective = NaN;
diag.mpNoiseCalibrationApplied = false;
diag.mpNoiseCalibrationRatio = NaN;
diag.decisionDirectedSigmaEqualized = NaN;
diag.delayTapsUsed = [];
diag.dopplerTapsUsed = [];
diag.chanCoefUsed = [];
diag.dataSymbols = complex(zeros(0, 1));
diag.softDataSymbols = complex(zeros(0, 1));
diag.posteriorMeanDataSymbols = complex(zeros(0, 1));
diag.expectedDataSymbols = complex(zeros(0, 1));
diag.dataDecisionConfidence = zeros(0, 1);
diag.meanDecisionConfidence = NaN;
diag.minimumDecisionConfidence = NaN;
diag.softEvmRms = NaN;
diag.softEvmPercent = NaN;
diag.residualEvmRms = NaN;
diag.residualEvmPercent = NaN;
diag.commonComplexGain = NaN;
diag.commonGainMagnitude = NaN;
diag.commonPhaseErrorRad = NaN;
diag.estimatedBits = zeros(0, 1);
diag.refBits = zeros(0, 1);
diag.bitErrors = false(0, 1);
diag.errorBitPositions = zeros(0, 1);
diag.frameResidualCfoHz = 0;
diag.frameResidualCfoScore = NaN;
diag.ddPilotResidualCfoFallbackApplied = false;
diag.rowBiasCorrectionApplied = false;
diag.rowBiasAppliedRows = zeros(0, 1);
diag.rowBiasByRow = complex(zeros(params.N, 1));
diag.rowBiasImprovementRatioByRow = ones(params.N, 1);
diag.rowBiasCoherenceByRow = zeros(params.N, 1);
diag.frameDcEstimate = NaN;
diag.frameDcRemovalApplied = false;
diag.frameId = NaN;
diag.headerValid = false;
diag.headerEstimatedBits = zeros(0, 1);
diag.headerInformationBits = zeros(0, 1);
diag.duplicateFrameId = false;
diag.sequenceDiscontinuity = false;
diag.bitErrorsByPlane = zeros(1, params.MBits);
end

function diag = localAddSoftSymbolDiagnostics(diag, softSymbols, expectedSymbols)
softSymbols = softSymbols(:);
expectedSymbols = expectedSymbols(:);
compareLength = min(numel(softSymbols), numel(expectedSymbols));
if compareLength < 1
    return;
end
softSymbols = softSymbols(1:compareLength);
expectedSymbols = expectedSymbols(1:compareLength);
referenceEnergy = sum(abs(expectedSymbols).^2);
if referenceEnergy <= eps
    return;
end

commonGain = (expectedSymbols' * softSymbols) / referenceEnergy;
softError = softSymbols-expectedSymbols;
residualError = softSymbols-commonGain*expectedSymbols;
fittedEnergy = sum(abs(commonGain*expectedSymbols).^2);
diag.softDataSymbols = softSymbols;
diag.expectedDataSymbols = expectedSymbols;
diag.softEvmRms = sqrt(sum(abs(softError).^2)/referenceEnergy);
diag.softEvmPercent = 100*diag.softEvmRms;
diag.residualEvmRms = sqrt(sum(abs(residualError).^2) / ...
    max(fittedEnergy, eps));
diag.residualEvmPercent = 100*diag.residualEvmRms;
diag.commonComplexGain = commonGain;
diag.commonGainMagnitude = abs(commonGain);
diag.commonPhaseErrorRad = angle(commonGain);
end

function reference = localNormalizeReference(referenceInput)
% Accept both current superframe packages and legacy repeated-frame bits.
reference = struct();
if isstruct(referenceInput) && ...
        isfield(referenceInput, "payloadBitsByFrame")
    reference.mode = "unique-superframe";
    reference.payloadBitsByFrame = referenceInput.payloadBitsByFrame;
    reference.superframeLength = size(reference.payloadBitsByFrame, 2);
elseif isstruct(referenceInput) && isfield(referenceInput, "bitsPerFrame")
    reference.mode = "legacy-repeated";
    reference.bitsPerFrame = referenceInput.bitsPerFrame(:);
    reference.superframeLength = 1;
else
    reference.mode = "legacy-repeated";
    reference.bitsPerFrame = referenceInput(:);
    reference.superframeLength = 1;
end
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
    "cpCorrectionAccepted", false, ...
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
