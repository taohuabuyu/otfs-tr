function [transferRateBps, receiveDurationSeconds] = ...
        otfs_tr_calculate_transfer_rate(receivedBits, radioStatus, fsRx)
%otfs_tr_calculate_transfer_rate Calculate received bits per receive second.

validateattributes(receivedBits, {'numeric'}, ...
    {'scalar', 'real', 'finite', 'nonnegative'});

receiveDurationSeconds = localField(radioStatus, ...
    "captureDurationSeconds", NaN);
if ~(isnumeric(receiveDurationSeconds) && ...
        isscalar(receiveDurationSeconds) && ...
        isfinite(receiveDurationSeconds) && receiveDurationSeconds > 0)
    totalReceivedSamples = localField(radioStatus, ...
        "totalReceivedSamples", NaN);
    if isnumeric(totalReceivedSamples) && isscalar(totalReceivedSamples) && ...
            isfinite(totalReceivedSamples) && totalReceivedSamples > 0 && ...
            isnumeric(fsRx) && isscalar(fsRx) && ...
            isfinite(fsRx) && fsRx > 0
        receiveDurationSeconds = totalReceivedSamples/fsRx;
    else
        receiveDurationSeconds = NaN;
    end
end

if isfinite(receiveDurationSeconds) && receiveDurationSeconds > 0
    transferRateBps = double(receivedBits)/receiveDurationSeconds;
else
    transferRateBps = NaN;
end
end

function value = localField(s, name, defaultValue)
if isstruct(s) && isfield(s, name)
    value = s.(name);
else
    value = defaultValue;
end
end
