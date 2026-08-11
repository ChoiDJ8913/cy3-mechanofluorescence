function [Sgnl, Bgnd] = MTView_v2(Peaks, movie1, fileName, filePath, avgLim, opts)
% MTView_v2  Publication-quality drop-in replacement for MTView.
%
%   [Sgnl, Bgnd] = MTView_v2(Peaks, movie1, fileName, filePath, avgLim)
%   [Sgnl, Bgnd] = MTView_v2(..., opts)
%
%   Requires mt_label.m and mt_labelpos.m on the path (same folder is fine).
%
%   The numerical output (Sgnl, Bgnd, Fluor.mat) is IDENTICAL to MTView.
%   Only the rendering changed:
%     saveas        -> exportgraphics at 600 dpi (saveas cannot set dpi)
%     figure size   -> centimetres, so fonts print at their true size
%     fonts         -> Arial 8 pt
%     peak numbers  -> plain black text, kept inside the axes
%     'Time (msec)' -> 'Frame'  (the axis is frame index, not milliseconds)
%     pixel axes    -> kept (opts.ShowPixelAxes)
%     scale bar     -> optional, from opts.PixelSize_nm
%     TIFF          -> written alongside each PNG
%
%   opts fields (all optional):
%     Resolution      600
%     FontName        'Arial'
%     FontSize        8
%     PanelWidth_cm   8.5        8.5 = single column, 17.5 = double
%     Colormap        'jet'      'turbo' or 'parula' are better perceptually
%     ShowPixelAxes   true
%     TextColor       [0 0 0]    peak numbers and scale bar text
%     LabelStyle      'plain'    'plain' | 'halo' | 'box'
%     HaloColor       [1 1 1]    only used by 'halo'
%     HaloWidth       0.4        points
%     RingColor       [1 1 1]    circle line
%     RingEdgeColor   [0 0 0]    dark edge under the circle, [] to disable
%     PixelSize_nm    []         e.g. 91.7; enables the scale bar
%     ScaleBar_um     2
%     SaveTIFF        true
%     SavePeakTraces  true
%     TraceYLim       []         [] = auto; was hard-coded [-50 550]
%
%   Example
%     opts.PixelSize_nm = 91.7;
%     [S,B] = MTView_v2(Peaks, movie1, fileName, filePath, [100 500], opts);

if nargin < 6, opts = struct(); end
opts = setdefaults(opts, struct( ...
    'Resolution',     600, ...
    'FontName',       'Arial', ...
    'FontSize',       8, ...
    'PanelWidth_cm',  8.5, ...
    'Colormap',       'jet', ...
    'ShowPixelAxes',  true, ...
    'TextColor',      [0 0 0], ...
    'LabelStyle',     'plain', ...
    'HaloColor',      [1 1 1], ...
    'HaloWidth',      0.4, ...
    'RingColor',      [1 1 1], ...
    'RingEdgeColor',  [0 0 0], ...
    'PixelSize_nm',   [], ...
    'ScaleBar_um',    2, ...
    'SaveTIFF',       true, ...
    'SavePeakTraces', true, ...
    'TraceYLim',      []));

movie1 = double(movie1);
h = size(movie1, 1);
N = size(movie1, 3);

avgFrame = mean(movie1, 3);

PeakR = 5;             % peak radius  (unchanged)
exR   = PeakR + 2;     % background annulus outer radius (unchanged)

minX = min(Peaks(:, 1)) - exR;
maxX = max(Peaks(:, 1)) + exR;
minY = min(Peaks(:, 2)) - exR;
maxY = max(Peaks(:, 2)) + exR;
NPeaks = size(Peaks, 1);
fprintf('Total %3d Peaks \n\n', NPeaks);

[~, nameOnly, ~] = fileparts(fileName);
outputFolder = fullfile(filePath, [nameOnly '_Output']);
if ~exist(outputFolder, 'dir'), mkdir(outputFolder); end

