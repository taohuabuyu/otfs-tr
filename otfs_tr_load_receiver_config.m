function rxConfig = otfs_tr_load_receiver_config(filePath, cfg)
%otfs_tr_load_receiver_config Read RX-local input and execution controls.
% RX configuration intentionally contains no TX frequency or task ID.

if nargin < 2
    cfg = otfs_tr_config();
end
filePath = string(filePath);
allowedKeys = ["testPayload", "receive_mode", "receive_round_count"];
values = otfs_tr_read_key_value_file(filePath, allowedKeys);
if ~isfield(values, "testPayload") || ...
        strlength(values.testPayload) == 0
    error("otfs_tr:MissingRxTestCasePath", ...
        "RX configuration requires testPayload=<local MAT file path>.");
end

testCasePath = values.testPayload;
isAbsolutePath = ~isempty(regexp(char(testCasePath), ...
    '^[A-Za-z]:[\\/]|^\\\\|^/', 'once'));
if ~isAbsolutePath
    testCasePath = fullfile(fileparts(filePath), testCasePath);
end
if ~isfile(testCasePath) || ~endsWith(lower(testCasePath), ".mat")
    error("otfs_tr:MissingTestCaseFile", ...
        "RX testPayload must identify an existing MAT file: %s", ...
        testCasePath);
end

receiveMode = string(localValue(values, "receive_mode", cfg.receiveMode));
receiveRoundCount = localInteger(localValue(values, ...
    "receive_round_count", string(cfg.receiveRoundCount)), ...
    "receive_round_count");
candidateCfg = cfg;
candidateCfg.receiveMode = receiveMode;
candidateCfg.receiveRoundCount = receiveRoundCount;
otfs_tr_validate_config(candidateCfg);

rxConfig = struct("test_case_file", string(testCasePath), ...
    "source_file", filePath, "receive_mode", receiveMode, ...
    "receive_round_count", receiveRoundCount);
end

function value = localValue(values, key, defaultValue)
if isfield(values, key)
    value = values.(key);
else
    value = defaultValue;
end
end

function value = localInteger(textValue, key)
value = str2double(textValue);
if ~isscalar(value) || ~isfinite(value) || value < 1 || ...
        mod(value, 1) ~= 0
    error("otfs_tr:InvalidSoftwareConfigNumber", ...
        "%s must contain one positive integer value.", key);
end
end
