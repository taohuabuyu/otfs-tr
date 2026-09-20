function report = otfs_tr_save_report(cfg, result, radioStatus, outputRoot)
%otfs_tr_save_report Save reproducible MAT and text result artifacts.

if nargin < 4 || strlength(string(outputRoot)) == 0
    outputRoot = cfg.resultRoot;
end
timestamp = string(datetime("now", "Format", "yyyyMMdd_HHmmss"));
runDirectory = fullfile(outputRoot, timestamp);
if ~exist(runDirectory, "dir")
    mkdir(runDirectory);
end

save(fullfile(runDirectory, "otfs_tr_result.mat"), ...
    "cfg", "result", "radioStatus");
lines = [
    "OTFS-TR acceptance report"
    "timestamp = " + timestamp
    "TX address = " + cfg.txAddress
    "RX address = " + cfg.rxAddress
    "requested equivalent Doppler/CFO = " + result.requestedDopplerHz + " Hz"
    "estimated CFO = " + result.cfoEstimateHz + " Hz"
    "median residual CFO = " + result.residualCfoHz + " Hz"
    "SFO compensation enabled = " + localSfoField(result, "enabled", false)
    "SFO compensation applied = " + localSfoField(result, "applied", false)
    "estimated SFO = " + localSfoField(result, "estimatedPpm", NaN) + " ppm"
    "SFO status = " + localSfoField(result, "status", "unavailable")
    "fractional timing compensation enabled = " + ...
        localFractionalTimingField(result, "enabled", false)
    "fractional timing compensation applied = " + ...
        localFractionalTimingField(result, "applied", false)
    "fractional timing offset = " + ...
        localFractionalTimingField(result, "selectedOffsetSamples10", NaN) + ...
        " samples at 10 MHz"
    "fractional timing pilot-score improvement = " + ...
        localFractionalTimingField(result, "improvementRatio", NaN)
    "fractional timing status = " + ...
        localFractionalTimingField(result, "status", "unavailable")
    "DD-pilot CFO fallback frames = " + ...
        localResultField(result, "ddPilotCfoFallbackFrames", 0)
    "structured row-bias corrected frames = " + ...
        localResultField(result, "rowBiasCorrectedFrames", 0)
    "row-bias applications by Doppler row = [" + ...
        localVectorText(localResultField(result, ...
        "rowBiasApplicationCountByRow", zeros(cfg.N, 1))) + "]"
    "MP noise-calibration frames = " + ...
        localResultField(result, "mpNoiseCalibrationFrames", 0)
    "median effective MP noise variance = " + ...
        localResultField(result, "sigmaEffectiveMedian", NaN)
    "median MP noise-calibration ratio = " + ...
        localResultField(result, "mpNoiseCalibrationRatioMedian", NaN)
    "modulation = " + cfg.MMod + "-QAM"
    "waveform version = " + localResultField(cfg, "waveformVersion", 1)
    "nominal bandwidth = " + cfg.signalBandwidthHz + " Hz"
    "design bit rate = " + cfg.designBitRateBps + " bit/s"
    "design spectral efficiency = " + cfg.designSpectralEfficiency + " bit/s/Hz"
    "reference mode = " + localResultField(result, ...
        "referenceMode", "legacy-repeated")
    "reference alignment pass = " + result.acceptance.referenceAlignmentPass
    "header CRC failures = " + localResultField(result, ...
        "headerCrcFailures", 0)
    "duplicate frame IDs = " + localResultField(result, ...
        "duplicateFrameIds", 0)
    "sequence discontinuities = " + localResultField(result, ...
        "sequenceDiscontinuities", 0)
    "median equalized-symbol EVM = " + localResultField(result, ...
        "softEvmPercentMedian", NaN) + " %"
    "median residual EVM after common gain removal = " + ...
        localResultField(result, "residualEvmPercentMedian", NaN) + " %"
    "median MP decision confidence = " + localResultField(result, ...
        "decisionConfidenceMedian", NaN)
    "median common gain magnitude = " + localResultField(result, ...
        "commonGainMagnitudeMedian", NaN)
    "median common phase error = " + localResultField(result, ...
        "commonPhaseErrorDegMedian", NaN) + " deg"
    "bit errors by QAM bit plane = [" + ...
        localVectorText(localResultField(result, ...
        "bitErrorsByPlane", zeros(1, cfg.MBits))) + "]"
    "valid frames = " + result.validFrames
    "minimum valid frames = " + cfg.minimumValidFrames
    "total bits = " + result.totalBits
    "total errors = " + result.totalErrors
    "BER = " + result.ber
    "zero-error 95% BER upper bound = " + result.acceptance.zeroErrorBerUpper95
    "zero-error confidence pass = " + result.acceptance.zeroErrorConfidencePass
    "radio pass = " + result.acceptance.radioPass
    "overall pass = " + result.acceptance.pass
    ];
reportPath = fullfile(runDirectory, "acceptance_report.txt");
writelines(lines, reportPath);

report = struct();
report.directory = string(runDirectory);
report.matFile = string(fullfile(runDirectory, "otfs_tr_result.mat"));
report.textFile = string(reportPath);
end

function value = localResultField(result, name, defaultValue)
if isfield(result, name)
    value = result.(name);
else
    value = defaultValue;
end
end

function value = localVectorText(values)
value = strjoin(string(values(:).'), ", ");
end

function value = localSfoField(result, name, defaultValue)
if isfield(result, "sfoInfo") && isfield(result.sfoInfo, name)
    value = result.sfoInfo.(name);
else
    value = defaultValue;
end
end

function value = localFractionalTimingField(result, name, defaultValue)
if isfield(result, "fractionalTimingInfo") && ...
        isfield(result.fractionalTimingInfo, name)
    value = result.fractionalTimingInfo.(name);
else
    value = defaultValue;
end
end
