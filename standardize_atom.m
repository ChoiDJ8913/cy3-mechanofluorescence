function A = standardize_atom(a)
    % normalise the label: strip spaces/underscores/hyphens, lowercase, then map by rule
    s = lower(regexprep(string(a), '[\s_\-]+', ''));
    A = strings(size(s));
    for i = 1:numel(s)
        t = s(i);
        if t=="nl" || t=="nleft"
            A(i) = "NL";
        elseif t=="nr" || t=="nright"
            A(i) = "NR";
        elseif t=="cl"
            A(i) = "CL";
        elseif t=="cr"
            A(i) = "CR";
        elseif startsWith(t,"cl") && strlength(t) > 2
            A(i) = upper("CL" + extractAfter(t,2));   % CL1, CL2...
        elseif startsWith(t,"cr") && strlength(t) > 2
            A(i) = upper("CR" + extractAfter(t,2));   % CR1, CR2...
        elseif startsWith(t,"c") && strlength(t) >= 2 && all(isstrprop(extractAfter(t,1),'digit'))
            A(i) = upper("C" + extractAfter(t,1));    % C1..C5
        else
            A(i) = upper(t);                           % everything else is preserved
        end
    end
end
