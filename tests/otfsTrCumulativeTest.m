classdef otfsTrCumulativeTest < matlab.unittest.TestCase
    %otfsTrCumulativeTest Verify BER accumulation across short captures.

    methods (TestClassSetup)
        function addProjectPath(testCase)
            projectRoot = fileparts(fileparts(mfilename("fullpath")));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                projectRoot));
        end
    end

    methods (Test)
        function testAccumulatesEveryRoundWithoutCrossRoundFrameDedup(testCase)
            % Arrange.
            cfg = otfs_tr_config();
            cfg.superframeLength = 8;
            cfg.targetDecodedFrames = 6;
            cfg.minimumTestBits = 6;
            stateDirectory = testCase.createProjectTempDirectory();
            stateFile = fullfile(stateDirectory, "cumulative.mat");
            first = otfsTrCumulativeTest.resultForFrames( ...
                [0 1], {[false; false], [false; true]}, "run-1");
            second = otfsTrCumulativeTest.resultForFrames( ...
                [1 2], {[true; true], [false; false]}, "run-2");

            % Act.
            otfs_tr_accumulate_results(stateFile, first, cfg);
            cumulative = otfs_tr_accumulate_results( ...
                stateFile, second, cfg);

            % Assert.
            testCase.verifyEqual(cumulative.batchCount, 2);
            testCase.verifyEqual(cumulative.accumulationMode, "per-round");
            testCase.verifyEqual(cumulative.validFrames, 4);
            testCase.verifyEqual(cumulative.testedBits, 8);
            testCase.verifyEqual(cumulative.bitErrors, 3);
            testCase.verifyEqual(cumulative.newValidFrames, 2);
            testCase.verifyEqual(cumulative.newTestedBits, 4);
            testCase.verifyEqual(cumulative.newBitErrors, 2);
            testCase.verifyEqual(cumulative.ber, 3/8, AbsTol=0);
            testCase.verifyTrue(cumulative.targetReached);
            testCase.verifyTrue(isfile(cumulative.jsonFile));
            testCase.verifyTrue(isfile(cumulative.textFile));
            cumulativeText = otfs_tr_read_key_value_file( ...
                cumulative.textFile, ["version", "accumulationMode", ...
                "batchCount", ...
                "validFrames", "testedBits", "bitErrors", ...
                "newValidFrames", "newTestedBits", "newBitErrors", "ber", ...
                "zeroErrorUpper95", "targetReached", ...
                "latestRunId", "updatedAt"]);
            testCase.verifyEqual(cumulativeText.accumulationMode, "per-round");
            testCase.verifyEqual(str2double(cumulativeText.testedBits), 8);
            testCase.verifyEqual(str2double(cumulativeText.bitErrors), 3);
        end

        function testRejectsDuplicateRoundSubmission(testCase)
            % Arrange.
            cfg = otfs_tr_config();
            stateDirectory = testCase.createProjectTempDirectory();
            stateFile = fullfile(stateDirectory, "cumulative.mat");
            result = otfsTrCumulativeTest.resultForFrames( ...
                0, {[false; false]}, "run-1");

            % Act.
            otfs_tr_accumulate_results(stateFile, result, cfg);
            operation = @() otfs_tr_accumulate_results( ...
                stateFile, result, cfg);

            % Assert.
            testCase.verifyError(operation, ...
                "otfs_tr:DuplicateCumulativeRound");
        end
    end

    methods (Access=private)
        function directory = createProjectTempDirectory(testCase)
            projectRoot = fileparts(fileparts(mfilename("fullpath")));
            directory = string(tempname(fullfile(projectRoot, "results")));
            mkdir(directory);
            testCase.addTeardown(@() rmdir(directory, "s"));
        end
    end

    methods (Static, Access=private)
        function result = resultForFrames(frameIds, errors, runId)
            frameIds = frameIds(:);
            diagnostics = repmat(struct("bitErrors", false(0, 1)), ...
                numel(frameIds), 1);
            for index = 1:numel(frameIds)
                diagnostics(index).bitErrors = logical(errors{index});
            end
            result = struct("referenceMode", "unique-superframe", ...
                "frameIds", frameIds, ...
                "frameBer", zeros(numel(frameIds), 1), ...
                "frameDiagnostics", diagnostics, ...
                "localRunId", runId, ...
                "validFrames", numel(frameIds), ...
                "totalBits", sum(cellfun(@numel, errors)), ...
                "totalErrors", sum(cellfun(@sum, errors)));
        end
    end
end
