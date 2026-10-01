function report = otfs_tr_save_report(cfg, result, ~, outputRoot)
%otfs_tr_save_report Prepare report paths and write the text metrics report.

if nargin < 4 || strlength(string(outputRoot)) == 0
    outputRoot = cfg.resultRoot;
end
timestamp = string(datetime("now", "Format", "yyyyMMdd_HHmmss"));
runDirectory = fullfile(outputRoot, timestamp);
if ~exist(runDirectory, "dir")
    mkdir(runDirectory);
end

lines = [
    "OTFS-TR acceptance report"
    "timestamp = " + timestamp
    "TX address = " + cfg.txAddress
    "RX address = " + cfg.rxAddress
    "TX AWGN evidence available = " + localResultField(result, ...
        "txAwgnEvidenceAvailable", false)
    "TX whole-waveform AWGN enabled = " + localTxAwgnField(result, ...
        "enabled", NaN)
    "TX configured injected SNR = " + localTxAwgnField(result, ...
        "configuredSnrDb", NaN) + " dB"
    "TX actual injected SNR = " + localTxAwgnField(result, ...
        "actualInjectedSnrDb", NaN) + " dB"
    "TX AWGN seed = " + localTxAwgnField(result, "seed", NaN)
    "TX AWGN peak-protection scale = " + localTxAwgnField(result, ...
        "peakProtectionScale", NaN)
    "requested equivalent Doppler/CFO = " + result.requestedDopplerHz + " Hz"
    "CFO assessment source = " + localResultField(result, ...
        "cfoAssessmentSource", "configured_cfo")
    "estimated CFO = " + result.cfoEstimateHz + " Hz"
    "tested equivalent CFO magnitude = " + ...
        result.acceptance.testedDopplerHz + " Hz"
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
    "shared MP noise-calibration frames = " + ...
        localResultField(result, "sharedMpNoiseCalibrationFrames", 0)
    "median effective MP noise variance = " + ...
        localResultField(result, "sigmaEffectiveMedian", NaN)
    "median MP noise-calibration ratio = " + ...
        localResultField(result, "mpNoiseCalibrationRatioMedian", NaN)
    "median final MP iterations = " + ...
        localResultField(result, "mpIterationMedian", NaN)
    "maximum final MP iterations = " + ...
        localResultField(result, "mpIterationMaximum", NaN)
    "frames reaching MP iteration limit = " + ...
        localResultField(result, "mpMaximumIterationFrames", 0)
    "MP converged frames = " + ...
        localResultField(result, "mpConvergedFrames", 0)
    "frame parallel requested = " + ...
        localFrameParallelField(result, "requested", false)
    "frame parallel used = " + ...
        localFrameParallelField(result, "used", false)
    "frame parallel status = " + ...
        localFrameParallelField(result, "status", "unavailable")
    "frame parallel workers = " + ...
        localFrameParallelField(result, "actualWorkers", 0)
    "frame detection elapsed = " + ...
        localFrameParallelField(result, ...
        "detectionElapsedSeconds", NaN) + " s"
    "frame aggregation elapsed = " + ...
        localFrameParallelField(result, ...
        "aggregationElapsedSeconds", NaN) + " s"
    "modulation = " + cfg.MMod + "-QAM"
    "scenario = " + cfg.scenarioName
    "software target BER = " + localResultField(cfg, ...
        "softwareTargetBer", cfg.maximumBer)
    "effective BER limit = " + cfg.maximumBer
    "software target spectral efficiency = " + localResultField(cfg, ...
        "softwareTargetSpectralEfficiency", ...
        cfg.minimumSpectralEfficiency) + " bit/s/Hz"
    "effective minimum spectral efficiency = " + ...
        cfg.minimumSpectralEfficiency + " bit/s/Hz"
    "waveform version = " + localResultField(cfg, "waveformVersion", 1)
    "nominal bandwidth = " + cfg.signalBandwidthHz + " Hz"
    "design bit rate = " + cfg.designBitRateBps + " bit/s"
    "design spectral efficiency = " + cfg.designSpectralEfficiency + " bit/s/Hz"
    "reference mode = " + localResultField(result, ...
        "referenceMode", "legacy-repeated")
    "reference alignment pass = " + result.acceptance.referenceAlignmentPass
    "header CRC failures = " + localResultField(result, ...
        "headerCrcFailures", 0)
    "air case code mismatches = " + localResultField(result, ...
        "caseCodeMismatches", 0)
    "air case code confirmed = " + localResultField(result, ...
        "airCaseCodeConfirmed", false)
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
    "application transmitted text = " + localApplicationField(result, ...
        "transmittedText", "")
    "application decoded text = " + localApplicationField(result, ...
        "decodedText", "")
    "application CRC pass = " + localApplicationField(result, ...
        "crcPass", false)
    "application matching frames = " + localApplicationField(result, ...
        "consistentFrames", 0)
    "application pass = " + localApplicationField(result, "pass", true)
    "valid frames = " + result.validFrames
    "minimum valid frames = " + cfg.minimumValidFrames
    "total bits = " + result.totalBits
    "received bits for transfer rate = " + ...
        localResultField(result, "receivedBitsForRate", result.totalBits)
    "receive duration = " + ...
        localResultField(result, "receiveDurationSeconds", NaN) + " s"
    "transfer rate = " + ...
        localResultField(result, "transferRateBps", NaN) + " bit/s"
    "transfer rate = " + ...
        localResultField(result, "transferRateBps", NaN)/1e6 + " Mbit/s"
    "total errors = " + result.totalErrors
    "BER = " + result.ber
    "zero-error 95% BER upper bound = " + result.acceptance.zeroErrorBerUpper95
    "zero-error confidence pass = " + result.acceptance.zeroErrorConfidencePass
    "radio pass = " + result.acceptance.radioPass
    "overall pass = " + result.acceptance.pass
    "application and core overall pass = " + ...
        localResultField(result, "overallPass", result.acceptance.pass)
    ];
reportPath = fullfile(runDirectory, "acceptance_report.txt");
writelines(lines, reportPath);

report = struct();
report.directory = string(runDirectory);
report.matFile = string(fullfile(runDirectory, "otfs_tr_result.mat"));
report.textFile = string(reportPath);
end

function value = localApplicationField(result, name, defaultValue)
if isfield(result, "application") && isfield(result.application, name)
    value = result.application.(name);
else
    value = defaultValue;
end
end

function value = localFrameParallelField(result, name, defaultValue)
if isfield(result, "frameParallelInfo") && ...
        isfield(result.frameParallelInfo, name)
    value = result.frameParallelInfo.(name);
else
    value = defaultValue;
end
end

function value = localResultField(result, name, defaultValue)
if isfield(result, name)
    value = result.(name);
else
    value = defaultValue;
end
end

function value = localTxAwgnField(result, name, defaultValue)
if isfield(result, "txAwgn") && isfield(result.txAwgn, name)
    value = result.txAwgn.(name);
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
