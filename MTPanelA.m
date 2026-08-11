function [imgs, info] = MTPanelA(src, opts)
% MTPanelA  Build the full-field-of-view panel of fig. S1A.
%
%   [imgs, info] = MTPanelA()                 pick a .mat file, choose frames
%   [imgs, info] = MTPanelA(file)             path to a *.record.mat
%   [imgs, info] = MTPanelA(movie1)           a movie array already in memory
%   [imgs, info] = MTPanelA(src, opts)
%
%   Requires mt_label.m on the path (same folder is fine).
%
%   Averages one or more chosen frame ranges, shows each as a full field of
%   view, optionally marks the zoom region with a red box and the tethered
%   dye with a red arrow, and exports at 600 dpi.
%
%   Only the requested frames are read from disk when the file is MAT v7.3,
%   so a 40 MB movie does not have to be loaded whole.
%
%   opts fields (all optional):
%     FrameSets     {}          e.g. {1:42, 77:100}. Empty opens a picker.
%     PanelLabels   {}          e.g. {'F_0 = 5.1 pN','F = 27.3 pN'}
%     CLim          []          [] = 1st/99.9th percentile of the first panel
%     Box           []          [x y w h] in pixels, red rectangle. NaN opens
%                               an interactive drag.
%     Arrow         []          [xTip yTip] target of the red arrow. NaN opens
%                               an interactive click.
%     ArrowLen_px   18
%     ArrowAngle    -135        direction the arrow comes from, degrees
%     Crop          []          [x y w h] to show a sub-region instead of all
%     Layout        'row'       'row' | 'column' | 'separate'
%     Gap_cm        0.15
%     PanelWidth_cm 17.5        total width of the exported figure
%     Resolution    600
%     FontName      'Arial'
%     FontSize      8
%     Colormap      'jet'
%     ShowPixelAxes false       full-FOV panels normally use a scale bar
%     TextColor     [0 0 0]     panel labels and scale bar text
%     LabelStyle    'plain'     'plain' | 'halo' | 'box'
%     HaloColor     [1 1 1]
%     HaloWidth     0.4
%     BarColor      [1 1 1]     scale bar line
%     BarEdgeColor  [0 0 0]     dark edge under it, [] to disable
%     PixelSize_nm  []          e.g. 91.7; enables the scale bar
%     ScaleBar_um   5
%     MarkColor     [1 0 0]     box and arrow colour
%     OutFile       'FigS1A'    written next to the source file
%     SaveTIFF      true
%
%   Example
%     opts.FrameSets    = {1:42, 77:100};
%     opts.PanelLabels  = {'F_0 = 5.1 pN', 'F = 27.3 pN'};
%     opts.Box          = [218 272 95 75];
%     opts.Arrow        = [265 305];
%     opts.PixelSize_nm = 91.7;
%     MTPanelA('D:\MT\...\1.record.mat', opts);

if nargin < 1, src = ''; end
if nargin < 2, opts = struct(); end
opts = setdefaults(opts, struct( ...
    'FrameSets',     {{}}, ...
    'PanelLabels',   {{}}, ...
    'CLim',          [], ...
    'Box',           [], ...
    'Arrow',         [], ...
    'ArrowLen_px',   18, ...
    'ArrowAngle',    -135, ...
    'Crop',          [], ...
    'Layout',        'row', ...
    'Gap_cm',        0.15, ...
    'PanelWidth_cm', 17.5, ...
    'Resolution',    600, ...
    'FontName',      'Arial', ...
    'FontSize',      8, ...
    'Colormap',      'jet', ...
    'ShowPixelAxes', false, ...
    'TextColor',     [0 0 0], ...
    'LabelStyle',    'plain', ...
    'HaloColor',     [1 1 1], ...
    'HaloWidth',     0.4, ...
    'BarColor',      [1 1 1], ...
    'BarEdgeColor',  [0 0 0], ...
    'PixelSize_nm',  [], ...
    'ScaleBar_um',   5, ...
    'MarkColor',     [1 0 0], ...
    'OutFile',       'FigS1A', ...
    'SaveTIFF',      true));

%% ---------------- resolve the source ----------------
outDir = pwd;
if isnumeric(src) && ~isempty(src)
    mv = double(src);
    nFrames = size(mv, 3);
    reader = @(f) mean(double(mv(:,:,f)), 3);
else
    if isempty(src)
        [fn, fp] = uigetfile('*.mat', 'Select a movie .mat file');
        if isequal(fn, 0), imgs = {}; info = struct(); return; end
        src = fullfile(fp, fn);
    end
    outDir = fileparts(src);
    [reader, nFrames] = makereader(src);
end
fprintf('Movie has %d frames\n', nFrames);

%% ---------------- choose frames ----------------
if isempty(opts.FrameSets)
    opts.FrameSets = pickframes(reader, nFrames, opts);
end
nP = numel(opts.FrameSets);

