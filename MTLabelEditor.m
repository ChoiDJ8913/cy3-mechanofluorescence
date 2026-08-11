function pos = MTLabelEditor(img, Peaks, opts)
% MTLabelEditor  Drag the peak numbers where you want them, then export.
%
%   pos = MTLabelEditor(img, Peaks)
%   pos = MTLabelEditor(img, Peaks, opts)
%   pos = MTLabelEditor()                 pick a *_Output folder interactively
%
%   Defaults reproduce the look of the original MTView: jet(256) over the
%   full intensity range, a single white circle of width 1, white numbers.
%   Only the export path is different, at 600 dpi instead of screen dpi.
%
%   Every number starts INSIDE the axes. A label outside would be clipped,
%   and a clipped text object cannot be clicked, so it could never be
%   dragged back in. Positions are clamped on start-up and during the drag.
%
%   img    : average frame (2-D). If omitted you are asked for a folder
%            containing Fluor.mat and the matching *_peak.mat.
%   Peaks  : N x 2 peak coordinates.
%   pos    : N x 2 final label positions. Pass back as opts.LabelPos to
%            reproduce the layout exactly.
%
%   Controls
%     drag a number     move it (cannot leave the plot box)
%     r                 reset the selected number to its default position
%     shift+R           reset all
%     e                 export TIFF + PNG at opts.Resolution
%     s                 save positions to <OutFile>_labelpos.mat
%     q                 quit and return the positions
%
%   opts fields (all optional):
%     CLim          []          [] = full range of the image, as MTView did.
%                               Pass the avgLim you used to match exactly.
%     PeakR         5           ring radius, same as MTView
%     RingColor     [1 1 1]     white, as MTView
%     RingWidth     1           single line, as MTView
%     RingEdgeColor []          [] = no dark under-ring
%     TextColor     [1 1 1]     white, as MTView
%     FontName      'Arial'
%     FontSize      8
%     Colormap      'jet'
%     ShowPixelAxes true
%     LabelPos      []          N x 2 starting positions
%     Pad_frac      0.03        keep-out margin from the axes edge
%     PanelWidth_cm 8.5
%     Resolution    600
%     OutFile       'AverageFrame_edited'
%     OutDir        pwd

if nargin < 3, opts = struct(); end
opts = setdefaults(opts, struct( ...
    'CLim',          [], ...
    'PeakR',         5, ...
    'RingColor',     [1 1 1], ...
    'RingWidth',     1, ...
    'RingEdgeColor', [], ...
    'TextColor',     [1 1 1], ...
    'FontName',      'Arial', ...
    'FontSize',      14, ...
    'Colormap',      'jet', ...
    'ShowPixelAxes', true, ...
    'LabelPos',      [], ...
    'Pad_frac',      0.03, ...
    'PanelWidth_cm', 8.5, ...
    'Resolution',    600, ...
    'OutFile',       'AverageFrame_edited', ...
    'OutDir',        pwd));

%% ---------------- load if not given ----------------
if nargin < 2 || isempty(img) || isempty(Peaks)
    d = uigetdir(pwd, 'Select a *_Output folder (contains Fluor.mat)');
    if isequal(d, 0), pos = []; return; end
    opts.OutDir = d;
    parent = fileparts(d);
    tok = regexp(d, '([^\\/]+)_Output$', 'tokens', 'once');
    if isempty(tok), error('Folder name must end in _Output'); end
    pk = fullfile(parent, [tok{1} '_peak.mat']);
    mv = fullfile(parent, [tok{1} '.mat']);
    if ~exist(pk, 'file'), error('Not found: %s', pk); end
    S = load(pk); Peaks = S.Peaks;
    if ~exist(mv, 'file'), error('Movie not found: %s', mv); end
    M = load(mv, 'movie1');
    img = mean(double(M.movie1), 3);
end

N = size(Peaks, 1);
if isempty(opts.CLim)
    opts.CLim = [min(img(:)) max(img(:))];      % as MTView, no stretching
end

%% ---------------- axes limits, fixed up front ----------------
exR   = opts.PeakR + 2;
xlim0 = [min(Peaks(:,1)) - exR, max(Peaks(:,1)) + exR];
ylim0 = [min(Peaks(:,2)) - exR, max(Peaks(:,2)) + exR];
lim   = struct('x', xlim0, 'y', ylim0, ...
               'px', opts.Pad_frac*diff(xlim0), 'py', opts.Pad_frac*diff(ylim0));

%% ---------------- default positions, always inside ----------------
defaultPos = zeros(N, 2);
for i = 1:N
    defaultPos(i, :) = autopos(Peaks(i,:), opts.PeakR, lim);
end
if isempty(opts.LabelPos)
    pos = defaultPos;
else
    pos = opts.LabelPos;
    if size(pos, 1) ~= N, error('LabelPos must be %d x 2', N); end
    for i = 1:N, pos(i,:) = clamp(pos(i,:), lim); end
end

%% ---------------- build the window ----------------
fig = figure('Color', 'w', 'NumberTitle', 'off', 'Units', 'centimeters', ...
    'Name', 'Drag the numbers   |   r reset   shift+R reset all   e export   s save   q quit');
fig.Position(3:4) = [opts.PanelWidth_cm*2.2, opts.PanelWidth_cm*2.2];
ax = axes('Parent', fig);
imagesc(ax, img, opts.CLim);
colormap(ax, feval(opts.Colormap, 256));
set(ax, 'YDir', 'reverse', 'Box', 'on', 'Layer', 'top', ...
        'LineWidth', 0.75, 'TickDir', 'out', ...
        'FontName', opts.FontName, 'FontSize', opts.FontSize);
