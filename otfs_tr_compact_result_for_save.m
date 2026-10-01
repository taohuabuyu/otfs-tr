function archived = otfs_tr_compact_result_for_save(result, cfg)
%otfs_tr_compact_result_for_save Remove bulky reproducible plot inputs.

archived = result;
if localField(cfg, "saveFullDiagnostics", false)
    archived.diagnosticsStorage = struct("mode", "full", ...
        "fullFrameIndices", (1:numel(result.frameDiagnostics)).');
    return;
end

signalFields = ["rx20", "rx20CfoCorrected", "rx20SfoCorrected", ...
    "rx20Filtered", "rx20FractionalTimingCorrected", "rx10"];
archived = localRemoveFields(archived, signalFields);
if isfield(archived, "coarseSync20")
    archived.coarseSync20 = localRemoveFields(archived.coarseSync20, ...
        ["metric", "preamble20"]);
end

frameCount = numel(archived.frameDiagnostics);
requestedFrames = unique(localField(cfg, ...
    "savedFullDiagnosticFrames", zeros(0, 1)));
fullFrameIndices = requestedFrames(requestedFrames >= 1 & ...
    requestedFrames <= frameCount);
compactFields = ["rxGrid", "detectedGrid", "softDetectedGrid", ...
    "rawSoftDetectedGrid", "posteriorMeanGrid", "dataSymbols", ...
    "softDataSymbols", "posteriorMeanDataSymbols", ...
    "expectedDataSymbols", "dataDecisionConfidence", ...
    "estimatedBits", "estimatedPayloadBits", ...
    "estimatedApplicationBits", "refBits"];
compactIndices = setdiff(1:frameCount, fullFrameIndices);
for frameIndex = compactIndices
    for fieldIndex = 1:numel(compactFields)
        fieldName = compactFields(fieldIndex);
        if isfield(archived.frameDiagnostics, fieldName)
            archived.frameDiagnostics(frameIndex).(fieldName) = [];
        end
    end
end
archived.diagnosticsStorage = struct("mode", "compact", ...
    "fullFrameIndices", fullFrameIndices(:), ...
    "removedSignalFields", signalFields(:), ...
    "compactedFrameFields", compactFields(:));
end

function value = localField(s, name, defaultValue)
if isfield(s, name)
    value = s.(name);
else
    value = defaultValue;
end
end

function value = localRemoveFields(value, fieldNames)
present = fieldNames(isfield(value, fieldNames));
if ~isempty(present)
    value = rmfield(value, cellstr(present));
end
end