% ------------------------------------------------------------------
% Panel 1 : average frame with detected peaks
% ------------------------------------------------------------------
fig = newpanel(opts, opts.PanelWidth_cm, opts.PanelWidth_cm);
ax  = axes('Parent', fig);
imagesc(ax, avgFrame, avgLim);
colormap(ax, feval(opts.Colormap, 256));
set(ax, 'YDir', 'reverse', 'Box', 'on');
axis(ax, 'equal');
axis(ax, [minX maxX minY maxY]);     % limits must be final before placing labels
hold(ax, 'on');
for i = 1:NPeaks
    drawring(ax, Peaks(i,1), Peaks(i,2), PeakR, opts, 0.75);
    [tx, ty, ha, va] = mt_labelpos(ax, Peaks(i,1), Peaks(i,2), PeakR);
    mt_label(ax, tx, ty, num2str(i), opts, ...
             'FontName', opts.FontName, 'FontSize', max(opts.FontSize-1, 6), ...
             'HorizontalAlignment', ha, 'VerticalAlignment', va);
end
hold(ax, 'off');
pixelaxes(ax, opts);
if ~isempty(opts.PixelSize_nm)
    addscalebar(ax, opts.PixelSize_nm, opts.ScaleBar_um, opts);
end
styleaxes(ax, opts);
exportpanel(fig, fullfile(outputFolder, 'AverageFrame'), opts);
close(fig);

% ------------------------------------------------------------------
% Signal / background extraction  (IDENTICAL to MTView)
% ------------------------------------------------------------------
Sgnl = zeros(NPeaks, N);
Bgnd = zeros(NPeaks, N);

[PX, PY] = meshgrid(-exR:exR, -exR:exR);
PeakI = find(PX.^2 + PY.^2 <= PeakR^2);
BgndI = find((PX.^2 + PY.^2 >= PeakR^2) & (PX.^2 + PY.^2 <= exR^2));
for i = 1:NPeaks
    xi = round(Peaks(i, 1));
    yi = round(Peaks(i, 2));
    pkIi = h * (xi + PX(PeakI) - 1) + yi + PY(PeakI);
    bgIi = h * (xi + PX(BgndI) - 1) + yi + PY(BgndI);
    for k = 1:N
        framek = movie1(:, :, k);
        Bgnd(i, k) = mean(framek(bgIi));
        Sgnl(i, k) = mean(framek(pkIi)) - Bgnd(i, k);
    end
end

% ------------------------------------------------------------------
% Panels 2 and 3 : background and signal heat maps
% ------------------------------------------------------------------
heatpanel(Bgnd, 'Background intensity (counts)', ...
          fullfile(outputFolder, 'BackgroundIntensity'), opts);
heatpanel(Sgnl, 'Signal intensity (counts)', ...
          fullfile(outputFolder, 'SignalIntensity'), opts);

% ------------------------------------------------------------------
% Per-peak traces
% ------------------------------------------------------------------
if opts.SavePeakTraces
    for i = 1:NPeaks
        fig = newpanel(opts, opts.PanelWidth_cm, opts.PanelWidth_cm * 0.62);
        ax  = axes('Parent', fig);
        plot(ax, 1:N, Bgnd(i, :), 'Color', [0 0 0], 'LineWidth', 0.75);
        hold(ax, 'on');
        plot(ax, 1:N, Sgnl(i, :), 'Color', [0.85 0.10 0.10], 'LineWidth', 0.75);
        hold(ax, 'off');
        xlabel(ax, 'Frame');
        ylabel(ax, 'Intensity (counts)');
        xlim(ax, [1 N]);
        if ~isempty(opts.TraceYLim), ylim(ax, opts.TraceYLim); end
        legend(ax, {'Background', 'Signal'}, 'Box', 'off', 'Location', 'best');
        title(ax, sprintf('Peak %d  (%.1f, %.1f)', i, Peaks(i,1), Peaks(i,2)), ...
              'FontWeight', 'normal');
        styleaxes(ax, opts);
        exportpanel(fig, fullfile(outputFolder, sprintf('Peak_%03d', i)), opts);
        close(fig);
    end
end

save(fullfile(outputFolder, 'Fluor.mat'), 'Sgnl', 'Bgnd');
fprintf('All graphs and data saved in folder: %s\n', outputFolder);
end


