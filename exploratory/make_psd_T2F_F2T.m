% ==== Build T2F / F2T with SAME HANDLE NAMES (drop-in replacement) ====
% Note: Here T is the x-axis used for calibration. We bind T := Extension(μm)
% to preserve the function shape and names.

E = load('PSDext.dat');    % Extension (μm), monotonically increasing
F = load('PSDforce.dat');  % Force (pN),    monotonically increasing
E = E(:); F = F(:);

% Basic sanity
if any(diff(E)<=0) || any(diff(F)<0)
    error('Both PSDext.dat and PSDforce.dat must be strictly increasing for invertible calibration.');
end

% Use PCHIP (shape-preserving, monotone-friendly)
% Define T := E for drop-in compatibility
Tgrid = E;        % "T" axis (kept for name compatibility)
Fgrid = F;        % Force axis

% T -> F
T2F = @(T) interp1(Tgrid, Fgrid, T, 'pchip', 'extrap');

% F -> T  (inverse via swapped axes; still pchip)
F2T = @(F) interp1(Fgrid, Tgrid, F, 'pchip', 'extrap');

% Helpful metadata
meta = struct();
meta.created = datestr(now,'yyyy-mm-dd HH:MM:SS');
meta.source  = {'PSDext.dat','PSDforce.dat'};
meta.note    = 'Drop-in replacement: T2F/F2T kept same names; here T == Extension(μm).';
meta.T_range = [min(Tgrid) max(Tgrid)];  % actually Extension range
meta.F_range = [min(Fgrid) max(Fgrid)];

% Save with function handles intact
outname = sprintf('CAL_T2F_F2T_%s.mat', datestr(now,'yyyymmdd'));
save(outname, 'T2F', 'F2T', 'Tgrid', 'Fgrid', 'meta', '-v7');
fprintf('Saved drop-in calibration to %s\n', outname);

% Quick self-check (optional)
% Fchk = T2F(Tgrid);
% Tchk = F2T(Fgrid);
% fprintf('Max abs error on grids: F %.3g, T %.3g\n', max(abs(Fchk-Fgrid)), max(abs(Tchk-Tgrid)));
