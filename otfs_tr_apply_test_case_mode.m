function cfg = otfs_tr_apply_test_case_mode(cfg)
%otfs_tr_apply_test_case_mode Use every data bit for the MAT test case.

cfg.payloadMode = "test-case-bits";
cfg.waveformVersion = 4;
cfg.frameCaseIdBits = 32;
cfg.headerInformationBits = cfg.frameIdBits + cfg.frameCaseIdBits + ...
    cfg.frameCrcBits;
cfg.headerCodedBits = cfg.headerInformationBits * ...
    cfg.headerRepetition;
cfg.headerSymbolsPerFrame = ceil(cfg.headerCodedBits/cfg.MBits);
cfg.headerMappedBits = cfg.headerSymbolsPerFrame*cfg.MBits;
cfg.headerPaddingBits = cfg.headerMappedBits-cfg.headerCodedBits;
cfg.payloadSymbolsPerFrame = cfg.dataSymbolsPerFrame - ...
    cfg.headerSymbolsPerFrame;
cfg.payloadBitsPerFrame = cfg.payloadSymbolsPerFrame*cfg.MBits;
cfg.applicationEnabled = false;
cfg.applicationPacketBytes = 0;
cfg.applicationPacketBits = 0;
cfg.applicationMappedBitsPerFrame = 0;
cfg.berTestBitsPerFrame = cfg.payloadBitsPerFrame;
cfg.effectiveBitsPerFrame = cfg.berTestBitsPerFrame;
cfg.totalUniquePayloadBits = cfg.superframeLength * ...
    cfg.berTestBitsPerFrame;
cfg.minimumValidFrames = ceil(cfg.minimumTestBits / ...
    cfg.effectiveBitsPerFrame);
desiredDecodedFrames = ceil(cfg.minimumValidFrames * ...
    (1 + cfg.decodeFrameMarginRatio));
cfg.maxDecodedFrames = min([desiredDecodedFrames, ...
    cfg.availableCaptureFrames, cfg.superframeLength]);
end
