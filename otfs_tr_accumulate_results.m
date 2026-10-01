function cumulative = otfs_tr_accumulate_results(stateFile, result, cfg)
%otfs_tr_accumulate_results Accumulate unique-frame BER across short captures.

stateFile = string(stateFile);
if strlength(stateFile) == 0
    error("otfs_tr:MissingCumulativeStateFile", ...
        "A cumulative BER state file is required.");
end
if string(localField(result, "referenceMode", "")) ~= ...
        "unique-superframe"
    error("otfs_tr:CumulativeBerRequiresUniqueFrames", ...
        "Cumulative BER requires decoded unique-superframe IDs.");
end

if isfile(stateFile)
    saved = load(stateFile, "cumulative");
    cumulative = saved.cumulative;
    if cumulative.superframeLength ~= cfg.superframeLength
        error("otfs_tr:CumulativeBerConfigurationMismatch", ...
            "The saved cumulative state uses a different superframe length.");
    end
else
    cumulative = localEmptyState(cfg);
end

newValidFrames = 0;
newTestedBits = 0;
newBitErrors = 0;
duplicatesSkipped = 0;
for frameIndex = 1:numel(result.frameBer)
    frameId = result.frameIds(frameIndex);
    validFrame = isfinite(result.frameBer(frameIndex)) && ...
        isfinite(frameId) && frameId >= 0 && ...
        frameId < cumulative.superframeLength;
    if ~validFrame
        continue;
    end
    stateIndex = frameId + 1;
    if cumulative.seenFrameIds(stateIndex)
        duplicatesSkipped = duplicatesSkipped + 1;
        continue;
    end
    bitErrors = result.frameDiagnostics(frameIndex).bitErrors;
    cumulative.seenFrameIds(stateIndex) = true;
    newValidFrames = newValidFrames + 1;
    newTestedBits = newTestedBits + numel(bitErrors);
    newBitErrors = newBitErrors + sum(bitErrors);
end

cumulative.batchCount = cumulative.batchCount + 1;
cumulative.validFrames = cumulative.validFrames + newValidFrames;
cumulative.testedBits = cumulative.testedBits + newTestedBits;
cumulative.bitErrors = cumulative.bitErrors + newBitErrors;
cumulative.duplicatesSkipped = cumulative.duplicatesSkipped + ...
    duplicatesSkipped;
cumulative.newValidFrames = newValidFrames;
cumulative.newTestedBits = newTestedBits;
cumulative.newBitErrors = newBitErrors;
cumulative.latestRunId = string(localField(result, "localRunId", ""));
if cumulative.testedBits > 0
    cumulative.ber = cumulative.bitErrors/cumulative.testedBits;
else
    cumulative.ber = NaN;
end
if cumulative.bitErrors == 0 && cumulative.testedBits > 0
    cumulative.zeroErrorUpper95 = 3/cumulative.testedBits;
else
    cumulative.zeroErrorUpper95 = NaN;
end
cumulative.targetReached = ...
    cumulative.testedBits >= cfg.minimumTestBits;
cumulative.updatedAt = string(datetime("now", ...
    "Format", "yyyy-MM-dd HH:mm:ss.SSS"));

localSaveStateAtomic(stateFile, cumulative);
[folder, name] = fileparts(stateFile);
jsonFile = fullfile(folder, name + ".json");
jsonState = rmfield(cumulative, "seenFrameIds");
otfs_tr_write_json_atomic(jsonFile, jsonState);
cumulative.stateFile = stateFile;
cumulative.jsonFile = string(jsonFile);
end

function cumulative = localEmptyState(cfg)
cumulative = struct();
cumulative.version = 1;
cumulative.superframeLength = cfg.superframeLength;
cumulative.minimumTestBits = cfg.minimumTestBits;
cumulative.seenFrameIds = false(cfg.superframeLength, 1);
cumulative.batchCount = 0;
cumulative.validFrames = 0;
cumulative.testedBits = 0;
cumulative.bitErrors = 0;
cumulative.duplicatesSkipped = 0;
cumulative.newValidFrames = 0;
cumulative.newTestedBits = 0;
cumulative.newBitErrors = 0;
cumulative.ber = NaN;
cumulative.zeroErrorUpper95 = NaN;
cumulative.targetReached = false;
cumulative.latestRunId = "";
cumulative.updatedAt = "";
end

function localSaveStateAtomic(stateFile, cumulative)
folder = string(fileparts(stateFile));
if strlength(folder) > 0 && ~isfolder(folder)
    mkdir(folder);
end
temporaryFile = string(tempname(folder)) + ".mat";
cleanup = onCleanup(@() localDeleteTemporaryFile(temporaryFile));
save(temporaryFile, "cumulative");
moved = false;
message = "";
for attempt = 1:5
    [moved, message] = movefile(temporaryFile, stateFile, "f");
    if moved
        break;
    end
    pause(0.02*attempt);
end
if ~moved
    error("otfs_tr:CumulativeStateWriteFailed", ...
        "Could not replace cumulative state %s: %s", ...
        char(stateFile), char(message));
end
clear cleanup;
end

function localDeleteTemporaryFile(filePath)
if isfile(filePath)
    delete(filePath);
end
end

function value = localField(s, name, defaultValue)
if isfield(s, name)
    value = s.(name);
else
    value = defaultValue;
end
end
