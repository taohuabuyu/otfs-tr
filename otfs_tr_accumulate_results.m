function cumulative = otfs_tr_accumulate_results(stateFile, result, cfg)
%otfs_tr_accumulate_results Accumulate complete per-round BER results.

stateFile = string(stateFile);
if strlength(stateFile) == 0
    error("otfs_tr:MissingCumulativeStateFile", ...
        "A cumulative BER state file is required.");
end
if isfile(stateFile)
    saved = load(stateFile, "cumulative");
    cumulative = saved.cumulative;
    if cumulative.version ~= 2 || ...
            cumulative.effectiveBitsPerFrame ~= cfg.effectiveBitsPerFrame || ...
            cumulative.modulationOrder ~= cfg.MMod
        error("otfs_tr:CumulativeBerConfigurationMismatch", ...
            "The cumulative state uses a different format or waveform configuration.");
    end
else
    cumulative = localEmptyState(cfg);
end

runId = string(localField(result, "localRunId", ""));
if strlength(runId) == 0
    error("otfs_tr:MissingCumulativeRoundId", ...
        "Each cumulative round requires a nonempty localRunId.");
end
if any(cumulative.processedRunIds == runId)
    error("otfs_tr:DuplicateCumulativeRound", ...
        "Round %s has already been accumulated.", runId);
end

roundValidFrames = localNonnegativeInteger(result, "validFrames");
roundTestedBits = localNonnegativeInteger(result, "totalBits");
roundBitErrors = localNonnegativeInteger(result, "totalErrors");
if roundBitErrors > roundTestedBits
    error("otfs_tr:InvalidCumulativeRoundResult", ...
        "A round cannot contain more bit errors than tested bits.");
end

cumulative.batchCount = cumulative.batchCount + 1;
cumulative.validFrames = cumulative.validFrames + roundValidFrames;
cumulative.testedBits = cumulative.testedBits + roundTestedBits;
cumulative.bitErrors = cumulative.bitErrors + roundBitErrors;
cumulative.newValidFrames = roundValidFrames;
cumulative.newTestedBits = roundTestedBits;
cumulative.newBitErrors = roundBitErrors;
cumulative.latestRunId = runId;
cumulative.processedRunIds(end+1, 1) = runId;
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
otfs_tr_write_json_atomic(jsonFile, cumulative);
textFile = fullfile(folder, name + ".txt");
textFields = ["version", "accumulationMode", "batchCount", ...
    "validFrames", "testedBits", "bitErrors", ...
    "newValidFrames", "newTestedBits", "newBitErrors", ...
    "ber", "zeroErrorUpper95", "targetReached", ...
    "latestRunId", "updatedAt"];
otfs_tr_write_key_value_atomic(textFile, cumulative, textFields);
cumulative.stateFile = stateFile;
cumulative.jsonFile = string(jsonFile);
cumulative.textFile = string(textFile);
end

function cumulative = localEmptyState(cfg)
cumulative = struct();
cumulative.version = 2;
cumulative.accumulationMode = "per-round";
cumulative.minimumTestBits = cfg.minimumTestBits;
cumulative.effectiveBitsPerFrame = cfg.effectiveBitsPerFrame;
cumulative.modulationOrder = cfg.MMod;
cumulative.processedRunIds = strings(0, 1);
cumulative.batchCount = 0;
cumulative.validFrames = 0;
cumulative.testedBits = 0;
cumulative.bitErrors = 0;
cumulative.newValidFrames = 0;
cumulative.newTestedBits = 0;
cumulative.newBitErrors = 0;
cumulative.ber = NaN;
cumulative.zeroErrorUpper95 = NaN;
cumulative.targetReached = false;
cumulative.latestRunId = "";
cumulative.updatedAt = "";
end

function value = localNonnegativeInteger(result, fieldName)
if ~isfield(result, fieldName)
    error("otfs_tr:InvalidCumulativeRoundResult", ...
        "Round result is missing %s.", fieldName);
end
value = result.(fieldName);
if ~isnumeric(value) || ~isscalar(value) || ~isfinite(value) || ...
        value < 0 || mod(value, 1) ~= 0
    error("otfs_tr:InvalidCumulativeRoundResult", ...
        "Round result field %s must be one nonnegative integer.", fieldName);
end
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
