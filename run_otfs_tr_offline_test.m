function results = run_otfs_tr_offline_test()
%run_otfs_tr_offline_test Exercise the complete baseband chain at +/-600 kHz.

cfg = otfs_tr_config();
otfs_tr_validate_config(cfg);
offsets = [-abs(cfg.equivalentDopplerHz), abs(cfg.equivalentDopplerHz)];
resultCells = cell(numel(offsets), 1);
for index = 1:numel(offsets)
    fprintf("Offline OTFS-TR test at %+.0f Hz...\n", offsets(index));
    resultCells{index} = otfs_tr_simulate_link( ...
        cfg, offsets(index), cfg.offlineSnrDb);
    fprintf("estimated=%+.1f Hz, frames=%d, bits=%d, errors=%d, BER=%.6g, pass=%d\n", ...
        resultCells{index}.cfoEstimateHz, resultCells{index}.validFrames, ...
        resultCells{index}.totalBits, resultCells{index}.totalErrors, ...
        resultCells{index}.ber, resultCells{index}.acceptance.pass);
end
results = vertcat(resultCells{:});
end
