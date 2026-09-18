classdef otfsTrPairingTest < matlab.unittest.TestCase
    %otfsTrPairingTest Non-hardware tests for RX-owned run packages.

    methods (TestClassSetup)
        function addProjectPath(testCase)
            projectRoot = fileparts(fileparts(mfilename("fullpath")));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                projectRoot));
        end
    end

    methods (Test)
        function testPreparePairCreatesExpectedLayout(testCase)
            tempRoot = otfsTrPairingTest.createTemporaryRoot(testCase);
            cfg = otfs_tr_config();
            cfg.resultRoot = tempRoot;

            pair = otfs_tr_prepare_pair(cfg);

            testCase.verifyTrue(isfolder(pair.pairDirectory));
            testCase.verifyTrue(isfolder(pair.rxDirectory));
            testCase.verifyTrue(isfolder(pair.txDirectory));
            testCase.verifyTrue(isfolder(pair.reportDirectory));
            testCase.verifyTrue(isfile(pair.manifestFile));
            testCase.verifyEqual(pair.status, "waiting-for-capture");
            testCase.verifyEqual(string(pair.expectedReferenceFile), ...
                fullfile(pair.txDirectory, "reference_package.mat"));
        end

        function testFindLatestCompletePairSkipsNewerIncomplete(testCase)
            tempRoot = otfsTrPairingTest.createTemporaryRoot(testCase);
            olderPair = fullfile(tempRoot, "pairs", ...
                "20260918_100000_000");
            newerPair = fullfile(tempRoot, "pairs", ...
                "20260918_100100_000");
            otfsTrPairingTest.createPairFiles(olderPair, true);
            otfsTrPairingTest.createPairFiles(newerPair, false);

            [pairDirectory, referenceFile, captureFile] = ...
                otfs_tr_find_latest_pair(tempRoot);

            testCase.verifyEqual(pairDirectory, string(olderPair));
            testCase.verifyEqual(referenceFile, string(fullfile( ...
                olderPair, "tx", "reference_package.mat")));
            testCase.verifyEqual(captureFile, string(fullfile( ...
                olderPair, "rx", "rx_capture.mat")));
        end

        function testPartialReferenceIsNotComplete(testCase)
            tempRoot = otfsTrPairingTest.createTemporaryRoot(testCase);
            pairDirectory = fullfile(tempRoot, "pairs", ...
                "20260918_100000_000");
            otfsTrPairingTest.createPartialPair(pairDirectory);

            operation = @() otfs_tr_find_latest_pair(tempRoot);

            testCase.verifyError(operation, ...
                "otfs_tr:MissingCompletePair");
        end

        function testMissingCompletePairErrors(testCase)
            tempRoot = otfsTrPairingTest.createTemporaryRoot(testCase);

            operation = @() otfs_tr_find_latest_pair(tempRoot);

            testCase.verifyError(operation, ...
                "otfs_tr:MissingCompletePair");
        end
    end

    methods (Static, Access=private)
        function tempRoot = createTemporaryRoot(testCase)
            tempRoot = string(tempname);
            mkdir(tempRoot);
            testCase.addTeardown(@() rmdir(tempRoot, "s"));
        end

        function createPairFiles(pairDirectory, includeReference)
            mkdir(fullfile(pairDirectory, "rx"));
            mkdir(fullfile(pairDirectory, "tx"));
            otfsTrPairingTest.touch(fullfile( ...
                pairDirectory, "rx", "rx_capture.mat"));
            if includeReference
                otfsTrPairingTest.touch(fullfile( ...
                    pairDirectory, "tx", "reference_package.mat"));
            end
        end

        function createPartialPair(pairDirectory)
            mkdir(fullfile(pairDirectory, "rx"));
            mkdir(fullfile(pairDirectory, "tx"));
            otfsTrPairingTest.touch(fullfile( ...
                pairDirectory, "rx", "rx_capture.mat"));
            otfsTrPairingTest.touch(fullfile( ...
                pairDirectory, "tx", "reference_package.mat.partial"));
        end

        function touch(filePath)
            fileId = fopen(filePath, "w");
            cleaner = onCleanup(@() fclose(fileId));
            fwrite(fileId, uint8([]));
            clear cleaner;
        end
    end
end
