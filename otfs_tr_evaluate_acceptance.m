function acceptance = otfs_tr_evaluate_acceptance(cfg, result, radioStatus)
%otfs_tr_evaluate_acceptance Evaluate explicit OTFS-TR acceptance criteria.

if nargin < 3
    radioStatus = struct();
end

acceptance = struct();
acceptance.berLimit = cfg.maximumBer;
acceptance.measuredBer = result.ber;
acceptance.minimumTestBits = cfg.minimumTestBits;
acceptance.totalBits = result.totalBits;
acceptance.testBitsPass = result.totalBits >= cfg.minimumTestBits;
acceptance.minimumValidFrames = cfg.minimumValidFrames;
acceptance.validFrames = result.validFrames;
acceptance.validFramesPass = result.validFrames >= cfg.minimumValidFrames;
acceptance.minimumDopplerHz = cfg.minimumDopplerHz;
acceptance.testedDopplerHz = abs(result.requestedDopplerHz);
acceptance.dopplerPass = abs(result.requestedDopplerHz) > ...
    cfg.minimumDopplerHz;
acceptance.minimumSpectralEfficiency = cfg.minimumSpectralEfficiency;
acceptance.designSpectralEfficiency = cfg.designSpectralEfficiency;
acceptance.spectralEfficiencyPass = cfg.designSpectralEfficiency >= ...
    cfg.minimumSpectralEfficiency;
acceptance.cfoEstimatePass = isfield(result, "cfoEstimateHz") && ...
    isfinite(result.cfoEstimateHz);
acceptance.residualCfoPass = isfield(result, "residualCfoHz") && ...
    isfinite(result.residualCfoHz);

if result.totalErrors == 0 && result.totalBits > 0
    acceptance.zeroErrorBerUpper95 = 3/result.totalBits;
    acceptance.zeroErrorConfidencePass = ...
        acceptance.zeroErrorBerUpper95 < cfg.maximumBer;
else
    acceptance.zeroErrorBerUpper95 = NaN;
    acceptance.zeroErrorConfidencePass = true;
end
acceptance.berPass = isfinite(result.ber) && ...
    result.ber < cfg.maximumBer && acceptance.zeroErrorConfidencePass;

hasRadioStatus = ~isempty(fieldnames(radioStatus));
if hasRadioStatus
    onboardReplay = string(localValueField(radioStatus, ...
        "txExecutionMode", "host-streaming")) == "onboard-continuous";
    if onboardReplay
        txTransportPass = localLogicalField(radioStatus, ...
            "txOnboardReplayStarted", false) && ...
            localLogicalField(radioStatus, "txOnboardReplayStopped", false) && ...
            localLogicalField(radioStatus, "txNoApiError", false);
    else
        txTransportPass = ~localLogicalField( ...
            radioStatus, "anyTxUnderrun", false);
    end
    acceptance.txTransportPass = txTransportPass;
    acceptance.radioPass = radioStatus.txRepeatStarted && ...
        localLogicalField(radioStatus, "txCompleted", false) && ...
        txTransportPass && ...
        ~radioStatus.anyRxOverrun && ...
        localLogicalField(radioStatus, "captureComplete", false) && ...
        radioStatus.totalReceivedSamples > 0;
else
    acceptance.radioPass = true;
end
if ~cfg.requireNoRadioErrors
    acceptance.radioPass = true;
end

acceptance.pass = acceptance.berPass && acceptance.testBitsPass && ...
    acceptance.validFramesPass && ...
    acceptance.dopplerPass && acceptance.spectralEfficiencyPass && ...
    acceptance.cfoEstimatePass && acceptance.residualCfoPass && ...
    acceptance.radioPass;
end

function value = localValueField(s, name, defaultValue)
if isfield(s, name)
    value = s.(name);
else
    value = defaultValue;
end
end

function value = localLogicalField(s, name, defaultValue)
if isfield(s, name)
    value = logical(s.(name));
else
    value = defaultValue;
end
end
