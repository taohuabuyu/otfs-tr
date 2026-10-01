function options = otfs_tr_resolve_receiver_input(receiverInput)
%otfs_tr_resolve_receiver_input Normalize RX entry arguments without hardware.

options = struct( ...
    "softwareTxtMode", false, ...
    "localTestCaseMode", false, ...
    "autoCaseMode", false, ...
    "sourceConfigFile", "", ...
    "testCaseInput", "", ...
    "equivalentDopplerHz", NaN, ...
    "requestedCfoKnown", false);

if nargin < 1
    return;
end

if ~(ischar(receiverInput) || ...
        (isstring(receiverInput) && isscalar(receiverInput)))
    error("otfs_tr:InvalidReceiverInput", ...
        "RX input must be a TXT path, MAT path, or case directory.");
end

inputPath = string(receiverInput);
if endsWith(lower(inputPath), ".txt")
    options.softwareTxtMode = true;
    options.sourceConfigFile = inputPath;
elseif endsWith(lower(inputPath), ".mat") || isfolder(inputPath)
    options.testCaseInput = inputPath;
    options.autoCaseMode = isfolder(inputPath);
else
    error("otfs_tr:InvalidReceiverInput", ...
        "RX text input must identify a TXT config, MAT case, or case directory.");
end

options.localTestCaseMode = true;
end
