function otfs_tr_write_key_value_atomic(filePath, values, fieldNames)
%otfs_tr_write_key_value_atomic Atomically publish a UTF-8 key=value file.

filePath = string(filePath);
if strlength(filePath) == 0
    return;
end
validateattributes(values, {'struct'}, {'scalar'});
fieldNames = string(fieldNames);
lines = strings(numel(fieldNames), 1);
for fieldIndex = 1:numel(fieldNames)
    fieldName = fieldNames(fieldIndex);
    if ~isfield(values, fieldName)
        error("otfs_tr:InvalidKeyValueText", ...
            "Required key=value field is missing: %s", fieldName);
    end
    lines(fieldIndex) = fieldName + "=" + ...
        localValueText(values.(fieldName));
end

folder = string(fileparts(filePath));
if strlength(folder) > 0 && ~isfolder(folder)
    mkdir(folder);
end
temporaryFile = string(tempname(folder)) + ".txt";
cleanup = onCleanup(@() localDeleteTemporaryFile(temporaryFile));
writelines(lines, temporaryFile, Encoding="UTF-8");
moved = false;
message = "";
for attempt = 1:5
    [moved, message] = movefile(temporaryFile, filePath, "f");
    if moved
        break;
    end
    pause(0.02*attempt);
end
if ~moved
    error("otfs_tr:KeyValueTextWriteFailed", ...
        "Could not replace key=value file %s: %s", ...
        char(filePath), char(message));
end
clear cleanup;
end

function valueText = localValueText(value)
if islogical(value) && isscalar(value)
    valueText = string(double(value));
elseif isnumeric(value) && isscalar(value)
    valueText = string(sprintf("%.17g", double(value)));
elseif (isstring(value) || ischar(value)) && isscalar(string(value))
    valueText = string(value);
else
    error("otfs_tr:InvalidKeyValueText", ...
        "Values must be scalar text, numeric, or logical values.");
end
if contains(valueText, newline) || contains(valueText, char(13)) || ...
        contains(valueText, "=")
    error("otfs_tr:InvalidKeyValueText", ...
        "Values cannot contain line breaks or equals signs.");
end
end

function localDeleteTemporaryFile(filePath)
if isfile(filePath)
    delete(filePath);
end
end
