function request = otfs_tr_validate_request(request, cfg)
%otfs_tr_validate_request Normalize and validate one software test request.

arguments
    request (1,1) struct
    cfg (1,1) struct = otfs_tr_config()
end

requiredFields = "equivalent_cfo_hz";
for fieldIndex = 1:numel(requiredFields)
    fieldName = requiredFields(fieldIndex);
    if ~isfield(request, fieldName)
        error("otfs_tr:MissingRequestField", ...
            "The request is missing required field %s.", fieldName);
    end
end

allowedFields = ["protocol_version", "command", ...
    "payload_text", "equivalent_cfo_hz", "options", ...
    "scenario_name", "target_ber", "target_spectral_efficiency", ...
    "test_case_file"];
unknownFields = setdiff(string(fieldnames(request)), allowedFields);
if ~isempty(unknownFields)
    error("otfs_tr:UnsupportedRequestField", ...
        "Unsupported request field: %s.", unknownFields(1));
end

request.protocol_version = string(localField(request, ...
    "protocol_version", cfg.controlProtocolVersion));
if ~isscalar(request.protocol_version) || ...
        request.protocol_version ~= cfg.controlProtocolVersion
    error("otfs_tr:UnsupportedProtocolVersion", ...
        "protocol_version must be %s.", cfg.controlProtocolVersion);
end

request.command = string(localField(request, "command", "start_test"));
if ~isscalar(request.command) || request.command ~= "start_test"
    error("otfs_tr:InvalidStartCommand", ...
        "A transmit request command must be start_test.");
end

if isfield(request, "test_case_file")
    if isfield(request, "payload_text")
        error("otfs_tr:ConflictingPayloadSources", ...
            "Use test_case_file or payload_text, not both.");
    end
    request.test_case_file = string(request.test_case_file);
    if ~isscalar(request.test_case_file) || ...
            strlength(request.test_case_file) == 0 || ...
            ~endsWith(lower(request.test_case_file), ".mat") || ...
            ~isfile(request.test_case_file)
        error("otfs_tr:InvalidTestCaseFile", ...
            "test_case_file must be an existing MAT file.");
    end
else
    if ~isfield(request, "payload_text")
        error("otfs_tr:MissingRequestField", ...
            "The request is missing required field payload_text.");
    end
    request.payload_text = string(request.payload_text);
    if ~isscalar(request.payload_text)
        error("otfs_tr:InvalidPayloadText", ...
            "payload_text must be a scalar UTF-8 string.");
    end
    payloadBytes = unicode2native(char(request.payload_text), "UTF-8");
    if isempty(payloadBytes) || ...
            numel(payloadBytes) > cfg.applicationMaxPayloadBytes
        error("otfs_tr:InvalidPayloadLength", ...
            "payload_text must contain 1-%d UTF-8 bytes.", ...
            cfg.applicationMaxPayloadBytes);
    end
end

validateattributes(request.equivalent_cfo_hz, {'numeric'}, ...
    {'scalar', 'real', 'finite'});
request.equivalent_cfo_hz = double(request.equivalent_cfo_hz);
if request.equivalent_cfo_hz < min(cfg.cfoSearchHz) || ...
        request.equivalent_cfo_hz > max(cfg.cfoSearchHz)
    error("otfs_tr:InvalidRequestedCfo", ...
        "equivalent_cfo_hz must be within [%g, %g] Hz.", ...
        min(cfg.cfoSearchHz), max(cfg.cfoSearchHz));
end

request.scenario_name = string(localField(request, ...
    "scenario_name", cfg.scenarioName));
if ~isscalar(request.scenario_name) || ...
        strlength(request.scenario_name) < 1 || ...
        strlength(request.scenario_name) > 128
    error("otfs_tr:InvalidScenarioName", ...
        "scenario_name must contain 1-128 characters.");
end
request.target_ber = localField(request, ...
    "target_ber", cfg.maximumBer);
validateattributes(request.target_ber, {'numeric'}, ...
    {'scalar', 'real', 'finite', 'positive', '<', 1});
request.target_ber = double(request.target_ber);
request.target_spectral_efficiency = localField(request, ...
    "target_spectral_efficiency", cfg.minimumSpectralEfficiency);
validateattributes(request.target_spectral_efficiency, {'numeric'}, ...
    {'scalar', 'real', 'finite', 'positive'});
request.target_spectral_efficiency = ...
    double(request.target_spectral_efficiency);

options = localField(request, "options", struct());
if ~isstruct(options) || ~isscalar(options)
    error("otfs_tr:InvalidRequestOptions", ...
        "options must be a scalar JSON object/MATLAB struct.");
end
unknownOptions = setdiff(string(fieldnames(options)), "duration_seconds");
if ~isempty(unknownOptions)
    error("otfs_tr:UnsupportedRequestOption", ...
        "Unsupported request option: %s.", unknownOptions(1));
end
durationSeconds = localField(options, "duration_seconds", ...
    cfg.defaultTransmitDurationSeconds);
validateattributes(durationSeconds, {'numeric'}, ...
    {'scalar', 'real', 'finite'});
if durationSeconds < cfg.minimumTransmitDurationSeconds || ...
        durationSeconds > cfg.maximumTransmitDurationSeconds
    error("otfs_tr:InvalidTransmitDuration", ...
        "duration_seconds must be within [%g, %g].", ...
        cfg.minimumTransmitDurationSeconds, ...
        cfg.maximumTransmitDurationSeconds);
end
request.options = struct("duration_seconds", double(durationSeconds));
end

function value = localField(s, name, defaultValue)
if isfield(s, name)
    value = s.(name);
else
    value = defaultValue;
end
end
