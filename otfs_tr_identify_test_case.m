function selected = otfs_tr_identify_test_case(rx20, cfg, caseDirectory)
%otfs_tr_identify_test_case Select one local MAT by the decoded air code.
% The case directory is a local catalog, not a BER-based candidate search.

caseDirectory = string(caseDirectory);
if ~isscalar(caseDirectory) || ~isfolder(caseDirectory)
    error("otfs_tr:MissingTestCaseDirectory", ...
        "A local test-case directory is required.");
end
entries = dir(fullfile(caseDirectory, "*.mat"));
if isempty(entries) || numel(entries) > 128
    error("otfs_tr:InvalidTestCaseCatalog", ...
        "The case directory must contain 1-128 MAT files.");
end
caseFiles = strings(numel(entries), 1);
caseIds = strings(numel(entries), 1);
caseCodes = zeros(numel(entries), 1, "uint32");
for index = 1:numel(entries)
    caseFiles(index) = string(fullfile(entries(index).folder, ...
        entries(index).name));
    data = otfs_tr_load_test_case(caseFiles(index), cfg);
    caseIds(index) = data.caseId;
    caseCodes(index) = otfs_tr_case_code(data.caseId);
end
if numel(unique(caseCodes)) ~= numel(caseCodes)
    error("otfs_tr:DuplicateAirCaseCode", ...
        "The case directory contains duplicate or colliding case IDs.");
end

probeCfg = cfg;
probeCfg.minimumTestBits = 1;
probeCfg.minimumValidFrames = 1;
probeCfg.maxDecodedFrames = min(6, cfg.maxDecodedFrames);
probeRequest = struct("test_case_file", caseFiles(1), ...
    "equivalent_cfo_hz", cfg.equivalentDopplerHz);
[~, reference, params, training] = otfs_tr_build_waveform( ...
    cfg, probeRequest);
probe = wide_rx_process_capture(rx20, training, params, ...
    reference, probeCfg);
valid = [probe.frameDiagnostics.headerValid];
codes = [probe.frameDiagnostics(valid).caseCode];
if numel(codes) < 2 || numel(unique(codes)) ~= 1
    error("otfs_tr:AirCaseCodeNotConfirmed", ...
        "At least two CRC-valid frames must agree on one air case code.");
end
match = find(caseCodes == codes(1));
if numel(match) ~= 1
    error("otfs_tr:UnknownAirCaseCode", ...
        "Decoded air case code %08X is absent from the local catalog.", ...
        codes(1));
end
selected = struct("filePath", caseFiles(match), ...
    "caseId", caseIds(match), "caseCode", codes(1), ...
    "confirmingFrames", numel(codes));
end
