%% cy3_panel_C_fig3_v10.m
% reproduces the original exactly:
% phi1: blue  solid   + circle    (o)
% phi2: orange dashed + square    (s)
% phi3: green  dashed + triangle  (^)
% phi4: purple dotted + diamond   (d)
% x axis: -160 to 160
% dxeff label: black, without the +/- , "dxeff = 1.09 A"

clear; clc;

xlsxFile      = '5ns4_xyz.xlsx';
phiScan       = (-180:1:180)';
Delta_xeff    = 1.09;
Delta_xeff_sd = 0.51;

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

% Shaded band
fill(ax,[-180 180 180 -180], ...
    [Delta_xeff-Delta_xeff_sd Delta_xeff-Delta_xeff_sd ...
     Delta_xeff+Delta_xeff_sd Delta_xeff+Delta_xeff_sd], ...
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

% Annotation: BLACK, no ±, inside shaded band lower-left
text(ax,-150,Delta_xeff-Delta_xeff_sd-0.10, ...
    'Δx_e_f_f = 1.09 Å', ...
    'FontName','Arial','FontSize',8,'Color',[0.10 0.10 0.10], ...
    'HorizontalAlignment','left','Interpreter','tex');

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

annotation(fig,'textbox',[0.01 0.91 0.07 0.08],'String','C', ...
    'FontName','Arial','FontSize',10,'FontWeight','bold', ...
    'EdgeColor','none','FitBoxToText','on');

hold(ax,'off');
exportgraphics(fig,'fig3_panelC_v10.pdf','ContentType','vector');
exportgraphics(fig,'fig3_panelC_v10.png','Resolution',600);
fprintf('Saved: fig3_panelC_v10.pdf  +  fig3_panelC_v10.png (600 dpi)\n');

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