imgs = cell(1, nP);
for p = 1:nP
    f = opts.FrameSets{p};
    f = f(f >= 1 & f <= nFrames);
    if isempty(f), error('Frame set %d is empty or out of range.', p); end
    opts.FrameSets{p} = f;
    imgs{p} = reader(f);
end

if ~isempty(opts.Crop)
    c = round(opts.Crop);
    for p = 1:nP
        imgs{p} = imgs{p}(c(2):c(2)+c(4)-1, c(1):c(1)+c(3)-1);
    end
end

if isempty(opts.CLim)
    v = sort(imgs{1}(:));
    opts.CLim = [v(max(1, round(0.010*end))) v(round(0.999*end))];
end

%% ---------------- interactive box / arrow ----------------
if isscalar(opts.Box) && isnan(opts.Box)
    opts.Box = pickbox(imgs{1}, opts);
end
if isscalar(opts.Arrow) && isnan(opts.Arrow)
    opts.Arrow = pickpoint(imgs{1}, opts);
end

%% ---------------- draw ----------------
[H, W] = size(imgs{1});
aspect = H / W;

switch lower(opts.Layout)
    case 'separate'
        for p = 1:nP
            fig = newfig(opts.PanelWidth_cm, opts.PanelWidth_cm * aspect);
            ax  = axes('Parent', fig, 'Position', [0 0 1 1]);
            drawpanel(ax, imgs{p}, opts, labelof(opts, p));
            exportfig(fig, fullfile(outDir, sprintf('%s_%d', opts.OutFile, p)), opts);
            close(fig);
        end
    otherwise
        isRow = strcmpi(opts.Layout, 'row');
        if isRow
            wEach = (opts.PanelWidth_cm - opts.Gap_cm*(nP-1)) / nP;
            figH  = wEach * aspect;
        else
            wEach = opts.PanelWidth_cm;
            figH  = (wEach * aspect) * nP + opts.Gap_cm*(nP-1);
        end
        fig = newfig(opts.PanelWidth_cm, figH);
        for p = 1:nP
            if isRow
                x0 = ((p-1)*(wEach + opts.Gap_cm)) / opts.PanelWidth_cm;
                pos = [x0 0 wEach/opts.PanelWidth_cm 1];
            else
                hEach = (wEach * aspect) / figH;
                y0 = 1 - p*hEach - (p-1)*opts.Gap_cm/figH;
                pos = [0 y0 1 hEach];
            end
            ax = axes('Parent', fig, 'Position', pos);
            drawpanel(ax, imgs{p}, opts, labelof(opts, p));
        end
        exportfig(fig, fullfile(outDir, opts.OutFile), opts);
        close(fig);
end

info = struct('FrameSets', {opts.FrameSets}, 'CLim', opts.CLim, ...
              'Box', opts.Box, 'Arrow', opts.Arrow, 'OutDir', outDir);
fprintf('Panel written to %s (%d dpi)\n', fullfile(outDir, opts.OutFile), opts.Resolution);
end


% ======================================================================
function drawpanel(ax, img, opts, lbl)
imagesc(ax, img, opts.CLim);
colormap(ax, feval(opts.Colormap, 256));
axis(ax, 'image');
set(ax, 'YDir', 'reverse', 'Box', 'on', 'Layer', 'top', ...
        'LineWidth', 0.75, 'TickDir', 'out', ...
        'FontName', opts.FontName, 'FontSize', opts.FontSize);
if opts.ShowPixelAxes
    xlabel(ax, 'x (pixel)'); ylabel(ax, 'y (pixel)');
else
    set(ax, 'XTick', [], 'YTick', []);
end
hold(ax, 'on');

if ~isempty(opts.Box) && numel(opts.Box) == 4
    rectangle(ax, 'Position', opts.Box, 'EdgeColor', opts.MarkColor, 'LineWidth', 1.0);
end

if ~isempty(opts.Arrow) && numel(opts.Arrow) == 2
    drawarrow(ax, opts.Arrow, opts);
end

if ~isempty(opts.PixelSize_nm)
    addscalebar(ax, opts.PixelSize_nm, opts.ScaleBar_um, opts);
end

if ~isempty(lbl)
    xl = xlim(ax); yl = ylim(ax);
    mt_label(ax, xl(1) + 0.035*diff(xl), yl(1) + 0.045*diff(yl), lbl, opts, ...
             'HorizontalAlignment', 'left', 'VerticalAlignment', 'top', ...
             'FontName', opts.FontName, 'FontSize', opts.FontSize);
end
hold(ax, 'off');
end


function drawarrow(ax, tip, opts)
a  = deg2rad(opts.ArrowAngle);
L  = opts.ArrowLen_px;
tail = tip + L*[cos(a) sin(a)];
plot(ax, [tail(1) tip(1)], [tail(2) tip(2)], '-', ...
     'Color', opts.MarkColor, 'LineWidth', 1.2);
hl = 0.35*L; hw = 0.20*L;
dir  = (tip - tail) / max(norm(tip - tail), eps);
perp = [-dir(2) dir(1)];
p1 = tip;
p2 = tip - hl*dir + hw*perp;
p3 = tip - hl*dir - hw*perp;
patch(ax, 'XData', [p1(1) p2(1) p3(1)], 'YData', [p1(2) p2(2) p3(2)], ...
      'FaceColor', opts.MarkColor, 'EdgeColor', 'none');
