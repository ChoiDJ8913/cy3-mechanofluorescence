%% cy3_panel_D_fig3_v8.m
% Figure 3D: projected displacement of the Cy3 attachment-point distance
% versus bridge-bond torsion angle (phi1-phi4), PDB 5NS4.
% Changes from cy3_panel_C_fig3_v7.m (curves, colours and axes unchanged):
%   - Shaded band = +/- SE of the Bell-model fit (Figure 3C), computed below
%     from the Origin linear-fit output. v7 hard-coded 0.51 A, which does not
%     correspond to any fit output (the fit SE is 0.0515 A).
%   - Label moved to the centre, above the band (the narrow band no longer
%     leaves room at the lower left without overlapping the phi1/phi4 curves).
%   - Panel letter C -> D; output file names -> fig3_panelD_v11.*
% phi1: blue  solid   + circle    (o)
% phi2: orange dashed + square    (s)
% phi3: green  dashed + triangle  (^)
% phi4: purple dotted + diamond   (d)
% x axis: -160 to 160

clear; clc;

xlsxFile      = '5ns4_xyz.xlsx';
phiScan       = (-180:1:180)';

% Bell-model fit of ln[I(F)/I(F0)] vs F (Figure 3C; OriginPro 2019 Linear Fit,
% N-weighted pooled Up/Down mean, 5.1-27.3 pN, weights 1/sigma^2):
fitSlope    = -0.02655;          % pN^-1
fitSlopeSE  =  0.00125;          % pN^-1 (scaled by sqrt of reduced chi-sqr)
T_K         = 298.15;            % 25 degC
kBT_pNA     = 1.380649e-23*T_K*1e22;         % pN*Angstrom (= 41.16)
Delta_xeff    = -fitSlope*kBT_pNA;           % 1.093 A
Delta_xeff_se =  fitSlopeSE*kBT_pNA;         % 0.0515 A
fprintf('Delta_xeff = %.3f +/- %.3f A (slope +/- SE, kBT = %.2f pN*A)\n', ...
        Delta_xeff, Delta_xeff_se, kBT_pNA);

chainAtoms = ["CAZ","NAU","CAG","CAH","CAI","CAJ","CAK","NAV","CBA"];
nChain=9;
axisBonds  = [3 4; 4 5; 5 6; 6 7];
downRanges = {4:9, 5:9, 6:9, 7:9};

T = readtable(xlsxFile,'VariableNamingRule','preserve');
T.Properties.VariableNames = {'cy3','atom','x','y','z'};
xyzChain = zeros(nChain,3);
for i=1:nChain
    row=strcmp(T.atom,chainAtoms(i));
    xyzChain(i,:)=table2array(T(row,{'x','y','z'}));
end
d0=norm(xyzChain(1,:)-xyzChain(9,:));
nPhi=numel(phiScan);

dxCC=zeros(nPhi,4);
for k=1:4
    for i=1:nPhi
        xyzS=rotate_subset(xyzChain,axisBonds(k,1),axisBonds(k,2),downRanges{k},phiScan(i));
        dxCC(i,k)=norm(xyzS(1,:)-xyzS(9,:))-d0;
    end
end

% Structural estimate quoted in the text: change in the CAZ-CBA distance at
% +/-90 deg rotation (phi1: 1.52/1.54 A; phi4: 1.51/1.57 A)
for k=1:4
    fprintf('phi%d: dx(+90) = %.3f A, dx(-90) = %.3f A\n', k, ...
        dxCC(phiScan==90,k), dxCC(phiScan==-90,k));
end

%% style - as in the original
colors = [0.000 0.447 0.741;   % phi1 blue
          0.855 0.412 0.020;   % phi2 orange
          0.600 0.601 0.020;   % phi3 green
          0.494 0.184 0.556];  % phi4 purple

lineStyles = {'-', '--', '--', ':'};
markers    = {'o', 's',  '^',  'd'};
mSizes     = [ 5,   5,    5,    6 ];
step=20;
mkIdx=unique([1,(1:step:nPhi),nPhi]);

