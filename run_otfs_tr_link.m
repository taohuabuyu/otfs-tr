function result = run_otfs_tr_link(referenceFile, captureFile)
%run_otfs_tr_link Compatibility alias for saved-file offline comparison.
%
% TX and RX hardware operations are intentionally separate. Use
% run_otfs_tr_transmitter and run_otfs_tr_receiver in two MATLAB sessions,
% then call this function or run_otfs_tr_offline_decode afterward.

if nargin < 1
    referenceFile = "";
end
if nargin < 2
    captureFile = "";
end
result = run_otfs_tr_offline_decode(referenceFile, captureFile);
end
