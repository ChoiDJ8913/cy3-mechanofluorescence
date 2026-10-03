function [lowFrames, highFrames] = detect_stable_force_frames(instruments, numFrames, varargin)
% DETECT_STABLE_FORCE_FRAMES - Automatically selects stable low/high force frames
% Inputs:
%   instruments : struct with .F (magnet position), .Time (datetime)
%   numFrames   : number of frames in the movie (T)
%   varargin    : optional name-value pair: 'lowThresh', 'highThresh', 'deltaThresh', 'minDuration',
%                 'CalFile' (magnet-position-to-force calibration; default
%                 'CAL_M280_9.8mm_cube_Magnet_20250908.mat' on the MATLAB path)
% Output:
%   lowFrames   : vector of frame indices with stable low force
%   highFrames  : vector of frame indices with stable high force

% --- Parameters (modifiable) ---
lowThresh   = 6;
highThresh  = 12;
deltaThresh = 0.15;
minDuration = 8;
calFile     = 'CAL_M280_9.8mm_cube_Magnet_20250908.mat';

% Parse optional overrides
for i = 1:2:numel(varargin)
    switch lower(varargin{i})
        case 'lowthresh',   lowThresh = varargin{i+1};
        case 'highthresh',  highThresh = varargin{i+1};
        case 'deltathresh', deltaThresh = varargin{i+1};
        case 'minduration', minDuration = varargin{i+1};
        case 'calfile',     calFile = varargin{i+1};
    end
end

% --- Load calibration ---
cal = load(calFile);   % provides cal.T2F (force as a function of 25 - magnet position, mm)
magnetLength = posixtime(instruments.Time(end,1)) - posixtime(instruments.Time(1,1));
timeMagnet = linspace(0, magnetLength - 1, size(instruments.F,1));
timeVideo  = linspace(0, magnetLength - 1, numFrames);
magnet_interp = interp1(timeMagnet, instruments.F, timeVideo, 'linear');
y_force = cal.T2F(25 - magnet_interp(:));

% --- Detect stability ---
dy = [0; abs(diff(y_force))];
isLow  = (y_force < lowThresh)  & (dy < deltaThresh);
isHigh = (y_force > highThresh) & (dy < deltaThresh);

% --- Connected component labeling ---
lowFrames  = extract_long_runs(isLow,  minDuration);
highFrames = extract_long_runs(isHigh, minDuration);

end

%% Subfunction
function idx = extract_long_runs(mask, minLen)
    idx = [];
    cc = bwconncomp(mask);
    for i = 1:cc.NumObjects
        run = cc.PixelIdxList{i};
        if numel(run) >= minLen
            idx = [idx; run(:)];
        end
    end
end
