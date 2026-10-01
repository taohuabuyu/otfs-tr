function rxConfig = otfs_tr_load_receiver_config(filePath)
%otfs_tr_load_receiver_config Read the RX-local MAT path after capture.
% RX configuration intentionally contains no TX frequency or task ID.

filePath = string(filePath);
values = otfs_tr_read_key_value_file(filePath, "testPayload");
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

rxConfig = struct("test_case_file", string(testCasePath), ...
    "source_file", filePath);
end
