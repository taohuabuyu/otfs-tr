function cfg = otfs_tr_apply_equivalent_cfo(cfg, equivalentCfoHz)
%otfs_tr_apply_equivalent_cfo Tune TX while keeping the RX center fixed.
%
% The request convention is equivalentCfoHz = fRX - fTX. Consequently,
% the nominal received baseband offset is fTX - fRX = -equivalentCfoHz.

validateattributes(equivalentCfoHz, {'numeric'}, ...
    {'scalar', 'real', 'finite'});
validateattributes(cfg.rxCenterFrequencyHz, {'numeric'}, ...
    {'scalar', 'real', 'finite', 'positive'});
cfg.equivalentDopplerHz = double(equivalentCfoHz);
cfg.txCenterFrequencyHz = cfg.rxCenterFrequencyHz - ...
    cfg.equivalentDopplerHz;
end
