function results = run_all_tests()
%run_all_tests Run the OTFS-TR class-based non-hardware test suite.

projectRoot = fileparts(mfilename("fullpath"));
suite = testsuite(fullfile(projectRoot, "tests"), ...
    "IncludeSubfolders", true);
results = run(suite);
assertSuccess(results);
end
