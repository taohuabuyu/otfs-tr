function plotFiles = wide_rx_plot_diagnostics(results, params, plotDir, opts)
%wide_rx_plot_diagnostics Save and optionally display SDR diagnostic figures.
%
% Each diagnostic is saved twice:
%   .png for quick preview outside MATLAB
%   .fig for clickable, editable MATLAB figure inspection.

if nargin < 4
    opts = struct();
end
opts = localApplyPlotDefaults(opts);

if ~exist(plotDir, "dir")
    mkdir(plotDir);
end

plotFiles = strings(0, 1);
plotFiles = [plotFiles; localPlotRx20Amplitude(results, plotDir, opts)];
plotFiles = [plotFiles; localPlotPreambleSync(results, plotDir, opts)];
plotFiles = [plotFiles; localPlotRx10Amplitude(results, plotDir, opts)];
plotFiles = [plotFiles; localPlotBer(results, plotDir, opts)];
plotFiles = [plotFiles; localPlotErrorFrameGrid(results, params, plotDir, opts)];
plotFiles = [plotFiles; localPlotErrorBitPositions(results, plotDir, opts)];
plotFiles = plotFiles(strlength(plotFiles) > 0);
end

function opts = localApplyPlotDefaults(opts)
if ~isfield(opts, "showFigures")
    opts.showFigures = true;
end
if ~isfield(opts, "closeFigures")
    opts.closeFigures = ~opts.showFigures;
end
if opts.showFigures
    opts.figureVisible = "on";
else
    opts.figureVisible = "off";
end
end

function paths = localPlotRx20Amplitude(results, plotDir, opts)
fig = figure("Visible", opts.figureVisible, "Name", "20 MHz RX amplitude");
plot(abs(results.rx20), "LineWidth", 1);
grid on;
xlabel("20 MHz sample index");
ylabel("|r_{20}[n]|");
title("Received signal amplitude at 20 MHz");
paths = localSaveFigure(fig, fullfile(plotDir, "rx20_amplitude"), opts);
end

function paths = localPlotPreambleSync(results, plotDir, opts)
fig = figure("Visible", opts.figureVisible, "Name", "20 MHz preamble sync");
metric = results.coarseSync20.metric;
plot(metric, "LineWidth", 1);
grid on;
xlabel("20 MHz correlation start index");
ylabel("Normalized correlation");
title(sprintf("20 MHz preamble sync, CFO = %.2f Hz", ...
    localCfoEstimate(results)));
hold on;
if isfield(results.coarseSync20, "preambleStart20") && ...
        isfinite(results.coarseSync20.preambleStart20)
    xline(results.coarseSync20.preambleStart20, "r--", ...
        "Preamble start");
end
hold off;
paths = localSaveFigure(fig, fullfile(plotDir, ...
    "preamble_sync_correlation"), opts);
end

function paths = localPlotRx10Amplitude(results, plotDir, opts)
fig = figure("Visible", opts.figureVisible, "Name", "10 MHz RX amplitude");
plot(abs(results.rx10), "LineWidth", 1);
grid on;
xlabel("10 MHz sample index");
ylabel("|r_{10}[n]|");
title("Filtered and decimated received signal amplitude at 10 MHz");
paths = localSaveFigure(fig, fullfile(plotDir, "rx10_amplitude"), opts);
end

function paths = localPlotBer(results, plotDir, opts)
fig = figure("Visible", opts.figureVisible, "Name", "BER per frame");
frameIdx = (1:numel(results.ber)).';
stem(frameIdx, results.ber, "filled", "LineWidth", 1.2);
grid on;
xlabel("Payload frame index");
ylabel("BER");
title("BER per payload frame");
xlim([0.5, numel(results.ber) + 0.5]);
validBer = results.ber(isfinite(results.ber));
if ~isempty(validBer)
    ylim([0, max([0.02; validBer(:)]) * 1.1]);
end
paths = localSaveFigure(fig, fullfile(plotDir, "ber_per_frame"), opts);
end

function paths = localPlotErrorFrameGrid(results, params, plotDir, opts)
fig = figure("Visible", opts.figureVisible, "Name", "Worst frame DD grid");
frameIdx = localWorstFrame(results);
if isnan(frameIdx)
    text(0.1, 0.5, "No valid error frame to plot");
    axis off;
else
    rxGrid = results.frameDiagnostics(frameIdx).rxGrid;
    [delayGrid, dopplerGrid] = meshgrid(1:params.M, 1:params.N);
    surf(delayGrid, dopplerGrid, abs(rxGrid), ...
        "EdgeColor", [0.25 0.25 0.25], "FaceAlpha", 0.95);
    view(45, 35);
    grid on;
    colorbar;
    xlabel("Delay index");
    ylabel("Doppler index");
    zlabel("|Y[n,m]|");
    title(sprintf("Worst/error frame received OTFS grid, frame %d", ...
        frameIdx));
    hold on;
    scatter3(params.mPilot, params.nPilot, ...
        abs(rxGrid(params.nPilot, params.mPilot)), 70, "r", "filled", ...
        "MarkerEdgeColor", "k");
    hold off;
end
paths = localSaveFigure(fig, fullfile(plotDir, ...
    "error_frame_rx_grid_3d"), opts);
end

function paths = localPlotErrorBitPositions(results, plotDir, opts)
fig = figure("Visible", opts.figureVisible, "Name", "Bit error positions");
frameIdx = localWorstFrame(results);
if isnan(frameIdx)
    text(0.1, 0.5, "No bit errors to plot");
    axis off;
else
    bitErrors = results.frameDiagnostics(frameIdx).bitErrors;
    errorPositions = find(bitErrors);
    stem(errorPositions, ones(size(errorPositions)), "filled", ...
        "LineWidth", 1.1);
    grid on;
    xlabel("Bit index within payload data");
    ylabel("Error");
    title(sprintf("Bit error positions, frame %d", frameIdx));
    ylim([0, 1.2]);
    if ~isempty(bitErrors)
        xlim([1, numel(bitErrors)]);
    end
end
paths = localSaveFigure(fig, fullfile(plotDir, "error_bit_positions"), opts);
end

function cfoEstimateHz = localCfoEstimate(results)
if isfield(results, "cfoEstimateHz")
    cfoEstimateHz = results.cfoEstimateHz;
elseif isfield(results, "coarseSync20") && ...
        isfield(results.coarseSync20, "cfoEstimateHz")
    cfoEstimateHz = results.coarseSync20.cfoEstimateHz;
else
    cfoEstimateHz = NaN;
end
end

function frameIdx = localWorstFrame(results)
ber = results.ber(:);
if all(~isfinite(ber))
    frameIdx = NaN;
    return;
end
[~, frameIdx] = max(ber, [], "omitnan");
if ~isfinite(ber(frameIdx)) || ber(frameIdx) <= 0
    frameIdx = find(isfinite(ber), 1, "first");
end
end

function paths = localSaveFigure(fig, basePath, opts)
pngPath = basePath + ".png";
figPath = basePath + ".fig";
localHideAxesToolbars(fig);
exportgraphics(fig, pngPath, "Resolution", 150);
savefig(fig, figPath);
paths = [string(pngPath); string(figPath)];
if opts.closeFigures
    close(fig);
end
end

function localHideAxesToolbars(fig)
axesHandles = findall(fig, "Type", "axes");
for idx = 1:numel(axesHandles)
    ax = axesHandles(idx);
    if isprop(ax, "Toolbar") && ~isempty(ax.Toolbar)
        ax.Toolbar.Visible = "off";
    end
end
end
