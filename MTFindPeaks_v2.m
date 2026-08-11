function [Peaks, movie1, fileName, filePath] = MTFindPeaks_v2(avgLim, PeakR, ROIR, opts)
% MTFindPeaks_v2  Publication-quality drop-in replacement for MTFindPeaks.
%
%   [Peaks, movie1, fileName, filePath] = MTFindPeaks_v2(avgLim, PeakR, ROIR)
%   [...] = MTFindPeaks_v2(avgLim, PeakR, ROIR, opts)
%
%   Requires mt_label.m and mt_labelpos.m on the path (same folder is fine).
%
%   Peak detection is IDENTICAL to MTFindPeaks. What changed:
%     - the peak-detection overview is EXPORTED at 600 dpi. The original
%       saved nothing but Peaks.mat.
%     - figure sized in centimetres so fonts print at their true size
%     - peak numbers in plain black text, kept inside the axes
%     - pixel coordinate axes kept (opts.ShowPixelAxes)
%     - optional scale bar from opts.PixelSize_nm
%
%   opts fields (all optional):
%     Resolution      600
%     FontName        'Arial'
%     FontSize        8
%     PanelWidth_cm   8.5
%     Colormap        'jet'      'turbo' or 'parula' are better perceptually
%     ShowPixelAxes   true
%     TextColor       [0 0 0]
%     LabelStyle      'plain'    'plain' | 'halo' | 'box'
%     HaloColor       [1 1 1]
%     HaloWidth       0.4
%     RingColor       [1 1 1]    circle line
%     RingEdgeColor   [0 0 0]    dark edge under the circle, [] to disable
%     PixelSize_nm    []         e.g. 91.7; enables the scale bar
%     ScaleBar_um     2
%     SaveTIFF        true
%     SaveOverview    true
%     ShowIndex       true
%
%   Example
%     opts.PixelSize_nm = 91.7;
%     [Peaks, mv, fn, fp] = MTFindPeaks_v2([100 500], 7, 50, opts);

if nargin < 4, opts = struct(); end
opts = setdefaults(opts, struct( ...
    'Resolution',    600, ...
    'FontName',      'Arial', ...
    'FontSize',      8, ...
    'PanelWidth_cm', 8.5, ...
    'Colormap',      'jet', ...
    'ShowPixelAxes', true, ...
    'TextColor',     [0 0 0], ...
    'LabelStyle',    'plain', ...
    'HaloColor',     [1 1 1], ...
    'HaloWidth',     0.4, ...
    'RingColor',     [1 1 1], ...
    'RingEdgeColor', [0 0 0], ...
    'PixelSize_nm',  [], ...
    'ScaleBar_um',   2, ...
    'SaveTIFF',      true, ...
    'SaveOverview',  true, ...
    'ShowIndex',     true));

%% ---------------- load ----------------
[fileName, filePath] = uigetfile('*.mat', 'Select a MATLAB file');
if isequal(fileName, 0)
    disp('File selection cancelled.');
    Peaks = []; movie1 = []; return;
end
data = load(fullfile(filePath, fileName));
disp(fullfile(filePath, fileName))
if ~isfield(data, 'movie1')
    error('Check file')
end
movie1 = double(data.movie1);

[~, nameOnly, ~] = fileparts(fileName);
saveFileName = fullfile(filePath, [nameOnly '_peak.mat']);

V = movie1;
h = size(movie1, 1);
w = size(movie1, 2);
N = size(movie1, 3);

avgFrame = mean(movie1, 3);

%% ---------------- interactive windows ----------------
figImg = figure(1); clf(figImg);
set(figImg, 'Color', 'w', 'Name', 'Average frame');
axImg = axes('Parent', figImg);
imagesc(axImg, avgFrame, avgLim);
hold(axImg, 'on');
hBead = plot(axImg, NaN, NaN, 'Color', opts.RingColor, 'LineWidth', 1.5);
hold(axImg, 'off');
axis(axImg, 'equal');
colormap(axImg, feval(opts.Colormap, 256));
xlabel(axImg, 'x (pixel)');
ylabel(axImg, 'y (pixel)');
set(axImg, 'FontName', opts.FontName, 'FontSize', opts.FontSize, 'TickDir', 'out');

figTr = figure(2); clf(figTr);
set(figTr, 'Color', 'w', 'Name', 'Trace preview');
axTr = axes('Parent', figTr);
hFluor = plot(axTr, 1:N, NaN(1, N), 'r', 'LineWidth', 1);
xlabel(axTr, 'Frame');
ylabel(axTr, 'Intensity (counts)');
set(axTr, 'FontName', opts.FontName, 'FontSize', opts.FontSize, 'TickDir', 'out');

figure(figImg);
title(axImg, 'Click a point, then press Enter');
disp('Click a point');
while 1
    [gx, gy] = ginput(1);
    if numel(gx) > 0
        set(hFluor, 'YData', squeeze(V(round(gy(1)), round(gx(1)), :)));
    else
        break;
    end
end

ROIX = (1 + w)/2;
ROIY = (1 + h)/2;
exR  = PeakR + 1;

figure(figImg);
title(axImg, 'Click an ROI centre, then press Enter');
disp('Click for an ROI');
while 1
    [gx, gy] = ginput(1);
    if numel(gx) > 0
        ROIX = gx(1);
        ROIY = gy(1);
        [xdata, ydata] = circlexy(ROIX, ROIY, ROIR);
        set(hBead, 'XData', xdata, 'YData', ydata);
    else
        break;
    end
end

