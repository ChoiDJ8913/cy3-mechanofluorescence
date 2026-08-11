function T = read_table_flex(file)
[~,~,ext] = fileparts(file);
switch lower(ext)
    case {'.xlsx','.xls'}
        opts = detectImportOptions(file, 'VariableNamingRule','preserve');
        % force the candidate label columns to string
        vnames = string(opts.VariableNames);
        normnm = lower(regexprep(vnames,'[\s_-]+',''));
        cand = ["coord","atom","label","name","atomname"];
        for c = cand
            hit = find(normnm==c, 1, 'first');
            if ~isempty(hit)
                opts = setvartype(opts, vnames(hit), 'string');
            end
        end
        % force x,y,z to numeric
        for k = ["x","y","z"]
            hit = find(normnm==k, 1, 'first');
            if ~isempty(hit)
                opts = setvartype(opts, vnames(hit), 'double');
            end
        end
        T = readtable(file, opts);

    case '.csv'
        try
            T = readtable(file,'VariableNamingRule','preserve','FileType','text');
        catch
            T = readtable(file,'VariableNamingRule','preserve');
        end
    otherwise
        error('Unsupported file: %s',ext);
end
end
