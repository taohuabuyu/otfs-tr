function cfg = otfs_tr_apply_software_targets(cfg, request)
%otfs_tr_apply_software_targets Apply requested targets without weakening
%the project's BER and design-spectral-efficiency acceptance limits.

cfg.scenarioName = request.scenario_name;
cfg.softwareTargetBer = request.target_ber;
cfg.softwareTargetSpectralEfficiency = ...
    request.target_spectral_efficiency;
cfg.maximumBer = min(cfg.maximumBer, request.target_ber);
cfg.minimumSpectralEfficiency = max(cfg.minimumSpectralEfficiency, ...
    request.target_spectral_efficiency);
cfg.minimumTestBits = max(floor(3/cfg.maximumBer)+1, ...
    cfg.targetTestBits);
cfg.minimumValidFrames = ceil(cfg.minimumTestBits / ...
    cfg.effectiveBitsPerFrame);
desiredDecodedFrames = ceil(cfg.minimumValidFrames * ...
    (1 + cfg.decodeFrameMarginRatio));
desiredDecodedFrames = max(desiredDecodedFrames, cfg.targetDecodedFrames);
cfg.maxDecodedFrames = min([desiredDecodedFrames, ...
    cfg.availableCaptureFrames, cfg.superframeLength]);
end
