function server = run_otfs_tr_control_service(port)
%run_otfs_tr_control_service Start the length-prefixed JSON TCP endpoint.
%
% Messages use a four-byte unsigned big-endian length followed by UTF-8 JSON.
% Keep the returned tcpserver object alive while accepting software commands.

if nargin < 1
    port = 9001;
end
validateattributes(port, {'numeric'}, ...
    {'scalar', 'integer', '>=', 1, '<=', 65535});
server = tcpserver("0.0.0.0", port);
server.UserData = struct("phase", "length", "expectedBytes", 4);
configureCallback(server, "byte", 4, @localReceiveMessage);
fprintf("OTFS-TR control service listening on TCP port %d.\n", port);
end

function localReceiveMessage(server, ~)
state = server.UserData;
if state.phase == "length"
    lengthBytes = read(server, 4, "uint8");
    messageLength = localBytesToUint32(lengthBytes);
    if messageLength < 2 || messageLength > 1024*1024
        localWriteResponse(server, jsonencode(struct( ...
            "protocol_version", "1.0", "command", "", ...
            "code", 1001, ...
            "error_code", "INVALID_JSON", ...
            "message", "Invalid JSON message length.", ...
            "status", "failed")));
        localResetCallback(server);
        return;
    end
    server.UserData = struct("phase", "body", ...
        "expectedBytes", double(messageLength));
    configureCallback(server, "byte", double(messageLength), ...
        @localReceiveMessage);
    return;
end

body = read(server, state.expectedBytes, "uint8");
requestJson = native2unicode(uint8(body), "UTF-8");
responseJson = otfs_tr_handle_json(requestJson);
localWriteResponse(server, responseJson);
localResetCallback(server);
end

function localWriteResponse(server, responseJson)
body = uint8(unicode2native(char(string(responseJson)), "UTF-8"));
lengthBytes = localUint32Bytes(uint32(numel(body)));
write(server, [lengthBytes body], "uint8");
end

function localResetCallback(server)
server.UserData = struct("phase", "length", "expectedBytes", 4);
configureCallback(server, "byte", 4, @localReceiveMessage);
end

function value = localBytesToUint32(bytes)
bytes = uint8(bytes(:).');
value = bitor(bitshift(uint32(bytes(1)), 24), ...
    bitor(bitshift(uint32(bytes(2)), 16), ...
    bitor(bitshift(uint32(bytes(3)), 8), uint32(bytes(4)))));
end

function bytes = localUint32Bytes(value)
bytes = uint8([bitshift(value, -24), ...
    bitand(bitshift(value, -16), uint32(255)), ...
    bitand(bitshift(value, -8), uint32(255)), ...
    bitand(value, uint32(255))]);
end
