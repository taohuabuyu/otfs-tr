function [gridWithPilot, dataMask] = addpilot( ...
        dataGrid, pilot, nPilot, mPilot, mMax, nMax)
%addpilot Insert one DD pilot and clear its rectangular guard region.
[N, M] = size(dataGrid);
gridWithPilot = dataGrid;
dataMask = true(N, M);

rowStart = max(1, nPilot - nMax);
rowEnd = min(N, nPilot + nMax);
colStart = max(1, mPilot - mMax);
colEnd = min(M, mPilot + mMax);

gridWithPilot(rowStart:rowEnd, colStart:colEnd) = 0;
dataMask(rowStart:rowEnd, colStart:colEnd) = false;
gridWithPilot(nPilot, mPilot) = pilot;
end

