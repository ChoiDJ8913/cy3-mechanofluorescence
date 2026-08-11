function [Peaks, movie1, fileName,filePath] = MTFindPeaks(avgLim, PeakR, ROIR)
%% load the data file
[fileName, filePath] = uigetfile('*.mat', 'Select a MATLAB file');
if isequal(fileName, 0)
    disp('File selection cancelled.');
    return;
end
% load the selected data file
data = load(fullfile(filePath, fileName));
disp(fullfile(filePath, fileName))
% check that movie1 is present in the data
if ~isfield(data, 'movie1')
    error('Check file')
end
movie1 = double(data.movie1);


% build the output file name: append 'peak'
[~, nameOnly, ~] = fileparts(fileName); % strip the extension from the file name
saveFileName = fullfile(filePath, [nameOnly '_peak.mat']); % append 'peak'

%movie1 = movie1(:, :, 40:550 );
% movie1(:, :, 1:50 ) = [];
V = movie1;
h = size(movie1, 1);
w = size(movie1, 2);
N = size(movie1, 3);

%avgFrame = max(movie1, [], 3);
avgFrame = mean( movie1, 3 );
% avgLim = [ 180 200 ];

figure(1);
clf;
imagesc( avgFrame, avgLim );
hold on;
hBead = plot(  NaN ,  NaN , 'w', 'LineWidth', 2 );
hold off;
axis equal;
colormap(jet(256));

figure(2);
clf;
hFluor = plot( 1:N, NaN * zeros( 1, N ), 'r', 'LineWidth', 2 );
xlabel('Frame');
ylabel('Intensity (a.u.)');

figure(1);
title('Click a point ');
disp('Click a point');
while 1
    [gx, gy] = ginput( 1 );
    if numel(gx) > 0
        set( hFluor, 'YData', V( round(gy(1)), round(gx(1)), : ) );
    else
        break;
    end
end

ROIX = (1+w)/2;
ROIY = (1+h)/2;
% ROIR = 50; % 

% PeakR = 7; % peak radius
exR = PeakR + 1;

figure(1);
title('Click for an ROI');
disp('Click for an ROI');
while 1
    [gx, gy] = ginput( 1 );
    if numel(gx) > 0
        ROIX = gx(1);
        ROIY = gy(1);
        [ xdata, ydata ] = DrawCircle( ROIX, ROIY, ROIR, false );
        set( hBead, 'XData', xdata, 'YData', ydata );
    else
        break;
    end
end

[ X, Y ] = meshgrid( 1:w, 1:h );
V = avgFrame;
ind = find( (X-ROIX).^2 + (Y-ROIY).^2 < ROIR^2 );
ind(  V(ind) < avgLim(2)  ) = [];
[ sortV, sortI ] = sort( V(ind), 'descend' );
ind = ind(sortI);
ind0 = ind;

Peaks = zeros( 0, 2 );
while ~isempty(ind)
    cx = X(ind(1));
    cy = Y(ind(1));
    ci =  (X(ind0)-cx).^2 + (Y(ind0)-cy).^2 <= exR^2 ;
    if V(cy, cx) >= max( V(ind0(ci)) )
        Peaks(end+1, :) = [ cx cy ];
        ind(  (X(ind)-cx).^2 + (Y(ind)-cy).^2 <= exR^2  ) = [];
    else
        ind(1) = [];
    end
end
NPeaks = size(Peaks, 1);



% Correct Peaks
[ PX, PY ] = meshgrid( -exR:exR, -exR:exR );
PeakI = find( PX.^2 + PY.^2 <= PeakR^2 );
exI = find( PX.^2 + PY.^2 <= exR^2 );
bgI = setdiff(exI, PeakI);
for i = 1:NPeaks
    xi = Peaks(i, 1);
    yi = Peaks(i, 2);

    ind = h * ( xi+PX(PeakI) -1 ) + yi+PY(PeakI);
    bg = median( V(ind) );
    Vbgsub = max( V(ind)-bg, 0 );
    cx = sum( X(ind) .* Vbgsub )/sum(Vbgsub);
    cy = sum( Y(ind) .* Vbgsub )/sum(Vbgsub);
    %disp( num2str(Peaks(i, :)) );
    %disp( num2str( [ cx cy ] ) );
    Peaks(i, :) = [ cx cy ];
end

figure(1);
title('Peaks');
%clf;
%imagesc( avgFrame, avgLim );
hold on;
for i = 1:NPeaks
    DrawCircle( Peaks(i, 1), Peaks(i, 2), exR );
end
hold off;
axis equal;
colormap(jet(256));

minX = min( Peaks(:, 1) ) - exR;
maxX = max( Peaks(:, 1) ) + exR;
minY = min( Peaks(:, 2) ) - exR;
maxY = max( Peaks(:, 2) ) + exR;
axis( [ minX maxX minY maxY ] );
% save( 'Peaks.mat', 'Peaks' );
save(saveFileName, 'Peaks');
disp(['Peaks saved to: ' saveFileName]);


return;


function [ xdata, ydata ] = DrawCircle(x, y, r, flag, c, w)
xdata = x + r*cos(2*pi*(0:0.05:1));
ydata = y + r*sin(2*pi*(0:0.05:1));
if nargin < 4
    flag = true;
end
if nargin < 5
    c = [ 1 1 1 ];
end
if nargin < 6
    w = 2;
end

if flag
    plot( xdata, ydata, '-', 'Color', c, 'LineWidth', w );
end
return;
