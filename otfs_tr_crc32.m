function crc = otfs_tr_crc32(bytes)
%otfs_tr_crc32 Calculate the standard reflected CRC-32 of uint8 data.

bytes = uint8(bytes(:));
crc = uint32(hex2dec("FFFFFFFF"));
polynomial = uint32(hex2dec("EDB88320"));
for byteIndex = 1:numel(bytes)
    crc = bitxor(crc, uint32(bytes(byteIndex)));
    for bitIndex = 1:8
        if bitand(crc, uint32(1)) ~= 0
            crc = bitxor(bitshift(crc, -1), polynomial);
        else
            crc = bitshift(crc, -1);
        end
    end
end
crc = bitxor(crc, uint32(hex2dec("FFFFFFFF")));
end