% ======================================================================
% helpers
% ======================================================================
function pixelaxes(ax, opts)
if opts.ShowPixelAxes
    set(ax, 'XTickMode', 'auto', 'YTickMode', 'auto');
    xlabel(ax, 'x (pixel)');
    ylabel(ax, 'y (pixel)');
else
    set(ax, 'XTick', [], 'YTick', []);
end
end


function heatpanel(M, cbLabel, outBase, opts)
fig = newpanel(opts, opts.PanelWidth_cm, opts.PanelWidth_cm * 0.62);
ax  = axes('Parent', fig);
imagesc(ax, M, [min(M(:)) max(M(:))]);
xlabel(ax, 'Frame');
ylabel(ax, 'Molecule');
cb = colorbar(ax, 'EastOutside');
cb.Label.String   = cbLabel;
cb.FontName       = opts.FontName;
cb.FontSize       = opts.FontSize;
cb.Label.FontSize = opts.FontSize;
colormap(ax, feval(opts.Colormap, 256));
styleaxes(ax, opts);
exportpanel(fig, outBase, opts);
close(fig);
end


function fig = newpanel(opts, w_cm, h_cm)
fig = figure('Color', 'w', 'Units', 'centimeters', 'Visible', 'off');
fig.Position      = [2 2 w_cm h_cm];
fig.PaperUnits    = 'centimeters';
fig.PaperPosition = [0 0 w_cm h_cm];
fig.PaperSize     = [w_cm h_cm];
end


function styleaxes(ax, opts)
set(ax, 'FontName', opts.FontName, 'FontSize', opts.FontSize, ...
        'LineWidth', 0.75, 'TickDir', 'out', 'Layer', 'top');
set(findall(ax.Parent, '-property', 'FontName'), 'FontName', opts.FontName);
end


function exportpanel(fig, outBase, opts)
if exist('exportgraphics', 'file')
    exportgraphics(fig, [outBase '.png'], 'Resolution', opts.Resolution, ...
                   'BackgroundColor', 'white');
    if opts.SaveTIFF
        exportgraphics(fig, [outBase '.tiff'], 'Resolution', opts.Resolution, ...
                       'BackgroundColor', 'white');
    end
else   % MATLAB older than R2020a
    print(fig, [outBase '.png'],  '-dpng',  sprintf('-r%d', opts.Resolution));
    if opts.SaveTIFF
        print(fig, [outBase '.tiff'], '-dtiff', sprintf('-r%d', opts.Resolution));
    end
end
end


function drawring(ax, x, y, r, opts, lw)
t  = 2*pi*(0:0.02:1);
xd = x + r*cos(t);
yd = y + r*sin(t);
if ~isempty(opts.RingEdgeColor)
    plot(ax, xd, yd, '-', 'Color', opts.RingEdgeColor, 'LineWidth', lw + 1.0);
end
plot(ax, xd, yd, '-', 'Color', opts.RingColor, 'LineWidth', lw);
end


function addscalebar(ax, pixelSize_nm, bar_um, opts)
xl = xlim(ax); yl = ylim(ax);
barPx = (bar_um * 1000) / pixelSize_nm;
pad   = 0.06 * diff(xl);
x0 = xl(2) - pad - barPx;
y0 = yl(2) - 0.10 * diff(yl);
hold(ax, 'on');
if ~isempty(opts.RingEdgeColor)
    plot(ax, [x0 x0+barPx], [y0 y0], '-', 'Color', opts.RingEdgeColor, 'LineWidth', 3.0);
end
plot(ax, [x0 x0+barPx], [y0 y0], '-', 'Color', opts.RingColor, 'LineWidth', 2.0);
mt_label(ax, x0 + barPx/2, y0 - 0.03*diff(yl), sprintf('%g \\mum', bar_um), opts, ...
         'HorizontalAlignment', 'center', 'VerticalAlignment', 'top', ...
         'FontName', opts.FontName, 'FontSize', opts.FontSize);
hold(ax, 'off');
end


function s = setdefaults(s, d)
f = fieldnames(d);
for i = 1:numel(f)
    if ~isfield(s, f{i})
        s.(f{i}) = d.(f{i});
    end
end
end
