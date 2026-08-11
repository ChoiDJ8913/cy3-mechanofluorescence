function [tx, ty, ha, va] = mt_labelpos(ax, x, y, r)
% mt_labelpos  Where to put a peak number so it never leaves the axes.
%
%   [tx, ty, ha, va] = mt_labelpos(ax, x, y, r)
%
%   Default placement is up-and-right of the circle. If that would push the
%   label past an edge, the offset flips to the other side and the text
%   alignment flips with it, so the label always sits beside its circle and
%   always inside the plot box. Assumes the y axis is reversed (image
%   convention), where "up" on screen means a smaller y value.

xl = xlim(ax);
yl = ylim(ax);
off  = r * 1.4;
padx = 0.03 * diff(xl);
pady = 0.03 * diff(yl);

% ---- horizontal ----
tx = x + off;  ha = 'left';
if tx + padx > xl(2)          % would run off the right edge
    tx = x - off;  ha = 'right';
end
if tx - padx < xl(1)          % would run off the left edge
    tx = x + off;  ha = 'left';
end

% ---- vertical (y axis reversed: smaller y is higher on screen) ----
ty = y - off;  va = 'bottom';
if ty - pady < yl(1)          % would run off the top
    ty = y + off;  va = 'top';
end
if ty + pady > yl(2)          % would run off the bottom
    ty = y - off;  va = 'bottom';
end

% ---- final clamp, in case the circle itself sits at the very edge ----
tx = min(max(tx, xl(1) + padx), xl(2) - padx);
ty = min(max(ty, yl(1) + pady), yl(2) - pady);
end
