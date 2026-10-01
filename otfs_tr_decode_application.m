function application = otfs_tr_decode_application(mappedBits, cfg)
%otfs_tr_decode_application Decode and validate one application packet.

application = struct("valid", false, "crcPass", false, ...
    "paddingPass", false, ...
    "decodedText", "", "payloadBytes", 0, "errorCode", "INVALID_PACKET");
mappedBits = logical(mappedBits(:));
if numel(mappedBits) < cfg.applicationMappedBitsPerFrame
    application.errorCode = "SHORT_PACKET";
    return;
end
mappedBits = mappedBits(1:cfg.applicationMappedBitsPerFrame);
packetBits = mappedBits(1:cfg.applicationPacketBits);
paddingBits = mappedBits(cfg.applicationPacketBits+1:end);
application.paddingPass = ~any(paddingBits);
packetRows = reshape(packetBits, 8, []).';
packet = uint8(bi2de(packetRows, "left-msb")).';

if ~isequal(packet(1:2), cfg.applicationMagic)
    application.errorCode = "MAGIC_MISMATCH";
    return;
end
if packet(3) ~= cfg.applicationProtocolVersion || ...
        packet(4) ~= cfg.applicationPayloadType
    application.errorCode = "VERSION_OR_TYPE_MISMATCH";
    return;
end

payloadLength = double(localBytesToUint16(packet(9:10)));
if payloadLength > cfg.applicationMaxPayloadBytes
    application.errorCode = "INVALID_LENGTH";
    return;
end
payloadFirst = 11;
payloadLast = payloadFirst + cfg.applicationMaxPayloadBytes - 1;
storedCrc = localBytesToUint32(packet(payloadLast+1:payloadLast+4));
calculatedCrc = otfs_tr_crc32(packet(1:payloadLast));
application.crcPass = storedCrc == calculatedCrc;
if ~application.crcPass
    application.errorCode = "CRC_FAILED";
    return;
end

payload = packet(payloadFirst:payloadFirst+payloadLength-1);
application.decodedText = string(native2unicode(payload, "UTF-8"));
application.payloadBytes = payloadLength;
application.valid = application.paddingPass;
if application.valid
    application.errorCode = "OK";
else
    application.errorCode = "PADDING_FAILED";
end
end

function value = localBytesToUint16(bytes)
value = bitor(bitshift(uint16(bytes(1)), 8), uint16(bytes(2)));
end

function value = localBytesToUint32(bytes)
value = bitor(bitshift(uint32(bytes(1)), 24), ...
    bitor(bitshift(uint32(bytes(2)), 16), ...
    bitor(bitshift(uint32(bytes(3)), 8), uint32(bytes(4)))));
end
