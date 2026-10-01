function [frameId, isValid, informationBits, caseCode] = ...
        otfs_tr_decode_frame_header(mappedBits, cfg)
%otfs_tr_decode_frame_header Decode frame ID and optional air case code.

mappedBits = logical(mappedBits(:));
frameId = NaN;
isValid = false;
informationBits = zeros(0, 1);
caseCode = uint32(0);
if numel(mappedBits) < cfg.headerCodedBits
    return;
end

repeated = reshape(mappedBits(1:cfg.headerCodedBits), ...
    cfg.headerRepetition, cfg.headerInformationBits);
informationBits = sum(repeated, 1).' > cfg.headerRepetition/2;
idBits = informationBits(1:cfg.frameIdBits);
caseIdBits = 0;
if isfield(cfg, "frameCaseIdBits")
    caseIdBits = cfg.frameCaseIdBits;
end
if caseIdBits ~= 0 && caseIdBits ~= 32
    error("otfs_tr:InvalidAirCaseCode", ...
        "Only a 32-bit air case code is supported.");
end
caseBits = informationBits(cfg.frameIdBits+1: ...
    cfg.frameIdBits+caseIdBits);
crcBits = informationBits(cfg.frameIdBits+caseIdBits+1:end);
expectedCrc = logical(otfs_tr_crc8([idBits; caseBits]));
frameIdCandidate = bi2de(double(idBits.'), "left-msb");
isValid = isequal(crcBits, expectedCrc) && ...
    frameIdCandidate < cfg.superframeLength;
if isValid
    frameId = frameIdCandidate;
    if caseIdBits > 0
        caseCode = uint32(bi2de(double(caseBits.'), "left-msb"));
    end
end
end
