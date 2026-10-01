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
result.application = localFinalizeApplication(processed, validIndices, cfg);
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
result.sharedMpNoiseCalibrationFrames = localDiagnosticValueCount( ...
    processed.frameDiagnostics, "mpNoiseCalibrationSource", "shared");
result.sigmaEffectiveMedian = localDiagnosticMedian( ...
    processed.frameDiagnostics, "sigmaEffective");
result.mpNoiseCalibrationRatioMedian = localDiagnosticMedian( ...
    processed.frameDiagnostics, "mpNoiseCalibrationRatio");
result.mpIterationMedian = localDiagnosticMedian( ...
    processed.frameDiagnostics, "mpFinalPassIterations");
result.mpIterationMaximum = max(localDiagnosticValues( ...
    processed.frameDiagnostics, "mpFinalPassIterations"), ...
    [], "omitnan");
result.mpMaximumIterationFrames = sum(localDiagnosticValues( ...
    processed.frameDiagnostics, "mpFinalPassIterations") >= ...
    cfg.mpMaximumIterations);
result.mpConvergedFrames = localDiagnosticCount( ...
    processed.frameDiagnostics, "mpConverged");
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

function application = localFinalizeApplication(processed, validIndices, cfg)
application = struct("enabled", false, ...
    "transmittedText", "", "decodedText", "", ...
    "payloadBytes", 0, "crcValidFrames", 0, ...
    "consistentFrames", 0, "crcPass", false, ...
    "textMatch", false, "pass", true);
if ~isfield(processed, "referenceApplication") || ...
        ~isfield(processed.referenceApplication, "enabled") || ...
        ~processed.referenceApplication.enabled
    return;
end

reference = processed.referenceApplication;
application.enabled = true;
application.transmittedText = reference.transmittedText;
application.payloadBytes = reference.payloadBytes;
crcValid = false(size(validIndices));
matching = false(size(validIndices));
decodedText = strings(size(validIndices));
for itemIndex = 1:numel(validIndices)
    frameApplication = processed.frameDiagnostics( ...
        validIndices(itemIndex)).application;
    crcValid(itemIndex) = frameApplication.valid && ...
        frameApplication.crcPass;
    decodedText(itemIndex) = frameApplication.decodedText;
    matching(itemIndex) = crcValid(itemIndex) && ...
        frameApplication.decodedText == reference.transmittedText;
end
application.crcValidFrames = sum(crcValid);
application.consistentFrames = sum(matching);
application.crcPass = application.crcValidFrames > 0;
application.textMatch = application.consistentFrames > 0;
if any(matching)
    application.decodedText = decodedText(find(matching, 1, "first"));
elseif any(crcValid)
    application.decodedText = decodedText(find(crcValid, 1, "first"));
end
application.pass = application.consistentFrames >= ...
    cfg.applicationMinimumConsistentFrames;
end

function count = localDiagnosticCount(frameDiagnostics, fieldName)
if isempty(frameDiagnostics) || ~isfield(frameDiagnostics, fieldName)
    count = 0;
else
    count = sum(logical([frameDiagnostics.(fieldName)]));
end
end

function count = localDiagnosticValueCount( ...
        frameDiagnostics, fieldName, expectedValue)
if isempty(frameDiagnostics) || ~isfield(frameDiagnostics, fieldName)
    count = 0;
else
    count = sum(string({frameDiagnostics.(fieldName)}) == expectedValue);
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