axis(ax, 'equal');
axis(ax, [xlim0 ylim0]);
if opts.ShowPixelAxes
    xlabel(ax, 'x (pixel)'); ylabel(ax, 'y (pixel)');
else
    set(ax, 'XTick', [], 'YTick', []);
end
hold(ax, 'on');

t = 2*pi*(0:0.02:1);
for i = 1:N
    xd = Peaks(i,1) + opts.PeakR*cos(t);
    yd = Peaks(i,2) + opts.PeakR*sin(t);
    if ~isempty(opts.RingEdgeColor)
        plot(ax, xd, yd, '-', 'Color', opts.RingEdgeColor, ...
             'LineWidth', opts.RingWidth + 1.0, 'HitTest', 'off');
    end
    plot(ax, xd, yd, '-', 'Color', opts.RingColor, ...
         'LineWidth', opts.RingWidth, 'HitTest', 'off');
end

hTxt = gobjects(N, 1);
for i = 1:N
    hTxt(i) = text(ax, pos(i,1), pos(i,2), num2str(i), ...
                   'Color', opts.TextColor, 'FontName', opts.FontName, ...
                   'FontSize', opts.FontSize, 'Clipping', 'off', ...
                   'HorizontalAlignment', 'center', 'VerticalAlignment', 'middle', ...
                   'ButtonDownFcn', @startdrag);
end
hold(ax, 'off');

st = struct('fig', fig, 'ax', ax, 'hTxt', hTxt, 'sel', 0, ...
            'defaultPos', defaultPos, 'opts', opts, 'N', N, 'lim', lim);
guidata(fig, st);
set(fig, 'WindowButtonUpFcn', @stopdrag, 'KeyPressFcn', @onkey, ...
         'CloseRequestFcn', @(f,~) uiresume(f));

uiwait(fig);

if isvalid(fig)
    st = guidata(fig);
    for i = 1:st.N
        p = get(st.hTxt(i), 'Position');
        pos(i, 1:2) = p(1:2);
    end
    delete(fig);
end
end


% ======================================================================
function p = autopos(pk, r, lim)
off = r * 1.4;
x = pk(1) + off;
if x + lim.px > lim.x(2), x = pk(1) - off; end
if x - lim.px < lim.x(1), x = pk(1) + off; end
y = pk(2) - off;
if y - lim.py < lim.y(1), y = pk(2) + off; end
if y + lim.py > lim.y(2), y = pk(2) - off; end
p = clamp([x y], lim);
end


function p = clamp(p, lim)
p(1) = min(max(p(1), lim.x(1) + lim.px), lim.x(2) - lim.px);
p(2) = min(max(p(2), lim.y(1) + lim.py), lim.y(2) - lim.py);
end


function startdrag(src, ~)
st = guidata(src);
st.sel = find(st.hTxt == src, 1);
guidata(src, st);
set(st.fig, 'WindowButtonMotionFcn', @dodrag);
end

function dodrag(fig, ~)
st = guidata(fig);
if st.sel < 1, return; end
cp = get(st.ax, 'CurrentPoint');
q  = clamp([cp(1,1) cp(1,2)], st.lim);
p  = get(st.hTxt(st.sel), 'Position');
set(st.hTxt(st.sel), 'Position', [q(1) q(2) p(3)]);
end

function stopdrag(fig, ~)
set(fig, 'WindowButtonMotionFcn', '');
end

function onkey(fig, evt)
st = guidata(fig);
switch evt.Key
    case 'r'
        if any(strcmp(evt.Modifier, 'shift'))
            for i = 1:st.N
                set(st.hTxt(i), 'Position', [st.defaultPos(i,:) 0]);
            end
            fprintf('all labels reset\n');
        elseif st.sel >= 1
            set(st.hTxt(st.sel), 'Position', [st.defaultPos(st.sel,:) 0]);
            fprintf('label %d reset\n', st.sel);
        end
    case 'e'
        o = st.opts;
        base = fullfile(o.OutDir, o.OutFile);
        if exist('exportgraphics', 'file')
            exportgraphics(st.ax, [base '.tiff'], 'Resolution', o.Resolution, ...
                           'BackgroundColor', 'white');
            exportgraphics(st.ax, [base '.png'],  'Resolution', o.Resolution, ...
                           'BackgroundColor', 'white');
        else
            print(st.fig, [base '.tiff'], '-dtiff', sprintf('-r%d', o.Resolution));
            print(st.fig, [base '.png'],  '-dpng',  sprintf('-r%d', o.Resolution));
        end
        fprintf('exported %s.tiff / .png at %d dpi\n', base, o.Resolution);
    case 's'
        LabelPos = zeros(st.N, 2);
        for i = 1:st.N
            p = get(st.hTxt(i), 'Position');
            LabelPos(i, :) = p(1:2);
        end
        f = fullfile(st.opts.OutDir, [st.opts.OutFile '_labelpos.mat']);
        save(f, 'LabelPos');
        fprintf('saved %s\n', f);
        disp(LabelPos);
    case 'q'
        uiresume(fig);
end
end


function s = setdefaults(s, d)
f = fieldnames(d);
for i = 1:numel(f)
    if ~isfield(s, f{i})
        s.(f{i}) = d.(f{i});
    end
end
end
