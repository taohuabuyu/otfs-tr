function [mappedBits, informationBits] = ...
        otfs_tr_encode_frame_header(frameId, cfg)
%otfs_tr_encode_frame_header Encode frame ID and CRC into repeated bits.

if frameId < 0 || frameId >= cfg.superframeLength || ...
        frameId ~= floor(frameId)
    error("otfs_tr:InvalidFrameId", ...
        "frameId must be an integer in [0, superframeLength-1].");
end

idBits = de2bi(frameId, cfg.frameIdBits, "left-msb").';
crcBits = otfs_tr_crc8(idBits);
if cfg.frameCrcBits ~= numel(crcBits)
    error("otfs_tr:UnsupportedFrameCrc", ...
        "The current frame header requires an 8-bit CRC.");
end
informationBits = [idBits; crcBits];
codedBits = repelem(informationBits, cfg.headerRepetition);
mappedBits = [codedBits; zeros(cfg.headerPaddingBits, 1)];
end
