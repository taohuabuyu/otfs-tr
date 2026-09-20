function crcBits = otfs_tr_crc8(dataBits)
%otfs_tr_crc8 Compute CRC-8/ATM bits, polynomial x^8+x^2+x+1.

dataBits = logical(dataBits(:).');
register = uint8(0);
polynomial = uint8(hex2dec("07"));
for bitIndex = 1:numel(dataBits)
    feedback = bitget(register, 8) ~= dataBits(bitIndex);
    register = bitshift(register, 1);
    if feedback
        register = bitxor(register, polynomial);
    end
end
crcBits = de2bi(register, 8, "left-msb").';
crcBits = double(crcBits);
end
