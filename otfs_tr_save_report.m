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
    "modulation = " + cfg.MMod + "-QAM"
    "nominal bandwidth = " + cfg.signalBandwidthHz + " Hz"
    "design bit rate = " + cfg.designBitRateBps + " bit/s"
    "design spectral efficiency = " + cfg.designSpectralEfficiency + " bit/s/Hz"
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

function value = localSfoField(result, name, defaultValue)
if isfield(result, "sfoInfo") && isfield(result.sfoInfo, name)
    value = result.sfoInfo.(name);
else
    value = defaultValue;
end
end
