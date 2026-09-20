function [frameId, isValid, informationBits] = ...
        otfs_tr_decode_frame_header(mappedBits, cfg)
%otfs_tr_decode_frame_header Majority-decode a frame ID and validate CRC.

mappedBits = logical(mappedBits(:));
frameId = NaN;
isValid = false;
informationBits = zeros(0, 1);
if numel(mappedBits) < cfg.headerCodedBits
    return;
end

repeated = reshape(mappedBits(1:cfg.headerCodedBits), ...
    cfg.headerRepetition, cfg.headerInformationBits);
informationBits = sum(repeated, 1).' > cfg.headerRepetition/2;
idBits = informationBits(1:cfg.frameIdBits);
crcBits = informationBits(cfg.frameIdBits+1:end);
expectedCrc = logical(otfs_tr_crc8(idBits));
frameIdCandidate = bi2de(double(idBits.'), "left-msb");
isValid = isequal(crcBits, expectedCrc) && ...
    frameIdCandidate < cfg.superframeLength;
if isValid
    frameId = frameIdCandidate;
end
end
