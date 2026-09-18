function s = OTFS_modulation(N, M, x)
%OTFS_modulation ISFFT followed by the Heisenberg transform.
X = fft(ifft(x).').'/sqrt(M/N);
sMatrix = ifft(X.')*sqrt(M);
s = sMatrix(:);
end

