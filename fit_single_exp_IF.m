function out = fit_single_exp_IF(F, I, T, makePlot)
% I(F) = s * exp(-(dx/kBT)*F)
% ln I = ln s - (dx/kBT) F
% - added a semi-log y axis plot
% - report dx in angstrom (dx_A) and keep nm as well (dx_nm)
%
% Inputs
%   F         : [N×1] force (pN)
%   I         : [N×1] intensity (>0)
%   T         : temperature [K], default 298
%   makePlot  : true/false, default true
%
% output fields (main ones)
%   dx_A          : dx [A]              <-- unit reported in the paper
%   dx_nm         : Δx [nm]
%   s             : s (I at F=0 extrapolated)
%   slope_per_pN  : -(dx/kBT) [/pN]
%   Fq, Iq        : smooth fit curve
%   kBT_pNnm      : kBT in pN·nm

if nargin < 3 || isempty(T), T = 298; end
if nargin < 4, makePlot = true; end

kBT = 0.01380649 * T;   % pN·nm (298K ≈ 4.114)
F = F(:); I = I(:);
ok = isfinite(F) & isfinite(I) & (I > 0);
F = F(ok); I = I(ok);

% ----- linearised fit: ln I = ln s - (dx/kBT) F -----
P = polyfit(F, log(I), 1);   % [slope, intercept]
m  = P(1);                   % slope = -dx/kBT
c  = P(2);                   % ln s
dx_nm = -m * kBT;            % nm
dx_A  = dx_nm * 10;          % Å
s     = exp(c);

% predicted curve
Fq = linspace(min(F), max(F), 400).';
Iq = s * exp(-(dx_nm/kBT) * Fq);

out = struct('dx_A',dx_A, 'dx_nm',dx_nm, 's',s, ...
    'kBT_pNnm',kBT, ...
    'slope_per_pN', -(dx_nm/kBT), ...
    'Fq',Fq, 'Iq',Iq);
if makePlot
    % ---------- (common) helper values ----------
    [Fs, idx] = sort(F); Is = I(idx);
    slope_ln  = -(dx_nm/kBT);              % slope on the ln scale (/pN)
    slope_lg10 = slope_ln / log(10);       % slope on the log10 scale (/pN)
    tit1 = sprintf('\\Delta x = %.3f Å,  s = %.3f', dx_A, s);
    tit2 = sprintf('Semilog-y  |  \\Delta x = %.3f Å  |  slope_{log10} = %.4f per pN', ...
        dx_A, slope_lg10);

    % ---------- (1) linear y axis ----------
    figure('Color','w'); hold on;
    plot(Fs, Is, 'o', 'MarkerSize',5, 'DisplayName','data');
    plot(Fq, Iq, '-', 'LineWidth',2, 'DisplayName','single-exp fit');
    xlabel('Force F (pN)', 'Interpreter','tex');
    ylabel('Relative intensity', 'Interpreter','tex');
    title(tit1, 'Interpreter','tex');  % force tex interpretation
    grid on; box off; legend('Location','best');

    % ---------- (2) semi-log y axis ----------
    figure('Color','w'); hold on;
    plot(Fs, Is, 'o', 'MarkerSize',5, 'DisplayName','data');
    plot(Fq, Iq, '-', 'LineWidth',2, 'DisplayName','single-exp fit');
    set(gca, 'YScale','log', 'YMinorTick','on');  % log scale
    % pleasant range (positive values only), with a little headroom
    ylim([max(min(Is), 0.5*min(Is)) 1.2*max(Is)]);
    xlabel('Force F (pN)', 'Interpreter','tex');
    ylabel('Relative intensity (log scale)', 'Interpreter','tex');
    title(tit2, 'Interpreter','tex');    % force tex interpretation + Unicode angstrom
    grid on; box off; legend('Location','best');

    % ---------- (3) linearisation check: ln(I) vs F ----------
    figure('Color','w'); hold on;
    plot(Fs, log(Is), 'o', 'DisplayName','ln(I) data');
    plot(Fq, log(Iq), '-', 'LineWidth',2, 'DisplayName','linear fit');
    xlabel('Force F (pN)', 'Interpreter','tex');
    ylabel('ln(Intensity)', 'Interpreter','tex');
    title(sprintf('Linearized: slope = %.4f per pN', slope_ln), 'Interpreter','tex');
    grid on; box off; legend('Location','best');
end

end
