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
end
