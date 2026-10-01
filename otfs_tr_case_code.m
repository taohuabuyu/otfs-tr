function code = otfs_tr_case_code(caseId)
%otfs_tr_case_code Map a human-readable case_id to its 32-bit air code.

caseId = string(caseId);
if ~isscalar(caseId) || isempty(regexp(caseId, ...
        "^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$", "once"))
    error("otfs_tr:InvalidTestCaseId", ...
        "case_id must contain 1-64 safe characters.");
end
code = otfs_tr_crc32(unicode2native(char(caseId), "UTF-8"));
end
