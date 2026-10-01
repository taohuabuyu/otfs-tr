function [mappedBits, application] = otfs_tr_encode_application(request, cfg)
%otfs_tr_encode_application Encode one fixed-size UTF-8 application packet.

request = otfs_tr_validate_request(request, cfg);
if ~cfg.applicationEnabled
    error("otfs_tr:ApplicationRequires8Qam", ...
        "Application payload transport is enabled only for 8-QAM.");
end

payloadBytes = uint8(unicode2native(char(request.payload_text), "UTF-8"));
payloadArea = zeros(1, cfg.applicationMaxPayloadBytes, "uint8");
payloadArea(1:numel(payloadBytes)) = payloadBytes;
packet = [cfg.applicationMagic, uint8(cfg.applicationProtocolVersion), ...
    uint8(cfg.applicationPayloadType), ...
    zeros(1, 4, "uint8"), ...
    localUint16Bytes(uint16(numel(payloadBytes))), payloadArea];
packetCrc = otfs_tr_crc32(packet);
packet = [packet localUint32Bytes(packetCrc)];
packetRows = de2bi(packet, 8, "left-msb");
packetBits = reshape(packetRows.', [], 1);
mappedBits = [packetBits; zeros( ...
    cfg.applicationMappedBitsPerFrame-numel(packetBits), 1)];

application = struct();
application.enabled = true;
application.protocolVersion = cfg.applicationProtocolVersion;
application.transmittedText = request.payload_text;
application.payloadBytes = numel(payloadBytes);
application.packetCrc32 = packetCrc;
application.mappedBits = mappedBits;
end

function bytes = localUint16Bytes(value)
bytes = uint8([bitshift(value, -8), bitand(value, uint16(255))]);
end

function bytes = localUint32Bytes(value)
bytes = uint8([bitshift(value, -24), ...
    bitand(bitshift(value, -16), uint32(255)), ...
    bitand(bitshift(value, -8), uint32(255)), ...
    bitand(value, uint32(255))]);
end
