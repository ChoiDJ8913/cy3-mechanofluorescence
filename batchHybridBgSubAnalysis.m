function batchHybridBgSubAnalysis(folderPath, ups, bgWin, lkWinRad)
% BATCHHYBRIDBGSUBANALYSIS  (리뷰 반영 정리본)
%   폴더 내 모든 .mat (movie1 포함) 파일에 대해
%     1) 배경면 보정 (국소 최소 + scatteredInterpolant)
%     2) 정수 픽셀 수준 Phase Correlation  (초기 N프레임 평균 = 고정 기준)
%     3) 서브픽셀 Lucas–Kanade 잔차 보정
%   을 순차 처리하고, 누적 이동량을 저장/리포트합니다.
%
%   사용법:
%     batchHybridBgSubAnalysis( ...
%       'D:\path\to\data', ...  % movie1이 있는 폴더
%       200,   ...  % ups : (현재 미사용/예약, 호환 위해 인자 유지)
%       20,    ...  % bgWin : background 국소 윈도 반경
%       3);         % lkWinRad : LK 유효영역 테두리 반경
%
%   ── 이전 버전 대비 변경점 ───────────────────────────────────────────
%   [치명] 정수 단계가 '고정 기준' 대비 절대 드리프트를 측정하므로
%          cumsum 을 다시 걸면 안 됨 → 이중 누적 버그 제거.
%   [과학] 배경 샘플을 원본 휘도 대신 '블록 국소 최소'로 → PSF 흡수 방지.
%   [성능] scatteredInterpolant 1회 생성 후 .Values 만 갱신,
%          기준 FFT 1회 계산, LK 이중루프 → 전역 1-스텝 벡터화.
%   [견고] LK 조건수/NaN 가드, 기준=초기 N프레임 평균, 경계 채움=중앙값.
%   [메모] bgSub 단정밀도(single) 저장 + 사용 끝난 배열 즉시 해제.
%   ─────────────────────────────────────────────────────────────────

  %% ---------- 입력 검증 / 기본값 ----------
  if nargin < 1 || isempty(folderPath)
    error('batchHybridBgSubAnalysis:noPath', 'folderPath를 지정하세요.');
  end
  if ~isfolder(folderPath)
    error('batchHybridBgSubAnalysis:badPath', ...
          '폴더가 존재하지 않습니다: %s', folderPath);
  end
  if nargin < 2 || isempty(ups),      ups      = 200; end %#ok<NASGU>  (예약 인자)
  if nargin < 3 || isempty(bgWin),    bgWin    = 20;  end
  if nargin < 4 || isempty(lkWinRad), lkWinRad = 3;   end
  validateattributes(bgWin,    {'numeric'}, {'scalar','positive','integer'}, mfilename, 'bgWin');
  validateattributes(lkWinRad, {'numeric'}, {'scalar','positive','integer'}, mfilename, 'lkWinRad');

  nRefAvg = 10;   % 고정 기준으로 평균낼 초기 프레임 수

  files = dir(fullfile(folderPath, '*.mat'));
  fprintf('-> "%s"에서 MAT 파일 %d개 발견\n', folderPath, numel(files));

  for i = 1:numel(files)
    fname = files(i).name;
    fullf = fullfile(folderPath, fname);
    S = load(fullf);
    if ~isfield(S, 'movie1')
      warning('SKIP: %s 에 ''movie1''이 없습니다.', fname);
      continue;
    end

    fprintf('처리 중 %s (%d/%d)\n', fname, i, numel(files));
    mov = double(S.movie1);   clear S          % H×W×nF
    [H, W, nF] = size(mov);
    if nF < 2
      warning('SKIP: %s 는 프레임이 %d개뿐이라 정합 불가.', fname, nF);
      clear mov;  continue;
    end

    %% ---------- 1) 배경 추정 및 제거 ----------
    %  보간기는 1회만 생성하고( 들로네 삼각분할 재계산 회피 ) 값만 교체.
    %  샘플은 원본 휘도가 아니라 블록 국소 최소 → 밝은 PSF가 배경에 섞이지 않음.
    bgSub = zeros(H, W, nF, 'single');
    [Xg, Yg] = meshgrid(1:W, 1:H);
    xs = 1:bgWin:W;   ys = 1:bgWin:H;
    [Xsamp, Ysamp] = meshgrid(xs, ys);
    sampIdx = sub2ind([H, W], Ysamp(:), Xsamp(:));
    seBlk   = true(bgWin);                       % 국소 최소 윈도

    F = scatteredInterpolant(Xsamp(:), Ysamp(:), ...
          zeros(numel(Xsamp), 1), 'linear', 'nearest');
    for k = 1:nF
      I    = mov(:,:,k);
      Imin = ordfilt2(I, 1, seBlk, 'symmetric'); % 블록 국소 최소
      F.Values     = Imin(sampIdx);
      bgSub(:,:,k) = single(I - F(Xg, Yg));
    end
    clear mov                                    % 원본 스택 해제(메모리)

    %% ---------- 2) 정수 픽셀 Phase Correlation ----------
    %  기준 = 초기 N프레임 평균(고정). 따라서 결과는 프레임1 기준 '절대' 드리프트.
    win  = single(hann(H) * hann(W)');           % 2D Hann
    nAvg = min(nRefAvg, nF);
    ref0 = mean(bgSub(:,:,1:nAvg), 3) .* win;
    Fref = fft2(ref0);                           % 기준 FFT 1회

    absShiftInt = zeros(nF, 2);                  % [dX, dY] : 절대 정수 드리프트
    for k = 2:nF
      Ft  = fft2(bgSub(:,:,k) .* win);
      CPS = Fref .* conj(Ft);
      CPS = CPS ./ (abs(CPS) + eps('single'));   % 위상상관 정규화
      CC  = fftshift(ifft2(CPS, 'symmetric'));
      [~, idx] = max(CC(:));
      [u, v]   = ind2sub([H, W], idx);
      row0 = u - floor(H/2) - 1;                 % Y 방향 시프트
      col0 = v - floor(W/2) - 1;                 % X 방향 시프트
      absShiftInt(k, :) = -[col0, row0];         % [dX, dY]
    end
    % ※ 고정 기준이므로 이미 절대값 → cumsum 금지 (이전 버전의 버그).

    %% ---------- 3) 서브픽셀 Lucas–Kanade 잔차 보정 ----------
    %  연속 프레임을 각자의 절대 정수 시프트로 정렬한 뒤 잔차를 측정.
    %  연속 잔차의 cumsum 은 망원합(telescoping)으로 절대 잔차에 수렴.
    deltaSub = zeros(nF, 2);
    for k = 2:nF
      fillPrev = median(bgSub(:,:,k-1), 'all');  % 경계 0-채움 대신 중앙값
      fillCur  = median(bgSub(:,:,k),   'all');
      Iw = imtranslate(bgSub(:,:,k-1), -absShiftInt(k-1,:), ...
                       'OutputView','same', 'FillValues', fillPrev);
      Jw = imtranslate(bgSub(:,:,k),   -absShiftInt(k,:), ...
                       'OutputView','same', 'FillValues', fillCur);
      deltaSub(k, :) = lucasKanade2D(double(Iw), double(Jw), lkWinRad);
    end
    cumSub = cumsum(deltaSub, 1);                % 연속 잔차의 누적(적절)

    %% ---------- 최종 누적 이동 = 절대 정수 + 누적 서브픽셀 잔차 ----------
    cumX = absShiftInt(:,1) + cumSub(:,1);
    cumY = absShiftInt(:,2) + cumSub(:,2);

    %% ---------- 결과 저장 ----------
    outName = strrep(fname, '.mat', '_hybridBG_drift.mat');
    params  = struct('ups', ups, 'bgWin', bgWin, 'lkWinRad', lkWinRad, ...
                     'nRefAvg', nAvg, 'reference', 'mean(first N frames)');
    save(fullfile(folderPath, outName), ...
         'cumX', 'cumY', 'absShiftInt', 'deltaSub', 'cumSub', 'params');

    %% ---------- 시각화 ----------
    outDir = fullfile(folderPath, 'hybrid_drift_plots');
    if ~exist(outDir, 'dir'), mkdir(outDir); end
    baseName = strrep(fname, '.mat', '');

    % (1) 최종 누적 이동량
    figure('Visible','off');
    subplot(2,1,1); plot(cumX, 'r.-'); ylabel('\DeltaX (px)'); grid on;
    title(['Drift in X - ' baseName], 'Interpreter','none');
    subplot(2,1,2); plot(cumY, 'b.-'); ylabel('\DeltaY (px)'); xlabel('Frame'); grid on;
    saveas(gcf, fullfile(outDir, [baseName '_cumXY.png'])); close;

    % (2) 정수-only vs 하이브리드(정수+서브픽셀) 비교
    figure('Visible','off');
    subplot(2,1,1);
    plot(absShiftInt(:,1), 'r.-'); hold on; plot(cumX, 'k.-');
    ylabel('\DeltaX'); legend('Integer only','Hybrid'); grid on;
    title(['\DeltaX - ' baseName], 'Interpreter','none');
    subplot(2,1,2);
    plot(absShiftInt(:,2), 'r.-'); hold on; plot(cumY, 'k.-');
    ylabel('\DeltaY'); xlabel('Frame'); legend('Integer only','Hybrid'); grid on;
    title(['\DeltaY - ' baseName], 'Interpreter','none');
    saveas(gcf, fullfile(outDir, [baseName '_deltaXY.png'])); close;

    %% ---------- 리포트 ----------
    fprintf('  -> 저장 %s : 최종 \x394X=%.3f px, \x394Y=%.3f px\n\n', ...
            outName, cumX(end), cumY(end));

    clear bgSub
  end
