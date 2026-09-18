function [pairDirectory, referenceFile, captureFile] = ...
        otfs_tr_find_latest_pair(resultRoot)
%otfs_tr_find_latest_pair Find the newest complete RX-owned run package.

pairRoot = fullfile(resultRoot, "pairs");
directories = dir(pairRoot);
directories = directories([directories.isdir]);
names = string({directories.name});
directories = directories(names ~= "." & names ~= "..");

if isempty(directories)
    localMissingPairError(pairRoot);
end

[~, order] = sort(string({directories.name}), "descend");
directories = directories(order);
for index = 1:numel(directories)
    candidate = fullfile(directories(index).folder, ...
        directories(index).name);
    candidateReference = fullfile(candidate, "tx", ...
        "reference_package.mat");
    candidateCapture = fullfile(candidate, "rx", "rx_capture.mat");
    if isfile(candidateReference) && isfile(candidateCapture)
        pairDirectory = string(candidate);
        referenceFile = string(candidateReference);
        captureFile = string(candidateCapture);
        return;
    end
end

localMissingPairError(pairRoot);
end

function localMissingPairError(pairRoot)
error("otfs_tr:MissingCompletePair", ...
    "No complete run package was found under %s. Copy the final " + ...
    "reference_package.mat into the run package's tx folder.", pairRoot);
end
