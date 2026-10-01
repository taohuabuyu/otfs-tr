function responseJson = otfs_tr_handle_json(requestJson)
%otfs_tr_handle_json Execute one v1 software command and return UTF-8 JSON.

command = "";
try
    request = jsondecode(char(string(requestJson)));
    if ~isstruct(request) || ~isscalar(request)
        error("otfs_tr:InvalidJsonRequest", ...
            "The JSON root must be one object.");
    end
    command = string(localField(request, "command", ""));
    response = localDispatch(request, command);
catch exception
    response = localErrorResponse(command, exception);
end
responseJson = string(jsonencode(response));
end

function response = localDispatch(request, command)
cfg = otfs_tr_config();
protocolVersion = string(localField(request, "protocol_version", ""));
if protocolVersion ~= cfg.controlProtocolVersion
    error("otfs_tr:UnsupportedProtocolVersion", ...
        "protocol_version must be %s.", cfg.controlProtocolVersion);
end
switch command
    case "start_test"
        normalized = otfs_tr_validate_request(request, cfg);
        txRun = run_otfs_tr_transmitter(normalized);
        response = struct( ...
            "protocol_version", cfg.controlProtocolVersion, ...
            "command", command, ...
            "local_run_id", txRun.localRunId, ...
            "code", 0, "error_code", "OK", ...
            "message", "Transmit stage completed.", ...
            "status", "completed", ...
            "rx_matlab_command", txRun.rxCommand, ...
            "reference_file", txRun.referenceFile);
    otherwise
        error("otfs_tr:UnsupportedCommand", ...
            "command must be start_test.");
end
end

function response = localErrorResponse(command, exception)
[code, errorCode] = localErrorCode(exception.identifier);
response = struct("protocol_version", "1.0", ...
    "command", command, ...
    "code", code, "error_code", errorCode, ...
    "message", string(exception.message), "status", "failed");
end

function [code, errorCode] = localErrorCode(identifier)
switch string(identifier)
    case "MATLAB:json:ExpectedValue"
        code = 1001;
        errorCode = "INVALID_JSON";
    case "otfs_tr:UnsupportedProtocolVersion"
        code = 1002;
        errorCode = "UNSUPPORTED_VERSION";
    case "otfs_tr:MissingRequestField"
        code = 1003;
        errorCode = "MISSING_REQUIRED_FIELD";
    case {"otfs_tr:InvalidPayloadText", "otfs_tr:InvalidPayloadLength"}
        code = 1005;
        errorCode = "INVALID_PAYLOAD";
    case "otfs_tr:InvalidRequestedCfo"
        code = 1006;
        errorCode = "INVALID_CFO";
    case {"otfs_tr:UnsupportedRequestField", ...
            "otfs_tr:UnsupportedRequestOption"}
        code = 1007;
        errorCode = "UNSUPPORTED_PARAMETER";
    case "otfs_tr:IncompletePair"
        code = 1008;
        errorCode = "CAPTURE_FILE_NOT_FOUND";
    otherwise
        code = 1999;
        errorCode = "INTERNAL_ERROR";
end
end

function value = localField(s, name, defaultValue)
if isfield(s, name)
    value = s.(name);
else
    value = defaultValue;
end
end