end


function addscalebar(ax, pixelSize_nm, bar_um, opts)
xl = xlim(ax); yl = ylim(ax);
barPx = (bar_um * 1000) / pixelSize_nm;
pad   = 0.05 * diff(xl);
x0 = xl(2) - pad - barPx;
y0 = yl(2) - 0.08 * diff(yl);
if ~isempty(opts.BarEdgeColor)
    plot(ax, [x0 x0+barPx], [y0 y0], '-', 'Color', opts.BarEdgeColor, 'LineWidth', 3.0);
end
plot(ax, [x0 x0+barPx], [y0 y0], '-', 'Color', opts.BarColor, 'LineWidth', 2.0);
mt_label(ax, x0 + barPx/2, y0 - 0.02*diff(yl), sprintf('%g \\mum', bar_um), opts, ...
         'HorizontalAlignment', 'center', 'VerticalAlignment', 'top', ...
         'FontName', opts.FontName, 'FontSize', opts.FontSize);
end


% ---------------- frame reading ----------------
function [reader, nFrames] = makereader(file)
% Read only the requested frames when the file is MAT v7.3.
try
    m  = matfile(file);
    sz = size(m, 'movie1');
    nFrames = sz(3);
    reader  = @(f) mean(double(m.movie1(:, :, f)), 3);
    reader(1);                       % probe: fails on non-v7.3
catch
    S = load(file, 'movie1');
    if ~isfield(S, 'movie1'), error('movie1 not found in %s', file); end
    mv = double(S.movie1);
    nFrames = size(mv, 3);
    reader  = @(f) mean(mv(:, :, f), 3);
end
end


function sets = pickframes(reader, nFrames, opts)
% Show the frame-mean trace and let the user drag ranges on it.
step = max(1, round(nFrames/400));
idx  = 1:step:nFrames;
tr   = zeros(size(idx));
for k = 1:numel(idx), tr(k) = mean(reader(idx(k)), 'all'); end

f = figure('Color', 'w', 'Name', 'Select frame ranges');
ax = axes('Parent', f);
plot(ax, idx, tr, 'k-', 'LineWidth', 1);
xlabel(ax, 'Frame'); ylabel(ax, 'Mean intensity (counts)');
set(ax, 'FontName', opts.FontName, 'FontSize', 10, 'TickDir', 'out');
title(ax, 'Click START and END of range 1, then range 2. Enter when done.');

sets = {};
while true
    [gx, ~] = ginput(2);
    if numel(gx) < 2, break; end
    a = max(1, round(min(gx)));
    b = min(nFrames, round(max(gx)));
    sets{end+1} = a:b; %#ok<AGROW>
    hold(ax, 'on');
    yl = ylim(ax);
    patch(ax, [a b b a], [yl(1) yl(1) yl(2) yl(2)], [0.2 0.4 1], ...
          'FaceAlpha', 0.15, 'EdgeColor', 'none');
    hold(ax, 'off');
    fprintf('  range %d: frames %d to %d\n', numel(sets), a, b);
end
close(f);
if isempty(sets), error('No frame range selected.'); end
end


function box = pickbox(img, opts)
f = figure('Color', 'w', 'Name', 'Drag the zoom region');
ax = axes('Parent', f);
imagesc(ax, img, opts.CLim); axis(ax, 'image');
colormap(ax, feval(opts.Colormap, 256));
title(ax, 'Drag a rectangle, then double-click inside it');
r = drawrectangle(ax);
wait(r);
box = round(r.Position);
close(f);
fprintf('  box = [%d %d %d %d]\n', box);
end


function pt = pickpoint(img, opts)
f = figure('Color', 'w', 'Name', 'Click the arrow target');
ax = axes('Parent', f);
imagesc(ax, img, opts.CLim); axis(ax, 'image');
colormap(ax, feval(opts.Colormap, 256));
title(ax, 'Click the spot the arrow should point at');
[x, y] = ginput(1);
pt = round([x y]);
close(f);
fprintf('  arrow = [%d %d]\n', pt);
end


% ---------------- figure plumbing ----------------
function fig = newfig(w_cm, h_cm)
fig = figure('Color', 'w', 'Units', 'centimeters', 'Visible', 'off');
fig.Position      = [2 2 w_cm h_cm];
fig.PaperUnits    = 'centimeters';
fig.PaperPosition = [0 0 w_cm h_cm];
fig.PaperSize     = [w_cm h_cm];
end


function exportfig(fig, outBase, opts)
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
end


function s = labelof(opts, p)
if numel(opts.PanelLabels) >= p, s = opts.PanelLabels{p}; else, s = ''; end
end


function s = setdefaults(s, d)
f = fieldnames(d);
for i = 1:numel(f)
    if ~isfield(s, f{i})
        s.(f{i}) = d.(f{i});
    end
end
end
