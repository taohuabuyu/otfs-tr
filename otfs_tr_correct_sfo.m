function [rxCorrected, info] = otfs_tr_correct_sfo( ...
        rx20, preamble10, params, cfg)
%otfs_tr_correct_sfo Estimate and correct sampling-frequency offset.
%
% The estimate comes from the slope of fractional preamble locations across
% the complete 20 MHz capture. A uniform interpolation then maps the observed
% frame spacing back to the nominal samples-per-frame value.

rx20 = rx20(:);
rxCorrected = rx20;
expectedSpacing = (numel(preamble10) + params.blockLen) * ...
    cfg.fsRx / cfg.fsTx;
enabled = localGetField(cfg, "enableSfoCompensation", false);

info = struct();
info.enabled = logical(enabled);
info.applied = false;
info.status = "disabled";
info.estimatedPpm = NaN;
info.expectedSamplesPerFrame = expectedSpacing;
info.observedSamplesPerFrame = NaN;
info.detectedPreambles = 0;
info.usedPreambles = 0;
info.inputSamples = numel(rx20);
info.outputSamples = numel(rx20);
info.scale = 1;
info.interpolationMethod = "none";
info.preambleStarts20 = zeros(0, 1);
info.fractionalPreambleStarts20 = zeros(0, 1);

if ~enabled
    return;
end

ratio = cfg.fsRx/cfg.fsTx;
if abs(ratio-round(ratio)) > 1e-12 || expectedSpacing <= 0
    info.status = "invalid-sample-rate-ratio";
    return;
end
ratio = round(ratio);
if ratio == 1
    preamble20 = preamble10(:);
else
    preamble20 = resample(preamble10(:), ratio, 1);
end

metric = localNormalizedCorrelation(rx20, preamble20);
if isempty(metric)
    info.status = "capture-too-short";
    return;
end

score = max(metric);
robustThreshold = median(metric) + ...
    8*median(abs(metric-median(metric)));
threshold = max([localGetField(cfg, "sfoPreambleMinScore", 0.35), ...
    localGetField(cfg, "preamblePeakThreshold", 0.45)*score, ...
    robustThreshold]);
candidate = find(metric >= threshold);
candidate = candidate(candidate > 1 & candidate < numel(metric));
isPeak = metric(candidate) >= metric(candidate-1) & ...
    metric(candidate) >= metric(candidate+1);
peaks = localEnforcePeakSpacing(candidate(isPeak), metric, ...
    max(1, floor(0.8*expectedSpacing)));
fractionalPeaks = localRefinePeaks(metric, peaks);
info.detectedPreambles = numel(peaks);
info.preambleStarts20 = peaks;
info.fractionalPreambleStarts20 = fractionalPeaks;

minimumPreambles = localGetField(cfg, "sfoMinimumPreambles", 12);
if numel(fractionalPeaks) < minimumPreambles
    info.status = "insufficient-preambles";
    return;
end

nominalFrameIndex = round((fractionalPeaks-fractionalPeaks(1)) / ...
    expectedSpacing);
[spacing, fitMask] = localRobustSpacing( ...
    nominalFrameIndex, fractionalPeaks);
info.usedPreambles = nnz(fitMask);
info.observedSamplesPerFrame = spacing;
info.estimatedPpm = (spacing/expectedSpacing-1)*1e6;

if ~isfinite(info.estimatedPpm)
    info.status = "invalid-estimate";
    return;
end
if abs(info.estimatedPpm) > ...
        localGetField(cfg, "sfoMaxAbsPpm", 200)
    info.status = "estimate-out-of-range";
    return;
end
if abs(info.estimatedPpm) < ...
        localGetField(cfg, "sfoMinCorrectionPpm", 0.5)
    info.status = "below-correction-threshold";
    return;
end

scale = spacing/expectedSpacing;
outputLength = floor((numel(rx20)-1)/scale) + 1;
query = 1 + (0:outputLength-1).'*scale;
rxCorrected = interp1((1:numel(rx20)).', rx20, query, "linear");

info.applied = true;
info.status = "applied";
info.outputSamples = numel(rxCorrected);
info.scale = scale;
info.interpolationMethod = "linear";
end

function metric = localNormalizedCorrelation(rx, preamble)
referenceLength = numel(preamble);
if numel(rx) < referenceLength
    metric = zeros(0, 1);
    return;
end
corrValues = conv(rx, conj(flipud(preamble)), "valid");
referenceEnergy = sum(abs(preamble).^2);
energyPrefix = cumsum([0; abs(rx).^2]);
windowEnergy = energyPrefix(referenceLength+1:end) - ...
    energyPrefix(1:end-referenceLength);
metric = abs(corrValues).^2 ./ ...
    (windowEnergy*referenceEnergy + eps);
end

function peaks = localEnforcePeakSpacing(candidates, metric, minSpacing)
peaks = zeros(0, 1);
for index = 1:numel(candidates)
    candidate = candidates(index);
    if isempty(peaks) || candidate-peaks(end) >= minSpacing
        peaks(end+1, 1) = candidate; %#ok<AGROW>
    elseif metric(candidate) > metric(peaks(end))
        peaks(end) = candidate;
    end
end
end

function fractionalPeaks = localRefinePeaks(metric, peaks)
fractionalPeaks = double(peaks(:));
for index = 1:numel(peaks)
    peak = peaks(index);
    left = metric(peak-1);
    center = metric(peak);
    right = metric(peak+1);
    denominator = left - 2*center + right;
    if abs(denominator) > eps
        offset = 0.5*(left-right)/denominator;
        fractionalPeaks(index) = peak + max(-0.5, min(0.5, offset));
    end
end
end

function [spacing, fitMask] = localRobustSpacing(frameIndex, positions)
frameIndex = double(frameIndex(:));
positions = double(positions(:));
initialFit = polyfit(frameIndex, positions, 1);
residual = positions - polyval(initialFit, frameIndex);
medianResidual = median(residual);
residualMad = median(abs(residual-medianResidual));
tolerance = max(1.5, 6*residualMad);
fitMask = abs(residual-medianResidual) <= tolerance;
if nnz(fitMask) < 2
    fitMask = true(size(frameIndex));
end
finalFit = polyfit(frameIndex(fitMask), positions(fitMask), 1);
spacing = finalFit(1);
end

function value = localGetField(s, name, defaultValue)
if isfield(s, name) && ~isempty(s.(name))
    value = s.(name);
else
    value = defaultValue;
end
end
