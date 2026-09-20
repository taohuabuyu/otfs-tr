function result = otfs_tr_simulate_link(cfg, cfoHz, snrDb)
%otfs_tr_simulate_link Run a deterministic non-hardware flat-link simulation.

arguments
    cfg (1,1) struct
    cfoHz (1,1) double
    snrDb (1,1) double = Inf
end

otfs_tr_validate_config(cfg);
[txSignal, reference, params, training] = otfs_tr_build_waveform(cfg);
ratio = round(cfg.fsRx/cfg.fsTx);
rx20 = resample(txSignal, ratio, 1);
rx20 = rx20(1:min(cfg.rxSamplesPerFrame, numel(rx20)));
n = (0:numel(rx20)-1).';
flatChannel = 0.72*exp(1j*0.37);
rx20 = flatChannel*rx20 .* exp(1j*2*pi*cfoHz/cfg.fsRx*n);
if isfinite(snrDb)
    signalPower = mean(abs(rx20).^2);
    noisePower = signalPower/10^(snrDb/10);
    noise = sqrt(noisePower/2) * ...
        (randn(size(rx20)) + 1j*randn(size(rx20)));
    rx20 = rx20 + noise;
end

processed = wide_rx_process_capture(rx20, training, params, ...
    reference, cfg);
result = otfs_tr_finalize_result(processed, cfoHz, cfg);
result.snrDb = snrDb;
result.acceptance = otfs_tr_evaluate_acceptance(cfg, result, struct());
end