end


%% ====================== Lucas–Kanade 헬퍼 ======================
function d = lucasKanade2D(I, J, wRad)
% 전역 2D Lucas–Kanade (서브픽셀, 1-스텝).
% 유효 내부 영역(테두리 wRad 제외)에서 단일 흐름 벡터를 최소제곱으로 추정.
  m = false(size(I));
  m(1+wRad:end-wRad, 1+wRad:end-wRad) = true;

  [Ix, Iy] = gradient(I);          % Ix: dim2(X), Iy: dim1(Y)
  It = J - I;

  ix = Ix(m);  iy = Iy(m);  it = It(m);
  A = [ix.'*ix,  ix.'*iy;
       ix.'*iy,  iy.'*iy];
  b = -[ix.'*it; iy.'*it];

  % 평탄영역(개구 문제)·NaN 보호: 발산 대신 보정 생략
  if ~all(isfinite(A(:))) || ~all(isfinite(b(:))) || rcond(A) < 1e-8
    d = [0, 0];
    return;
  end
  d = (A \ b).';                   % [dX, dY]
end


%% ====================== (선택) 부호 컨벤션 자가검증 ======================
% imtranslate / gradient 의 부호가 실제 드리프트 방향과 맞는지 한 번 확인하려면
% 아래를 별도 스크립트로 복사해 실행하세요. 알려진 시프트가 복원되면 OK.
%
%   H = 128; W = 128; [xx,yy] = meshgrid(1:W,1:H);
%   g  = @(cx,cy) exp(-((xx-cx).^2+(yy-cy).^2)/(2*3^2));   % 가우시안 점광원
%   I0 = g(64,64);                                          % 기준 프레임
%   knownShift = [4, -3];                                   % [dX, dY] 정답
%   I1 = imtranslate(I0, knownShift, 'OutputView','same');
%   % 정수 PC:
%   win = hann(H)*hann(W)';
%   CPS = fft2(I0.*win).*conj(fft2(I1.*win)); CPS = CPS./(abs(CPS)+eps);
%   CC  = fftshift(ifft2(CPS,'symmetric')); [~,idx]=max(CC(:));
%   [u,v]=ind2sub([H,W],idx);
%   estInt = -[v-floor(W/2)-1, u-floor(H/2)-1];
%   fprintf('정답=[%g %g], PC추정=[%g %g]\n', knownShift, estInt);
%   % estInt 가 knownShift 와 같은 부호로 나오면 컨벤션 일치.