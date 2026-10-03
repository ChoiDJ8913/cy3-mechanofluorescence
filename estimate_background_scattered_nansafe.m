function [bgLow_full, bgHigh_full] = estimate_background_scattered_nansafe(meanLow, meanHigh, roiPos_all)
% ESTIMATE_BACKGROUND_SCATTERED_NANSAFE
%   ROI 외부 영역만 기반으로 전체 이미지에 대해 BG 추정
%   보간은 scatteredInterpolant(linear) 기반
%
% 입력:
%   - meanLow, meanHigh : 각 평균 이미지
%   - roiPos_all         : ROI 위치 {x, y, w, h}
% 출력:
%   - bgLow_full, bgHigh_full : 보간된 BG 이미지

    mask = true(size(meanLow));
    for i = 1:numel(roiPos_all)
        roi = roiPos_all{i};
        x = roi(1); y = roi(2); w = roi(3); h = roi(4);
        mask(y:y+h-1, x:x+w-1) = false;
    end

    [X,Y] = meshgrid(1:size(meanLow,2), 1:size(meanLow,1));

    % Low
    F_low = scatteredInterpolant(X(mask), Y(mask), meanLow(mask), 'linear', 'nearest');
    bgLow_full = F_low(X, Y);

    % High
    F_high = scatteredInterpolant(X(mask), Y(mask), meanHigh(mask), 'linear', 'nearest');
    bgHigh_full = F_high(X, Y);
end
