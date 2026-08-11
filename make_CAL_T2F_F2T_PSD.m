
%% Create T2F and F2T function handles (PSD method) from saved complex parameters
% Usage:
%   run this script in MATLAB. It will load PSD_params_T2F.mat and write CAL_T2F_F2T_PSD.mat

S = load('PSD_params_T2F.mat');

F0 = S.F0; A1 = S.A1; L1 = S.L1; A2 = S.A2; L2 = S.L2;
Zmin = S.Zmin; Zmax = S.Zmax;

% Real-valued model from complex-conjugate exponential pair
T2F = @(z) real( ...
  (-0.18103654013305423 - 4.073214875460918e-07*1i) ...
+ (-0.0012814656439011306 - 0.0005971341378073474*1i).*exp(-z./(-2.081744326195234  + 0.7907001390064781*1i)) ...
+ (-0.0012814741530181456 + 0.0005971478445970879*1i).*exp(-z./(-2.0817468464687905 - 0.7906998120702615*1i)) );
% Robust inverse using fzero within [Zmin,Zmax]
F2T = @(F) arrayfun(@(f) fzero(@(zz) T2F(zz)-f, (0+24)/2), F);

meta = struct();
meta.method = 'PSD';
meta.created = datestr(now,'yyyy-mm-dd HH:MM:SS');
meta.T_range_mm = [Zmin Zmax];
meta.F_est_range_pN = [T2F(Zmin) T2F(Zmax)];

save('CAL_T2F_F2T_PSD.mat','T2F','F2T','meta','-v7');
disp('Saved CAL_T2F_F2T_PSD.mat with T2F and F2T (PSD method).');
