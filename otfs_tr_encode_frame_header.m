function [mappedBits, informationBits] = ...
        otfs_tr_encode_frame_header(frameId, cfg, caseCode)
%otfs_tr_encode_frame_header Encode frame ID, optional case code, and CRC.

if frameId < 0 || frameId >= cfg.superframeLength || ...
        frameId ~= floor(frameId)
    error("otfs_tr:InvalidFrameId", ...
        "frameId must be an integer in [0, superframeLength-1].");
end

idBits = de2bi(frameId, cfg.frameIdBits, "left-msb").';
caseIdBits = 0;
if isfield(cfg, "frameCaseIdBits")
    caseIdBits = cfg.frameCaseIdBits;
end
caseBits = zeros(0, 1);
if caseIdBits > 0
    if nargin < 3 || ~isa(caseCode, "uint32") || ~isscalar(caseCode) || ...
            caseIdBits ~= 32
        error("otfs_tr:InvalidAirCaseCode", ...
            "A uint32 case code is required in test-case mode.");
    end
    caseBits = de2bi(double(caseCode), 32, "left-msb").';
end
crcBits = otfs_tr_crc8([idBits; caseBits]);
if cfg.frameCrcBits ~= numel(crcBits)
    error("otfs_tr:UnsupportedFrameCrc", ...
        "The current frame header requires an 8-bit CRC.");
end
informationBits = [idBits; caseBits; crcBits];
codedBits = repelem(informationBits, cfg.headerRepetition);
mappedBits = [codedBits; zeros(cfg.headerPaddingBits, 1)];
end
