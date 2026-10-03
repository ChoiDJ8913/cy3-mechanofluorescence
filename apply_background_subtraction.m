function [low_bgsub, high_bgsub] = apply_background_subtraction(low_raw, high_raw, method, roiMask)
    useMask = (nargin >= 4) && ~isempty(roiMask);

    % 기본 크기
    [rows, cols] = size(low_raw);
    [X, Y] = meshgrid(1:cols, 1:rows);

    switch method
        % case 'median20'
        %     if useMask
        %         valsLow = low_raw(roiMask);
        %         valsHigh = high_raw(roiMask);
        %     else
        %         valsLow = low_raw(:);
        %         valsHigh = high_raw(:);
        %     end
        %     lowCut = prctile(valsLow, 20);
        %     highCut = prctile(valsHigh, 20);
        %     bgLow = median(valsLow(valsLow < lowCut));
        %     bgHigh = median(valsHigh(valsHigh < highCut));
        %     low_bgsub = low_raw - bgLow;
        %     high_bgsub = high_raw - bgHigh;

        case 'min'
            if useMask
                bgLow = min(low_raw(roiMask));
                bgHigh = min(high_raw(roiMask));
            else
                bgLow = min(low_raw(:));
                bgHigh = min(high_raw(:));
            end
            low_bgsub = low_raw - bgLow;
            high_bgsub = high_raw - bgHigh;

        % case 'interp'
        %     if useMask
        %         % ROI 외부만 사용
        %         outside = ~roiMask;
        %         maskLow = outside & (low_raw < prctile(low_raw(outside), 20));
        %         maskHigh = outside & (high_raw < prctile(high_raw(outside), 20));
        %     else
        %         % 전체 기준
        %         maskLow = low_raw < prctile(low_raw(:), 20);
        %         maskHigh = high_raw < prctile(high_raw(:), 20);
        %     end
        % 
        %     % 유효점 존재 확인
        %     if nnz(maskLow) < 10 || nnz(maskHigh) < 10
        %         error('Not enough valid background points for interpolation.');
        %     end
        % 
        %     F_low = scatteredInterpolant(X(maskLow), Y(maskLow), low_raw(maskLow), 'linear', 'nearest');
        %     F_high = scatteredInterpolant(X(maskHigh), Y(maskHigh), high_raw(maskHigh), 'linear', 'nearest');
        % 
        %     bgLow = F_low(X, Y);
        %     bgHigh = F_high(X, Y);
        % 
        %     % NaN 보정
        %     bgLow(isnan(bgLow)) = min(low_raw(:), [], 'omitnan');
        %     bgHigh(isnan(bgHigh)) = min(high_raw(:), [], 'omitnan');
        % 
        %     % 크기 검사
        %     if ~isequal(size(bgLow), size(low_raw))
        %         error('bgLow size mismatch');
        %     end
        %     if ~isequal(size(bgHigh), size(high_raw))
        %         error('bgHigh size mismatch');
        %     end
        % 
        %     low_bgsub = low_raw - bgLow;
        %     high_bgsub = high_raw - bgHigh;

        case 'gauss'
            low_bgsub = low_raw - imgaussfilt(low_raw, 4);
            high_bgsub = high_raw - imgaussfilt(high_raw, 4);

        case 'polyfit2d'
            F_low = fit([X(:), Y(:)], low_raw(:), 'poly22');
            F_high = fit([X(:), Y(:)], high_raw(:), 'poly22');
            bgLow = reshape(F_low(X(:), Y(:)), rows, cols);
            bgHigh = reshape(F_high(X(:), Y(:)), rows, cols);
            low_bgsub = low_raw - bgLow;
            high_bgsub = high_raw - bgHigh;

        otherwise
            error('Unknown background subtraction method: %s', method);
    end

    % 클리핑
    low_bgsub(low_bgsub < 0) = 0;
    high_bgsub(high_bgsub < 0) = 0;
end
