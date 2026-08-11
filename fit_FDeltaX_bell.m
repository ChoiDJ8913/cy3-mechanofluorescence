function fit = fit_FDeltaX_bell(F, I, varargin)
% Fit normalized intensity vs force with Bell (F*Δx) model:
% I_norm(F) = 1 / (1 + alpha * (exp(F*dx/kBT) - 1))
% Inputs:
%   F : [N x 1] force in pN
%   I : [N x 1] intensity (raw or already normalized to F≈0)
% Name-Value options:
%   'T'         : temperature [K], default 298
%   'Normalize' : true/false (auto-normalize to mean of lowest-20% F), default true
%   'Weights'   : [N x 1] weights, default ones
%   'MakePlot'  : true/false, default true
%
% Output struct 'fit' contains fields: dx_nm, alpha, kBT_pNnm, slope0, I0_used,
%   Fq, Iq (fit curve), yhat (at data), rss, r2, and handles if plotted.

    % --------- parsing ---------
    p = inputParser;
    addParameter(p,'T',298);
    addParameter(p,'Normalize',true);
    addParameter(p,'Weights',[]);
    addParameter(p,'MakePlot',true);
    parse(p,varargin{:});
    T      = p.Results.T;
    doNorm = p.Results.Normalize;
    w      = p.Results.Weights;
    mkplot = p.Results.MakePlot;

    F = F(:); I = I(:);
    ok = isfinite(F) & isfinite(I);
    F = F(ok); I = I(ok);
    N = numel(F);
    if isempty(w), w = ones(N,1); else, w = w(:); w = w(ok); end

    % --------- kBT in pN*nm ---------
    kBT = 0.01380649 * T; % pN·nm

    % --------- auto-normalize if requested ---------
    I0_used = 1.0;
    if doNorm
        Fs = sort(F);
        cut = Fs(max(1, floor(0.2*numel(F)))); % 20% quantile
        mask0 = F <= cut;
        if ~any(mask0), mask0 = F == min(F); end
        I0_used = mean(I(mask0));
        I = I / I0_used;
    end

    % --------- initial guesses ---------
    % alpha in (0,1), dx>0. Use small-F slope to estimate dx.
    alpha0 = min(max( 1 - min(max(I,0),1), 0.05), 0.95); % between 0.05 and 0.95
    % linear fit on lowest 30% F to get slope
    Fs = sort(F); cutL = Fs(max(1, floor(0.3*numel(F))));
    Lmask = F <= cutL; 
    if nnz(Lmask) >= 3
        P = polyfit(F(Lmask), I(Lmask), 1);
        slope_est = P(1); % dI/dF (should be negative)
    else
        slope_est = (I(end)-I(1)) / (F(end)-F(1));
    end
    slope_est = min(slope_est, -1e-4); % force negative if accidental
    dx0 = min(max( -(kBT/alpha0)*slope_est , 0.01), 2.0); % nm, clamp 0.01~2

    % Re-parameterize to unconstrained variables:
    % alpha = sigmoid(a), dx = exp(b)
    a0 = log(alpha0/(1-alpha0));
    b0 = log(dx0);

    % --------- objective ---------
    function y = model(params, FF)
        a = params(1); b = params(2);
        alpha = 1/(1+exp(-a));
        dx    = exp(b); % nm
        y = 1 ./ (1 + alpha .* (exp( (FF.*dx)/kBT ) - 1));
    end
    function sse = obj(params)
        y = model(params, F);
        r = (I - y);
        sse = sum( w .* (r.^2) );
        if ~isfinite(sse), sse = 1e12; end
    end

    % --------- optimize (fminsearch; no toolboxes needed) ---------
    opts = optimset('MaxFunEvals', 5e4, 'MaxIter', 5e4, 'TolX',1e-10,'TolFun',1e-10,'Display','off');
    [popt, fval] = fminsearch(@obj, [a0 b0], opts);

    % --------- unpack & diagnostics ---------
    a = popt(1); b = popt(2);
    alpha = 1/(1+exp(-a));
    dx_nm = exp(b);
    yhat  = model(popt, F);
    rss   = sum(w.*(I - yhat).^2);
    tss   = sum(w.*(I - sum(w.*I)/sum(w)).^2);
    r2    = 1 - rss/max(tss, eps);
    slope0 = - alpha * dx_nm / kBT; % dI/dF at F=0  (per pN)

    % smooth curve
    Fq = linspace(min(F), max(F), 400).';
    Iq = model(popt, Fq);

    fit = struct('dx_nm',dx_nm,'alpha',alpha,'kBT_pNnm',kBT, ...
                 'slope0_per_pN',slope0, 'I0_used',I0_used, ...
                 'Fq',Fq,'Iq',Iq,'yhat',yhat,'rss',rss,'r2',r2);

    % --------- plot ---------
    if mkplot
        figure('Color','w'); hold on;
        plot(F, I, 'o', 'MarkerSize',5, 'DisplayName','data');
        plot(Fq, Iq, '-', 'LineWidth',2, 'DisplayName','Bell fit');
        xlabel('Force F (pN)'); ylabel('I_{norm}(F)');
        yl = ylim; ylim([max(0, yl(1)), min(1.1, max(1, yl(2)))]);
        grid on; box off;
        title(sprintf('\\Delta x = %.3f nm, \\alpha = %.3f, R^2=%.3f', dx_nm, alpha, r2));
        legend('Location','best');
    end
end
