function otfs_tr_write_json_atomic(filePath, value)
%otfs_tr_write_json_atomic Replace a JSON file without exposing partial text.

filePath = string(filePath);
if strlength(filePath) == 0
    return;
end
folder = string(fileparts(filePath));
if strlength(folder) > 0 && ~isfolder(folder)
    mkdir(folder);
end
temporaryFile = string(tempname(folder)) + ".json";
cleanup = onCleanup(@() localDeleteTemporaryFile(temporaryFile));
writelines(jsonencode(value, PrettyPrint=true), temporaryFile);
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
    error("otfs_tr:ProgressWriteFailed", ...
        "Could not replace JSON file %s: %s", ...
        char(filePath), char(message));
end
clear cleanup;
end

function localDeleteTemporaryFile(filePath)
if isfile(filePath)
    delete(filePath);
end
end
