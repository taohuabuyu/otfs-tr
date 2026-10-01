function [txSignalForRadio, info] = otfs_tr_add_tx_awgn(txSignal, cfg)
%otfs_tr_add_tx_awgn Add reproducible AWGN to the complete TX waveform.
% The composite waveform keeps the original average power when possible,
% then receives a final common scale to satisfy the hardware peak limit.

validateattributes(txSignal, {'numeric'}, ...
    {'vector', 'nonempty', 'finite'});
signalPower = mean(abs(txSignal).^2);
if signalPower <= 0
    error("otfs_tr:ZeroPowerTxSignal", ...
        "TX AWGN requires a waveform with positive average power.");
end

enabled = isfield(cfg, "enableTxAwgn") && logical(cfg.enableTxAwgn);
configuredSnrDb = Inf;
seed = NaN;
if isfield(cfg, "txAwgnSnrDb")
    configuredSnrDb = double(cfg.txAwgnSnrDb);
end
if isfield(cfg, "txAwgnSeed")
    seed = double(cfg.txAwgnSeed);
end

noise = zeros(size(txSignal), "like", txSignal);
targetNoisePower = 0;
averagePowerScale = 1;
if enabled
    stream = RandStream("mt19937ar", "Seed", seed);
    unitNoise = complex(randn(stream, size(txSignal)), ...
        randn(stream, size(txSignal))) / sqrt(2);
    unitNoisePower = mean(abs(unitNoise).^2);
    targetNoisePower = signalPower / 10^(configuredSnrDb/10);
    noise = cast(unitNoise * sqrt(targetNoisePower/unitNoisePower), ...
        "like", txSignal);
    composite = txSignal + noise;
    averagePowerScale = sqrt(signalPower/mean(abs(composite).^2));
    composite = averagePowerScale*composite;
else
    composite = txSignal;
end

peakBeforeProtection = max(abs(composite));
peakProtectionScale = min(1, cfg.hardwareTxPeak/peakBeforeProtection);
txSignalForRadio = peakProtectionScale*composite;
commonScale = averagePowerScale*peakProtectionScale;
transmittedSignalPower = mean(abs(commonScale*txSignal).^2);
transmittedNoisePower = mean(abs(commonScale*noise).^2);
actualInjectedSnrDb = Inf;
if enabled
    actualInjectedSnrDb = 10*log10( ...
        transmittedSignalPower/transmittedNoisePower);
end

info = struct( ...
    "enabled", enabled, ...
    "configuredSnrDb", configuredSnrDb, ...
    "actualInjectedSnrDb", actualInjectedSnrDb, ...
    "seed", seed, ...
    "wholeWaveform", true, ...
    "originalSignalPower", signalPower, ...
    "targetNoisePower", targetNoisePower, ...
    "generatedNoisePower", mean(abs(noise).^2), ...
    "averagePowerScale", averagePowerScale, ...
    "peakProtectionScale", peakProtectionScale, ...
    "totalCommonScale", commonScale, ...
    "outputPower", mean(abs(txSignalForRadio).^2), ...
    "peakBeforeProtection", peakBeforeProtection, ...
    "outputPeak", max(abs(txSignalForRadio)));
end