%% ---------------- peak detection (UNCHANGED) ----------------
[X, Y] = meshgrid(1:w, 1:h);
V = avgFrame;
ind = find((X - ROIX).^2 + (Y - ROIY).^2 < ROIR^2);
ind(V(ind) < avgLim(2)) = [];
[~, sortI] = sort(V(ind), 'descend');
ind  = ind(sortI);
ind0 = ind;

Peaks = zeros(0, 2);
while ~isempty(ind)
    cx = X(ind(1));
    cy = Y(ind(1));
    ci = (X(ind0) - cx).^2 + (Y(ind0) - cy).^2 <= exR^2;
    if V(cy, cx) >= max(V(ind0(ci)))
        Peaks(end+1, :) = [cx cy]; %#ok<AGROW>
        ind((X(ind) - cx).^2 + (Y(ind) - cy).^2 <= exR^2) = [];
    else
        ind(1) = [];
    end
end
NPeaks = size(Peaks, 1);

% centroid refinement (UNCHANGED)
[PX, PY] = meshgrid(-exR:exR, -exR:exR);
PeakI = find(PX.^2 + PY.^2 <= PeakR^2);
for i = 1:NPeaks
    xi = Peaks(i, 1);
    yi = Peaks(i, 2);
    ind = h * (xi + PX(PeakI) - 1) + yi + PY(PeakI);
    bg  = median(V(ind));
    Vbgsub = max(V(ind) - bg, 0);
    cx = sum(X(ind) .* Vbgsub) / sum(Vbgsub);
    cy = sum(Y(ind) .* Vbgsub) / sum(Vbgsub);
    Peaks(i, :) = [cx cy];
end

save(saveFileName, 'Peaks');
fprintf('%d peaks saved to: %s\n', NPeaks, saveFileName);

%% ---------------- publication overview ----------------
minX = min(Peaks(:, 1)) - exR;
maxX = max(Peaks(:, 1)) + exR;
minY = min(Peaks(:, 2)) - exR;
maxY = max(Peaks(:, 2)) + exR;

% on-screen version
figure(figImg);
title(axImg, sprintf('%d peaks', NPeaks));
hold(axImg, 'on');
for i = 1:NPeaks
    [xd, yd] = circlexy(Peaks(i,1), Peaks(i,2), exR);
    plot(axImg, xd, yd, '-', 'Color', opts.RingColor, 'LineWidth', 1);
end
hold(axImg, 'off');
axis(axImg, 'equal');
axis(axImg, [minX maxX minY maxY]);

if ~opts.SaveOverview, return; end

% clean, correctly sized copy for the figure
fig = figure('Color', 'w', 'Units', 'centimeters', 'Visible', 'off');
fig.Position      = [2 2 opts.PanelWidth_cm opts.PanelWidth_cm];
fig.PaperUnits    = 'centimeters';
fig.PaperPosition = [0 0 opts.PanelWidth_cm opts.PanelWidth_cm];
fig.PaperSize     = [opts.PanelWidth_cm opts.PanelWidth_cm];
ax = axes('Parent', fig);
imagesc(ax, avgFrame, avgLim);
colormap(ax, feval(opts.Colormap, 256));
set(ax, 'YDir', 'reverse', 'Box', 'on', 'Layer', 'top', ...
        'FontName', opts.FontName, 'FontSize', opts.FontSize, ...
        'LineWidth', 0.75, 'TickDir', 'out');
axis(ax, 'equal');
axis(ax, [minX maxX minY maxY]);     % limits final before placing labels
hold(ax, 'on');
for i = 1:NPeaks
    drawring(ax, Peaks(i,1), Peaks(i,2), exR, opts, 0.75);
    if opts.ShowIndex
        [tx, ty, ha, va] = mt_labelpos(ax, Peaks(i,1), Peaks(i,2), exR);
        mt_label(ax, tx, ty, num2str(i), opts, ...
                 'FontName', opts.FontName, 'FontSize', max(opts.FontSize-1, 6), ...
                 'HorizontalAlignment', ha, 'VerticalAlignment', va);
    end
end
hold(ax, 'off');
if opts.ShowPixelAxes
    xlabel(ax, 'x (pixel)');
    ylabel(ax, 'y (pixel)');
else
    set(ax, 'XTick', [], 'YTick', []);
end
if ~isempty(opts.PixelSize_nm)
    addscalebar(ax, opts.PixelSize_nm, opts.ScaleBar_um, opts);
end

outBase = fullfile(filePath, [nameOnly '_peaks']);
if exist('exportgraphics', 'file')
    exportgraphics(fig, [outBase '.png'], 'Resolution', opts.Resolution, ...
                   'BackgroundColor', 'white');
    if opts.SaveTIFF
        exportgraphics(fig, [outBase '.tiff'], 'Resolution', opts.Resolution, ...
                       'BackgroundColor', 'white');
    end
else
    print(fig, [outBase '.png'],  '-dpng',  sprintf('-r%d', opts.Resolution));
    if opts.SaveTIFF
        print(fig, [outBase '.tiff'], '-dtiff', sprintf('-r%d', opts.Resolution));
    end
end
close(fig);
fprintf('Overview written to: %s.png / .tiff (%d dpi)\n', outBase, opts.Resolution);
end


% ======================================================================
function [xdata, ydata] = circlexy(x, y, r)
t = 2*pi*(0:0.02:1);
xdata = x + r*cos(t);
ydata = y + r*sin(t);
end


function drawring(ax, x, y, r, opts, lw)
[xd, yd] = circlexy(x, y, r);
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
