function result = otfs_tr_finalize_result(processed, requestedDopplerHz, cfg)
%otfs_tr_finalize_result Add aggregate bit/error counts to baseline RX output.

result = processed;
validIndices = find(isfinite(processed.ber));
totalBits = 0;
totalErrors = 0;
for index = validIndices(:).'
    bitErrors = processed.frameDiagnostics(index).bitErrors;
    totalBits = totalBits + numel(bitErrors);
    totalErrors = totalErrors + sum(bitErrors);
end
result.totalBits = totalBits;
result.totalErrors = totalErrors;
result.frameBer = processed.ber;
if totalBits > 0
    result.ber = totalErrors/totalBits;
else
    result.ber = NaN;
end
result.requestedDopplerHz = requestedDopplerHz;
result.designBitRateBps = cfg.designBitRateBps;
result.designSpectralEfficiency = cfg.designSpectralEfficiency;
if isfield(processed, "frameInfo") && ~isempty(processed.frameInfo)
    residualValues = [processed.frameInfo.cpCfoEstimateHz];
    result.residualCfoHz = median(residualValues, "omitnan");
else
    result.residualCfoHz = NaN;
end
if totalErrors == 0 && totalBits > 0
    result.zeroErrorBerUpper95 = 3/totalBits;
else
    result.zeroErrorBerUpper95 = NaN;
end

result.softEvmPercentMedian = localDiagnosticMedian( ...
    processed.frameDiagnostics, "softEvmPercent");
result.residualEvmPercentMedian = localDiagnosticMedian( ...
    processed.frameDiagnostics, "residualEvmPercent");
result.decisionConfidenceMedian = localDiagnosticMedian( ...
    processed.frameDiagnostics, "meanDecisionConfidence");
result.commonGainMagnitudeMedian = localDiagnosticMedian( ...
    processed.frameDiagnostics, "commonGainMagnitude");
phaseValues = localDiagnosticValues(processed.frameDiagnostics, ...
    "commonPhaseErrorRad");
result.commonPhaseErrorDegMedian = ...
    rad2deg(median(phaseValues, "omitnan"));
result.ddPilotCfoFallbackFrames = localDiagnosticCount( ...
    processed.frameDiagnostics, "ddPilotResidualCfoFallbackApplied");
result.rowBiasCorrectedFrames = localDiagnosticCount( ...
    processed.frameDiagnostics, "rowBiasCorrectionApplied");
result.mpNoiseCalibrationFrames = localDiagnosticCount( ...
    processed.frameDiagnostics, "mpNoiseCalibrationApplied");
result.sigmaEffectiveMedian = localDiagnosticMedian( ...
    processed.frameDiagnostics, "sigmaEffective");
result.mpNoiseCalibrationRatioMedian = localDiagnosticMedian( ...
    processed.frameDiagnostics, "mpNoiseCalibrationRatio");
result.rowBiasApplicationCountByRow = zeros(cfg.N, 1);
for frameIndex = validIndices(:).'
    rows = processed.frameDiagnostics(frameIndex).rowBiasAppliedRows;
    rows = rows(rows >= 1 & rows <= cfg.N);
    result.rowBiasApplicationCountByRow(rows) = ...
        result.rowBiasApplicationCountByRow(rows)+1;
end
if ~isempty(validIndices) && ...
        isfield(processed.frameDiagnostics, "bitErrorsByPlane")
    result.bitErrorsByPlane = sum(vertcat( ...
        processed.frameDiagnostics(validIndices).bitErrorsByPlane), 1);
else
    result.bitErrorsByPlane = zeros(1, cfg.MBits);
end
end

function count = localDiagnosticCount(frameDiagnostics, fieldName)
if isempty(frameDiagnostics) || ~isfield(frameDiagnostics, fieldName)
    count = 0;
else
    count = sum(logical([frameDiagnostics.(fieldName)]));
end
end

function value = localDiagnosticMedian(frameDiagnostics, fieldName)
values = localDiagnosticValues(frameDiagnostics, fieldName);
value = median(values, "omitnan");
end

function values = localDiagnosticValues(frameDiagnostics, fieldName)
if isempty(frameDiagnostics) || ~isfield(frameDiagnostics, fieldName)
    values = NaN;
else
    values = [frameDiagnostics.(fieldName)];
end
end
