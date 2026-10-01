function values = otfs_tr_read_key_value_file(filePath, allowedKeys)
%otfs_tr_read_key_value_file Read a bounded UTF-8/GBK key=value TXT file.

filePath = string(filePath);
allowedKeys = string(allowedKeys);
if ~isscalar(filePath) || strlength(filePath) == 0 || ~isfile(filePath)
    error("otfs_tr:MissingSoftwareConfigFile", ...
        "Software configuration file does not exist: %s", filePath);
end
fileInfo = dir(filePath);
if fileInfo.bytes < 1 || fileInfo.bytes > 65536
    error("otfs_tr:InvalidSoftwareConfigSize", ...
        "Software configuration TXT must contain 1-65536 bytes.");
end
fileId = fopen(filePath, "rb");
if fileId < 0
    error("otfs_tr:UnreadableSoftwareConfigFile", ...
        "Cannot open software configuration file: %s", filePath);
end
fileCleanup = onCleanup(@() fclose(fileId));
bytes = fread(fileId, Inf, "*uint8").';
clear fileCleanup;
if numel(bytes) ~= fileInfo.bytes
    error("otfs_tr:IncompleteSoftwareConfigFile", ...
        "Software configuration file changed while being read.");
end

content = localDecodeText(bytes);
lines = splitlines(string(content));
values = struct();
for lineIndex = 1:numel(lines)
    line = strtrim(lines(lineIndex));
    if strlength(line) == 0 || startsWith(line, "#")
        continue;
    end
    separator = strfind(char(line), "=");
    if isempty(separator)
        error("otfs_tr:InvalidSoftwareConfigLine", ...
            "Line %d must use key=value syntax.", lineIndex);
    end
    key = strtrim(extractBefore(line, separator(1)));
    value = strtrim(extractAfter(line, separator(1)));
    if ~any(key == allowedKeys)
        error("otfs_tr:UnsupportedSoftwareConfigKey", ...
            "Unsupported software configuration key: %s", key);
    end
    if isfield(values, char(key))
        error("otfs_tr:DuplicateSoftwareConfigKey", ...
            "Duplicate software configuration key: %s", key);
    end
    values.(char(key)) = value;
end
end

function content = localDecodeText(bytes)
bytes = uint8(bytes(:).');
if numel(bytes) >= 3 && isequal(bytes(1:3), uint8([239 187 191]))
    bytes = bytes(4:end);
end
try
    candidate = native2unicode(bytes, "UTF-8");
    if isequal(uint8(unicode2native(candidate, "UTF-8")), bytes)
        content = candidate;
        return;
    end
catch
    % Invalid UTF-8 input is decoded using the supplied sample's GBK format.
end
content = native2unicode(bytes, "GBK");
end
