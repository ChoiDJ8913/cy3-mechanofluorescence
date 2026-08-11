function mt_label(ax, x, y, str, opts, varargin)
% mt_label  Draw a text label on an image axis.
%
%   opts.LabelStyle : 'plain' (default) plain text, nothing behind it
%                     'halo'  thin outline around the glyphs, only for
%                             labels that must sit on a dark background
%                     'box'   opaque box behind the text
%   opts.TextColor     text colour                  default [0 0 0]
%   opts.HaloColor     outline colour for 'halo'    default [1 1 1]
%   opts.HaloWidth     outline thickness in POINTS  default 0.4
%   opts.LabelBoxColor box colour for 'box'         default [1 1 1]
%
% Default is plain black text, which is what a printed figure normally uses.
% Reach for 'halo' or 'box' only where the label genuinely sits on a dark or
% busy part of the image.
%
% For 'halo': the offset is expressed in points of the rendered figure, not
% in data units. Data units break as soon as the axis spans few pixels,
% which is exactly the case for a cropped single-molecule field of view.

opts = local_defaults(opts);

switch lower(opts.LabelStyle)

    case 'box'
        text(ax, x, y, str, ...
             'Color',           opts.TextColor, ...
             'BackgroundColor', opts.LabelBoxColor, ...
             'EdgeColor',       'none', ...
             'Margin',          0.5, ...
             'Clipping',        'on', ...
             varargin{:});

    case 'halo'
        oldU = get(ax, 'Units');
        set(ax, 'Units', 'points');
        p = get(ax, 'Position');
        set(ax, 'Units', oldU);
        dxu = diff(xlim(ax)) / max(p(3), eps);
        dyu = diff(ylim(ax)) / max(p(4), eps);
        d   = opts.HaloWidth;                       % points
        off = [-1 -1; -1 0; -1 1; 0 -1; 0 1; 1 -1; 1 0; 1 1];
        for k = 1:size(off, 1)
            text(ax, x + off(k,1)*d*dxu, y + off(k,2)*d*dyu, str, ...
                 'Color', opts.HaloColor, 'BackgroundColor', 'none', ...
                 'Clipping', 'on', varargin{:});
        end
        text(ax, x, y, str, 'Color', opts.TextColor, ...
             'BackgroundColor', 'none', 'Clipping', 'on', varargin{:});

    otherwise
        text(ax, x, y, str, 'Color', opts.TextColor, ...
             'BackgroundColor', 'none', 'Clipping', 'on', varargin{:});
end
end


function opts = local_defaults(opts)
d = struct('LabelStyle',    'plain', ...
           'TextColor',     [0 0 0], ...
           'HaloColor',     [1 1 1], ...
           'HaloWidth',     0.4, ...
           'LabelBoxColor', [1 1 1]);
f = fieldnames(d);
for i = 1:numel(f)
    if ~isfield(opts, f{i}), opts.(f{i}) = d.(f{i}); end
end
end
