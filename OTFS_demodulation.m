function y = OTFS_demodulation(N, M, r)
%OTFS_demodulation Wigner transform followed by the SFFT.
rMatrix = reshape(r, M, N);
Y = fft(rMatrix)/sqrt(M);
Y = Y.';
y = ifft(fft(Y).').'/sqrt(N/M);
end