%% Figure
fig=figure('Color','w');
fig.Units='centimeters';
fig.Position=[2 2 13.0 7.0];

ax=axes('Parent',fig);
ax.Units='centimeters';
ax.Position=[1.9 1.3 8.8 5.0];
hold(ax,'on'); box(ax,'on');

% Shaded band: +/- SE of the fitted Delta_xeff
fill(ax,[-180 180 180 -180], ...
    [Delta_xeff-Delta_xeff_se Delta_xeff-Delta_xeff_se ...
     Delta_xeff+Delta_xeff_se Delta_xeff+Delta_xeff_se], ...
    [0.80 0.80 0.80],'EdgeColor','none','FaceAlpha',0.60);

% Dotted Δxeff line (black)
plot(ax,[-180 180],[Delta_xeff Delta_xeff],':', ...
    'Color',[0.10 0.10 0.10],'LineWidth',0.8,'HandleVisibility','off');

% Zero line
plot(ax,[-180 180],[0 0],'-', ...
    'Color',[0.72 0.72 0.72],'LineWidth',0.5,'HandleVisibility','off');

% Data curves
hLines=gobjects(1,4);
for k=1:4
    hLines(k)=plot(ax,phiScan,dxCC(:,k), ...
        lineStyles{k}, ...
        'Color',colors(k,:),'LineWidth',1.3, ...
        'Marker',markers{k},'MarkerIndices',mkIdx, ...
        'MarkerSize',mSizes(k), ...
        'MarkerFaceColor','w','MarkerEdgeColor',colors(k,:), ...
        'DisplayName',['φ' num2str(k)]);
end

% Annotation: BLACK, no +/-, centred just above the band
text(ax,0,Delta_xeff+Delta_xeff_se+0.08, ...
    'Δx_e_f_f = 1.09 Å', ...
    'FontName','Arial','FontSize',8,'Color',[0.10 0.10 0.10], ...
    'HorizontalAlignment','center','VerticalAlignment','bottom', ...
    'Interpreter','tex');

%% Formatting
xlim(ax,[-160 160]);
ylim(ax,[-0.5 3.0]);
xticks(ax,-150:50:150);
xticklabels(ax,{'-150','-100','-50','0','50','100','150'});
yticks(ax,-0.5:0.5:3.0);
ax.FontName='Arial'; ax.FontSize=7; ax.LineWidth=0.75;
ax.TickDir='out'; ax.TickLength=[0.010 0.010];

xlabel(ax,'Torsion angle (°)','FontName','Arial','FontSize',8);
ylabel(ax,'Δx (Å)','FontName','Arial','FontSize',8);

legend(ax,hLines,'Location','eastoutside','FontName','Arial', ...
    'FontSize',7,'Box','off','Interpreter','tex');

annotation(fig,'textbox',[0.01 0.91 0.07 0.08],'String','D', ...
    'FontName','Arial','FontSize',10,'FontWeight','bold', ...
    'EdgeColor','none','FitBoxToText','on');

hold(ax,'off');
exportgraphics(fig,'fig3_panelD_v11.pdf','ContentType','vector');
exportgraphics(fig,'fig3_panelD_v11.png','Resolution',600);
fprintf('Saved: fig3_panelD_v11.pdf  +  fig3_panelD_v11.png (600 dpi)\n');

function xyzOut=rotate_subset(xyzIn,idxA,idxB,moveIdx,thetaDeg)
    p0=xyzIn(idxA,:); p1=xyzIn(idxB,:);
    u=(p1-p0)/norm(p1-p0);
    th=deg2rad(thetaDeg); c=cos(th); s=sin(th);
    xyzOut=xyzIn;
    P=xyzIn(moveIdx,:)-p0;
    ud=repmat(u,numel(moveIdx),1);
    Prot=P*c+cross(ud,P,2)*s+ud.*(sum(P.*ud,2)*(1-c));
    xyzOut(moveIdx,:)=Prot+p0;
end